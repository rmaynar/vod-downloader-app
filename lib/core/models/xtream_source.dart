import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Normalizes a raw Xtream server URL for direct-to-provider requests.
///
/// - Prepends `http://` when no scheme is present.
/// - Strips trailing slashes.
///
/// Ported from the logic previously inlined in
/// `lib/features/catalog/providers/catalog_provider.dart` (loginWithXtream).
String normalizeServerUrl(String raw) {
  var cleanUrl = raw.trim();
  if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
    cleanUrl = 'http://$cleanUrl';
  }
  cleanUrl = cleanUrl.replaceAll(RegExp(r'/+$'), '');
  return cleanUrl;
}

/// Derives a stable, deterministic identity key for an Xtream source from its
/// server URL and username.
///
/// Previously `sourceId` was an integer assigned by the Node.js proxy
/// backend. Now that the app talks to providers directly, the id is derived
/// locally so the same server+username combination always resolves to the
/// same id (for SQLite cache keys, saved-account matching, etc).
///
/// Implementation: sha1('$url|$username'), first 16 hex characters. This is
/// an identity key, not a security control, so a short sha1 prefix is
/// sufficient collision resistance for the expected cardinality (a handful
/// of saved accounts per device).
String deriveSourceId(String url, String username) {
  final input = '$url|$username';
  final digest = sha1.convert(utf8.encode(input));
  return digest.toString().substring(0, 16);
}
