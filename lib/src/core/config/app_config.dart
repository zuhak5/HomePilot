import 'dart:convert';

enum AppEnvironment {
  dev,
  staging,
  prod;

  static AppEnvironment parse(String value) {
    return switch (value.trim().toLowerCase()) {
      'dev' => AppEnvironment.dev,
      'staging' => AppEnvironment.staging,
      'prod' => AppEnvironment.prod,
      _ => throw const AppConfigException(
        'APP_ENV must be dev, staging, or prod.',
      ),
    };
  }
}

class AppConfigException implements Exception {
  const AppConfigException(this.message);

  final String message;

  @override
  String toString() => 'App configuration is invalid: $message';
}

class AppConfig {
  const AppConfig._({
    required this.environment,
    required this.supabaseUrl,
    required this.supabasePublishableKey,
    required this.googleWebClientId,
  });

  factory AppConfig.fromEnvironment() {
    const environmentValue = String.fromEnvironment(
      'APP_ENV',
      defaultValue: 'dev',
    );
    const urlValue = String.fromEnvironment('SUPABASE_URL');
    const keyValue = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
    const googleWebClientIdValue = String.fromEnvironment(
      'GOOGLE_WEB_CLIENT_ID',
    );
    final environment = AppEnvironment.parse(environmentValue);
    return AppConfig.configured(
      environment: environment,
      supabaseUrl: urlValue,
      supabasePublishableKey: keyValue,
      googleWebClientId: googleWebClientIdValue,
    );
  }

  factory AppConfig.test({AppEnvironment environment = AppEnvironment.dev}) {
    return AppConfig._(
      environment: environment,
      supabaseUrl: Uri.parse('http://127.0.0.1:54321'),
      supabasePublishableKey: 'sb_publishable_test',
      googleWebClientId: '123-example.apps.googleusercontent.com',
    );
  }

  factory AppConfig.configured({
    required AppEnvironment environment,
    required String supabaseUrl,
    required String supabasePublishableKey,
    required String googleWebClientId,
  }) {
    final url = Uri.tryParse(supabaseUrl.trim());
    if (url == null || !url.hasScheme || url.host.isEmpty) {
      throw const AppConfigException('SUPABASE_URL must be an absolute URL.');
    }
    final isLocalDev =
        environment == AppEnvironment.dev &&
        (url.host == '127.0.0.1' || url.host == 'localhost');
    if (url.scheme != 'https' && !(isLocalDev && url.scheme == 'http')) {
      throw const AppConfigException(
        'SUPABASE_URL must use HTTPS outside local development.',
      );
    }

    final key = supabasePublishableKey.trim();
    if (key.isEmpty) {
      throw const AppConfigException(
        'SUPABASE_PUBLISHABLE_KEY must not be empty.',
      );
    }
    if (key.startsWith('sb_secret_') || _jwtRole(key) == 'service_role') {
      throw const AppConfigException(
        'A privileged Supabase key cannot be used by the app.',
      );
    }

    final webClientId = googleWebClientId.trim();
    if (!RegExp(
      r'^[A-Za-z0-9_-]+\.apps\.googleusercontent\.com$',
    ).hasMatch(webClientId)) {
      throw const AppConfigException(
        'GOOGLE_WEB_CLIENT_ID must be a Google Web OAuth client ID.',
      );
    }
    return AppConfig._(
      environment: environment,
      supabaseUrl: url,
      supabasePublishableKey: key,
      googleWebClientId: webClientId,
    );
  }

  final AppEnvironment environment;
  final Uri supabaseUrl;
  final String supabasePublishableKey;
  final String googleWebClientId;

  String get storageNamespace {
    final projectHost = supabaseUrl.host;
    return 'homepilot.supabase.${environment.name}.$projectHost';
  }

  String get redactedDescription =>
      'environment=${environment.name}, '
      'host=${supabaseUrl.host}';
}

String? _jwtRole(String token) {
  final parts = token.split('.');
  if (parts.length != 3) {
    return null;
  }
  try {
    final normalized = base64Url.normalize(parts[1]);
    final payload =
        jsonDecode(utf8.decode(base64Url.decode(normalized)))
            as Map<String, dynamic>;
    return payload['role'] as String?;
  } on Object {
    return null;
  }
}
