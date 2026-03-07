class AppConfig {
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue:
        'https://3u10v51mvk.execute-api.us-east-1.amazonaws.com/api/v1/',
  );
}
