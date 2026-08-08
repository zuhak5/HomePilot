import 'package:flutter_test/flutter_test.dart';
import 'package:homepilot/src/core/supabase/supabase_failure.dart';
import 'package:homepilot/src/features/auth/data/native_google_sign_in.dart';
import 'package:homepilot/src/features/auth/data/supabase_auth_repository.dart';
import 'package:homepilot/src/features/auth/domain/auth_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _MockGoTrueClient extends Mock implements GoTrueClient {}

class _MockFunctionsClient extends Mock implements FunctionsClient {}

class _MockSession extends Mock implements Session {}

class _MockUser extends Mock implements User {}

class _FakeGoogleSignInGateway implements GoogleSignInGateway {
  Object? signInError;
  var signInCalls = 0;
  var signOutCalls = 0;

  @override
  Future<GoogleSignInTokens> signIn() async {
    signInCalls++;
    final error = signInError;
    if (error != null) {
      throw error;
    }
    return const GoogleSignInTokens(
      idToken: 'google-id-token',
      accessToken: 'google-access-token',
    );
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
  }

  @override
  Future<void> disconnect() async {
    signOutCalls++;
  }
}

void main() {
  late _FakeGoogleSignInGateway googleSignIn;

  setUpAll(() {
    registerFallbackValue(OAuthProvider.google);
  });

  setUp(() {
    googleSignIn = _FakeGoogleSignInGateway();
  });

  test('repository exposes no session for a fresh client', () {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'sb_publishable_test',
    );
    final repository = SupabaseAuthRepository(
      client,
      googleSignIn,
      onAccountDeletionPrepared: (_) async {},
      onAccountDeletionCancelled: (_) async {},
      onAccountDeleted: (_) async {},
    );

    expect(repository.currentSession, isNull);
  });

  test('auth stream immediately replays the current session state', () async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'sb_publishable_test',
    );
    final repository = SupabaseAuthRepository(
      client,
      googleSignIn,
      onAccountDeletionPrepared: (_) async {},
      onAccountDeletionCancelled: (_) async {},
      onAccountDeleted: (_) async {},
    );

    final state = await repository.watchAuthState().first;

    expect(state.event, AuthEventType.initialSession);
    expect(state.session, isNull);
  });

  test('native Google tokens are exchanged for a Supabase session', () async {
    final client = _MockSupabaseClient();
    final auth = _MockGoTrueClient();
    when(() => client.auth).thenReturn(auth);
    when(
      () => auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: 'google-id-token',
        accessToken: 'google-access-token',
      ),
    ).thenAnswer((_) async => AuthResponse());
    final repository = SupabaseAuthRepository(
      client,
      googleSignIn,
      onAccountDeletionPrepared: (_) async {},
      onAccountDeletionCancelled: (_) async {},
      onAccountDeleted: (_) async {},
    );

    await repository.signInWithGoogle();

    verify(
      () => auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: 'google-id-token',
        accessToken: 'google-access-token',
      ),
    ).called(1);
  });

  test('revoked session is cleared without exposing the JWT error', () async {
    final client = _MockSupabaseClient();
    final auth = _MockGoTrueClient();
    when(() => client.auth).thenReturn(auth);
    when(
      () => auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: 'google-id-token',
        accessToken: 'google-access-token',
      ),
    ).thenThrow(
      const AuthException(
        'Session from session_id claim in JWT does not exist',
        code: 'session_not_found',
      ),
    );
    when(
      () => auth.signOut(scope: SignOutScope.local),
    ).thenAnswer((_) async {});
    final repository = SupabaseAuthRepository(
      client,
      googleSignIn,
      onAccountDeletionPrepared: (_) async {},
      onAccountDeletionCancelled: (_) async {},
      onAccountDeleted: (_) async {},
    );

    await expectLater(
      repository.signInWithGoogle(),
      throwsA(
        isA<SupabaseFailure>()
            .having(
              (failure) => failure.kind,
              'kind',
              SupabaseFailureKind.authentication,
            )
            .having(
              (failure) => failure.message,
              'message',
              'This cloud session expired or was revoked. '
                  'Your local data is safe.',
            ),
      ),
    );

    verify(() => auth.signOut(scope: SignOutScope.local)).called(1);
    expect(googleSignIn.signOutCalls, 1);
  });

  test('native picker cancellation remains a cancelled failure', () async {
    googleSignIn.signInError = const SupabaseFailure(
      kind: SupabaseFailureKind.cancelled,
      message: 'Google sign-in was cancelled.',
    );
    final client = _MockSupabaseClient();
    final repository = SupabaseAuthRepository(
      client,
      googleSignIn,
      onAccountDeletionPrepared: (_) async {},
      onAccountDeletionCancelled: (_) async {},
      onAccountDeleted: (_) async {},
    );

    await expectLater(
      repository.signInWithGoogle(),
      throwsA(
        isA<SupabaseFailure>().having(
          (failure) => failure.kind,
          'kind',
          SupabaseFailureKind.cancelled,
        ),
      ),
    );
  });

  test(
    'account deletion reauthenticates, invokes, cleans, and signs out',
    () async {
      final client = _MockSupabaseClient();
      final auth = _MockGoTrueClient();
      final functions = _MockFunctionsClient();
      final session = _MockSession();
      final user = _MockUser();
      when(() => client.auth).thenReturn(auth);
      when(() => client.functions).thenReturn(functions);
      when(() => auth.currentSession).thenReturn(session);
      when(() => session.user).thenReturn(user);
      when(() => user.id).thenReturn('user-1');
      when(
        () => auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: 'google-id-token',
          accessToken: 'google-access-token',
        ),
      ).thenAnswer((_) async => AuthResponse(session: session));
      when(
        () => functions.invoke(
          'delete-account',
          body: const {'confirmation': 'delete-my-account'},
        ),
      ).thenAnswer(
        (_) async => FunctionResponse(data: {'deleted': true}, status: 200),
      );
      when(
        () => auth.signOut(scope: SignOutScope.local),
      ).thenAnswer((_) async {});
      String? preparedUserId;
      String? cancelledUserId;
      String? cleanedUserId;
      final repository = SupabaseAuthRepository(
        client,
        googleSignIn,
        onAccountDeletionPrepared: (userId) async => preparedUserId = userId,
        onAccountDeletionCancelled: (userId) async => cancelledUserId = userId,
        onAccountDeleted: (userId) async => cleanedUserId = userId,
      );

      await repository.deleteAccount();

      expect(googleSignIn.signInCalls, 1);
      expect(preparedUserId, 'user-1');
      expect(cancelledUserId, isNull);
      expect(cleanedUserId, 'user-1');
      verify(
        () => functions.invoke(
          'delete-account',
          body: const {'confirmation': 'delete-my-account'},
        ),
      ).called(1);
      verify(() => auth.signOut(scope: SignOutScope.local)).called(1);
      expect(googleSignIn.signOutCalls, 1);
    },
  );

  test('account deletion rejects reauthentication as another user', () async {
    final client = _MockSupabaseClient();
    final auth = _MockGoTrueClient();
    final functions = _MockFunctionsClient();
    final originalSession = _MockSession();
    final originalUser = _MockUser();
    final otherSession = _MockSession();
    final otherUser = _MockUser();
    when(() => client.auth).thenReturn(auth);
    when(() => client.functions).thenReturn(functions);
    when(() => auth.currentSession).thenReturn(originalSession);
    when(() => originalSession.user).thenReturn(originalUser);
    when(() => originalUser.id).thenReturn('user-1');
    when(() => otherSession.user).thenReturn(otherUser);
    when(() => otherUser.id).thenReturn('user-2');
    when(
      () => auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: 'google-id-token',
        accessToken: 'google-access-token',
      ),
    ).thenAnswer((_) async => AuthResponse(session: otherSession));
    when(
      () => auth.signOut(scope: SignOutScope.local),
    ).thenAnswer((_) async {});
    final repository = SupabaseAuthRepository(
      client,
      googleSignIn,
      onAccountDeletionPrepared: (_) async {},
      onAccountDeletionCancelled: (_) async {},
      onAccountDeleted: (_) async {},
    );

    await expectLater(
      repository.deleteAccount(),
      throwsA(
        isA<SupabaseFailure>().having(
          (failure) => failure.kind,
          'kind',
          SupabaseFailureKind.permissionDenied,
        ),
      ),
    );

    verifyNever(
      () => functions.invoke(
        'delete-account',
        body: const {'confirmation': 'delete-my-account'},
      ),
    );
    verify(() => auth.signOut(scope: SignOutScope.local)).called(1);
  });

  test('storage cleanup failure rolls back deletion preparation', () async {
    final client = _MockSupabaseClient();
    final auth = _MockGoTrueClient();
    final functions = _MockFunctionsClient();
    final session = _MockSession();
    final user = _MockUser();
    when(() => client.auth).thenReturn(auth);
    when(() => client.functions).thenReturn(functions);
    when(() => auth.currentSession).thenReturn(session);
    when(() => session.user).thenReturn(user);
    when(() => user.id).thenReturn('user-1');
    when(
      () => auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: 'google-id-token',
        accessToken: 'google-access-token',
      ),
    ).thenAnswer((_) async => AuthResponse(session: session));
    when(
      () => functions.invoke(
        'delete-account',
        body: const {'confirmation': 'delete-my-account'},
      ),
    ).thenThrow(
      FunctionException(
        status: 503,
        details: {'error': 'storage_cleanup_failed'},
      ),
    );
    when(
      () => auth.signOut(scope: SignOutScope.local),
    ).thenAnswer((_) async {});
    String? preparedUserId;
    String? cancelledUserId;
    String? cleanedUserId;
    final repository = SupabaseAuthRepository(
      client,
      googleSignIn,
      onAccountDeletionPrepared: (userId) async => preparedUserId = userId,
      onAccountDeletionCancelled: (userId) async => cancelledUserId = userId,
      onAccountDeleted: (userId) async => cleanedUserId = userId,
    );

    await expectLater(
      repository.deleteAccount(),
      throwsA(
        isA<SupabaseFailure>()
            .having(
              (failure) => failure.kind,
              'kind',
              SupabaseFailureKind.storage,
            )
            .having((failure) => failure.retryable, 'retryable', isTrue),
      ),
    );

    expect(preparedUserId, 'user-1');
    expect(cancelledUserId, 'user-1');
    expect(cleanedUserId, isNull);
    verifyNever(() => auth.signOut(scope: SignOutScope.local));
    expect(googleSignIn.signOutCalls, 0);
  });
}
