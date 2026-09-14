class ApiConstants {
  ApiConstants._();

  /// Default API base URL pointing to the local Node.js proxy server.
  /// 10.0.2.2 is the loopback alias for the host machine in the standard Android emulator.
  static const String defaultBaseUrl = 'http://10.0.2.2:3000';

  /// Fallback host URL for localhost / desktop / web / iOS simulator
  static const String localhostBaseUrl = 'http://localhost:3000';

  // Shared Preferences / Local Storage Keys
  static const String keyBaseUrl = 'vodcatalog_base_url';
  static const String keyCurrentSourceId = 'vodcatalog_current_source_id';
  static const String keySavedAccounts = 'vodcatalog_saved_accounts';
  static const String keyCredentials = 'vodcatalog_xtream_credentials';

  // Meta database keys
  static const String metaKeyCurrentSource = 'currentSourceId';
  static const String metaKeyLastSyncPrefix = 'last_sync_';

  // API Endpoints
  static const String endpointSources = '/api/sources';
  static const String endpointDownload = '/api/download';
  static const String endpointXtreamProxy = '/api/proxy/xtream';

  // HTTP Timeouts
  static const Duration connectTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 60);
  static const Duration sendTimeout = Duration(seconds: 30);
}
