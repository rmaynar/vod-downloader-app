/// Storage keys and HTTP timeouts shared across the app.
///
/// The proxy-era endpoint paths and base URLs that used to live here were
/// removed along with the Node.js backend: the app now talks straight to a
/// user-configured Xtream Codes provider, so there is no fixed host to point
/// at and no app-defined URL paths to build. Provider URLs are constructed by
/// `XtreamClient` from the account's own server address.
class ApiConstants {
  ApiConstants._();

  // Shared Preferences / Local Storage Keys
  static const String keyCurrentSourceId = 'vodcatalog_current_source_id';
  static const String keySavedAccounts = 'vodcatalog_saved_accounts';
  static const String keyCredentials = 'vodcatalog_xtream_credentials';

  // Meta database keys
  static const String metaKeyCurrentSource = 'currentSourceId';
  static const String metaKeyLastSyncPrefix = 'last_sync_';

  // HTTP Timeouts
  static const Duration connectTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 60);
  static const Duration sendTimeout = Duration(seconds: 30);
}
