import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/observability/sentry_logger_bridge.dart';
import '../../../core/observability/sentry_scope.dart';
import '../../../core/observability/sentry_tracing.dart';
import '../../../core/supabase/supabase_failure.dart';
import '../domain/auth_repository.dart';
import 'native_google_sign_in.dart';

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(
    this._client,
    this._googleSignIn, {
    required this.onAccountDeletionPrepared,
    required this.onAccountDeletionCancelled,
    required this.onAccountDeleted,
  });

  final SupabaseClient _client;
  final GoogleSignInGateway _googleSignIn;
  final Future<void> Function(String userId) onAccountDeletionPrepared;
  final Future<void> Function(String userId) onAccountDeletionCancelled;
  final Future<void> Function(String userId) onAccountDeleted;

  @override
  AuthSession? get currentSession =>
      _sessionFromSupabase(_client.auth.currentSession);

  @override
  Stream<AuthStateChange> watchAuthState() async* {
    var previous = AuthStateChange(
      event: AuthEventType.initialSession,
      session: currentSession,
    );
    unawaited(_recordAuthState(previous));
    yield previous;
    await for (final state in _client.auth.onAuthStateChange) {
      final next = AuthStateChange(
        event: _eventFromSupabase(state.event),
        session: _sessionFromSupabase(state.session),
      );
      if (!next.hasSameIdentityAndEvent(previous)) {
        unawaited(_recordAuthState(next));
        yield next;
      }
      previous = next;
    }
  }

  @override
  Future<void> signInWithGoogle() async {
    try {
      await traceHomePilotOperation<void>(
        'auth.google_sign_in',
        () async {
          final tokens = await _googleSignIn.signIn();
          await traceHomePilotOperation<void>(
            'auth.supabase_token_exchange',
            () async {
              await _client.auth.signInWithIdToken(
                provider: OAuthProvider.google,
                idToken: tokens.idToken,
                accessToken: tokens.accessToken,
              );
            },
            attributes: const {'provider': 'google', 'execution': 'main'},
          );
        },
        attributes: const {'provider': 'google', 'execution': 'main'},
      );
      await setSentryAuthenticated(
        authenticated: true,
        event: 'auth.signed_in',
      );
    } on Object catch (error, stackTrace) {
      final failure = SupabaseFailure.from(error);
      reportOperationFailure(
        operation: 'auth_google_sign_in_failed',
        error: failure,
        stackTrace: stackTrace,
        fields: const {'provider': 'google', 'execution': 'main'},
      );
      await _throwAuthFailure(error);
    }
  }

  @override
  Future<void> signOut({bool allDevices = false}) async {
    try {
      await traceHomePilotOperation<void>('auth.sign_out', () async {
        await _client.auth.signOut(
          scope: allDevices ? SignOutScope.global : SignOutScope.local,
        );
        await _googleSignIn.signOut();
      }, attributes: const {'provider': 'google', 'execution': 'main'});
      await clearSentryAccountScope(event: 'auth.signed_out');
    } on Object catch (error, stackTrace) {
      final failure = SupabaseFailure.from(error);
      reportOperationFailure(
        operation: 'auth_sign_out_failed',
        error: failure,
        stackTrace: stackTrace,
        fields: const {'provider': 'google', 'execution': 'main'},
      );
      throw failure;
    }
  }

  @override
  Future<void> deleteAccount() async {
    try {
      await traceHomePilotOperation<void>(
        'auth.account_delete',
        _deleteAccount,
        attributes: const {'provider': 'google', 'execution': 'main'},
      );
      await clearSentryAccountScope(event: 'auth.account_deleted');
    } on Object catch (error, stackTrace) {
      final failure = SupabaseFailure.from(error);
      reportOperationFailure(
        operation: 'auth_account_delete_failed',
        error: failure,
        stackTrace: stackTrace,
        fields: const {'provider': 'google', 'execution': 'main'},
      );
      throw failure;
    }
  }

  Future<void> _deleteAccount() async {
    var cloudDeleted = false;
    var deletionPrepared = false;
    String? originalUserId;
    try {
      originalUserId = _client.auth.currentSession?.user.id;
      if (originalUserId == null) {
        throw const SupabaseFailure(
          kind: SupabaseFailureKind.authentication,
          message: 'Sign in again before deleting your account.',
        );
      }

      final tokens = await _googleSignIn.signIn();
      final reauthenticated = await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: tokens.idToken,
        accessToken: tokens.accessToken,
      );
      if (reauthenticated.session?.user.id != originalUserId) {
        await _clearLocalAuthentication();
        throw const SupabaseFailure(
          kind: SupabaseFailureKind.permissionDenied,
          message:
              'Authenticate with the same Google account before deleting it.',
        );
      }

      await onAccountDeletionPrepared(originalUserId);
      deletionPrepared = true;
      final response = await _client.functions.invoke(
        'delete-account',
        body: const {'confirmation': 'delete-my-account'},
      );
      final data = response.data;
      if (data is! Map || data['deleted'] != true) {
        throw const SupabaseFailure(
          kind: SupabaseFailureKind.unknown,
          message: 'The cloud account could not be deleted.',
        );
      }
      cloudDeleted = true;
      final deletedUserId = data['user_id'] is String
          ? data['user_id'] as String
          : originalUserId;
      final status = data['status'];
      if (deletedUserId != originalUserId ||
          (status != null &&
              status != 'deleted' &&
              status != 'already_deleted')) {
        throw const SupabaseFailure(
          kind: SupabaseFailureKind.unknown,
          message: 'The cloud account deletion receipt was invalid.',
        );
      }
      try {
        await traceHomePilotOperation<void>(
          'auth.account_delete.local_cleanup',
          () async => onAccountDeleted(originalUserId!),
          attributes: const {'execution': 'main'},
        );
      } on Object {
        throw const SupabaseFailure(
          kind: SupabaseFailureKind.unknown,
          message:
              'The account was deleted, but local cleanup is still pending. '
              'Restart HomePilot to finish cleanup.',
          retryable: true,
        );
      } finally {
        await _clearLocalAuthentication(isAccountDeletion: true);
      }
    } on Object catch (error) {
      if (cloudDeleted) {
        await _clearLocalAuthentication(isAccountDeletion: true);
        throw SupabaseFailure.from(error);
      }
      final functionErrorCode = _functionErrorCode(error);
      if (deletionPrepared && originalUserId != null) {
        await _cancelPreparedDeletion(originalUserId);
      }
      if (functionErrorCode == 'recent_reauthentication_required') {
        throw const SupabaseFailure(
          kind: SupabaseFailureKind.authentication,
          message: 'Authenticate with Google again, then retry deletion.',
        );
      }
      if (functionErrorCode == 'storage_cleanup_failed') {
        throw const SupabaseFailure(
          kind: SupabaseFailureKind.storage,
          message:
              'Private media cleanup did not finish. Sign in and retry '
              'account deletion.',
          retryable: true,
        );
      }
      await _throwAuthFailure(error);
    }
  }

  Future<void> _cancelPreparedDeletion(String userId) async {
    try {
      await onAccountDeletionCancelled(userId);
    } on Object catch (error, stackTrace) {
      reportOperationFailure(
        operation: 'auth_account_delete_cancel_cleanup_failed',
        error: error,
        stackTrace: stackTrace,
        fields: const {'execution': 'main'},
      );
      // Preserve the original remote deletion failure for the caller.
    }
  }

  Future<void> _clearLocalAuthentication({
    bool isAccountDeletion = false,
  }) async {
    try {
      await _client.auth.signOut(scope: SignOutScope.local);
    } on Object {
      // GoTrue normally clears local state before any remote work.
    }
    try {
      if (isAccountDeletion) {
        try {
          await _googleSignIn.disconnect();
        } on Object {
          await _googleSignIn.signOut();
        }
      } else {
        await _googleSignIn.signOut();
      }
    } on Object {
      // Supabase recovery must not depend on Google cleanup.
    }
    try {
      await clearSentryAccountScope(event: 'auth.signed_out');
    } on Object {
      // Observability must never prevent local authentication cleanup.
    }
  }

  Future<Never> _throwAuthFailure(Object error) async {
    if (_isRevokedSessionError(error)) {
      try {
        await _client.auth.signOut(scope: SignOutScope.local);
      } on Object {
        // GoTrue removes local session state before contacting the server.
      }
      try {
        await _googleSignIn.signOut();
      } on Object {
        // Supabase recovery must not depend on Google cleanup.
      }
      try {
        await clearSentryAccountScope(event: 'auth.signed_out');
      } on Object {
        // Observability must never block session recovery.
      }
    }
    throw SupabaseFailure.from(error);
  }

  Future<void> _recordAuthState(AuthStateChange state) async {
    final event = switch (state.event) {
      AuthEventType.initialSession => 'auth.initial_session',
      AuthEventType.signedIn => 'auth.signed_in',
      AuthEventType.signedOut => 'auth.signed_out',
      AuthEventType.tokenRefreshed => 'auth.token_refreshed',
      AuthEventType.userDeleted => 'auth.account_deleted',
      _ => 'auth.state_changed',
    };
    try {
      if (state.session == null ||
          state.event == AuthEventType.signedOut ||
          state.event == AuthEventType.userDeleted) {
        await clearSentryAccountScope(event: event);
      } else {
        await setSentryAuthenticated(authenticated: true, event: event);
      }
    } on Object {
      // Scope updates are best-effort and must not affect auth state delivery.
    }
  }
}

AuthEventType _eventFromSupabase(AuthChangeEvent event) {
  return switch (event.name) {
    'initialSession' => AuthEventType.initialSession,
    'signedIn' => AuthEventType.signedIn,
    'signedOut' => AuthEventType.signedOut,
    'tokenRefreshed' => AuthEventType.tokenRefreshed,
    'userUpdated' => AuthEventType.userUpdated,
    'userDeleted' => AuthEventType.userDeleted,
    'mfaChallengeVerified' => AuthEventType.mfaChallengeVerified,
    _ => AuthEventType.initialSession,
  };
}

AuthSession? _sessionFromSupabase(Session? session) {
  final user = session?.user;
  if (user == null) {
    return null;
  }
  final metadata = user.userMetadata;
  final providers = <String>{
    for (final identity in user.identities ?? const <UserIdentity>[])
      identity.provider,
  };
  final appProvider = user.appMetadata['provider'] as String?;
  if (appProvider != null) {
    providers.add(appProvider);
  }
  if (!providers.contains('google')) {
    return null;
  }
  final fullName = metadata?['full_name'] as String?;
  final name = metadata?['name'] as String?;
  return AuthSession(
    userId: user.id,
    email: user.email,
    fullName: fullName,
    name: name,
    avatarUrl:
        metadata?['avatar_url'] as String? ?? metadata?['picture'] as String?,
    providers: providers,
  );
}

bool _isRevokedSessionError(Object error) {
  final (String? code, String message) = switch (error) {
    AuthException value => (value.code, value.message),
    PostgrestException value => (value.code, value.message),
    _ => (null, ''),
  };
  final normalized = '${code ?? ''} $message'.toLowerCase();
  return normalized.contains('session_not_found') ||
      normalized.contains('session from session_id claim') ||
      normalized.contains('session id claim in jwt does not exist');
}

String? _functionErrorCode(Object error) {
  if (error is! FunctionException) return null;
  final details = error.details;
  if (details is Map && details['error'] is String) {
    return details['error'] as String;
  }
  return null;
}
