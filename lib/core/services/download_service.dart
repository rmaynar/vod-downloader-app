import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/media_item.dart';
import '../models/series_details.dart';
import '../network/xtream_client.dart';

/// Thrown by [DownloadService] when a download cannot be started or
/// completed (no active account, malformed input, or a network/IO failure).
///
/// The message — and therefore [toString] — is guaranteed to never contain
/// raw Xtream credentials; see [DownloadService.redactCredentials].
class DownloadServiceException implements Exception {
  final String message;
  const DownloadServiceException(this.message);

  @override
  String toString() => message;
}

/// Service responsible for constructing direct-to-provider download URLs and
/// downloading media files to local storage.
///
/// Post-proxy-removal, this service has no notion of a "host" or multiple
/// sources — it downloads from exactly one active Xtream account, whose
/// credentials are carried by the injected [XtreamClient].
class DownloadService extends ChangeNotifier {
  final XtreamClient? _client;
  final Dio _dio;

  DownloadService({
    XtreamClient? client,
    Dio? dio,
  })  : _client = client,
        // Reuse the injected client's Dio (and therefore its connection
        // pool) when the caller doesn't supply one explicitly.
        _dio = dio ?? client?.dio ?? Dio();

  /// Returns the injected [XtreamClient], or throws a clear
  /// [DownloadServiceException] if none is active. Centralizes the "no
  /// account configured" failure so every URL-building path fails the same
  /// way instead of null-dereferencing or building a malformed URL.
  XtreamClient _requireClient() {
    final client = _client;
    if (client == null) {
      throw const DownloadServiceException(
        'No active Xtream account is configured — cannot start a download. '
        'Sign in to an account first.',
      );
    }
    return client;
  }

  /// Redacts Xtream credentials embedded in [url] so it is safe to place in
  /// a log line, thrown exception message, or `toString()`.
  ///
  /// Download URLs built by this service carry the account username and
  /// password as raw path segments
  /// (`{base}/movie|series/{username}/{password}/{id}.{container}`), so any
  /// URL that could reach a log or error message MUST be passed through
  /// this first — otherwise the user's provider password leaks into crash
  /// reports, console output, or UI error text.
  String redactCredentials(String url) {
    var result = url;

    // Xtream path-style credentials:
    // /movie/{username}/{password}/... or /series/{username}/{password}/...
    result = result.replaceAllMapped(
      RegExp(r'/(movie|series)/([^/?#]+)/([^/?#]+)(?=[/.])'),
      (m) => '/${m[1]}/***/***',
    );

    // Defensive: query-string style credentials, in case a URL from another
    // code path (e.g. a raw player_api.php request surfaced in an error)
    // ever reaches this helper.
    result = result.replaceAllMapped(
      RegExp(
        r'([?&](?:username|password|user|pass)=)[^&#]*',
        caseSensitive: false,
      ),
      (m) => '${m[1]}***',
    );

    return result;
  }

  /// Constructs the direct provider stream URL for [type]/[itemId], e.g.
  /// `{base}/movie/{username}/{password}/{id}.{container}` or the `series`
  /// equivalent.
  ///
  /// Delegates entirely to [XtreamClient.buildStreamUrl] for base-URL
  /// normalisation, credential URL-encoding, and leading-dot stripping on
  /// the container extension; this method only owns picking a sensible
  /// default container (`mp4`) when [containerExtension] is missing/blank.
  ///
  /// Throws [DownloadServiceException] if no [XtreamClient] was injected
  /// (i.e. there is no active account) rather than building a malformed
  /// URL.
  String buildDownloadUrl({
    required String type, // 'movie' or 'series'
    required String itemId,
    String? containerExtension,
  }) {
    final client = _requireClient();
    final cleanContainer =
        (containerExtension ?? '').replaceAll(RegExp(r'^\.'), '').trim();
    final safeContainer = cleanContainer.isNotEmpty ? cleanContainer : 'mp4';

    return client.buildStreamUrl(
      type: type,
      id: itemId,
      container: safeContainer,
    );
  }

  /// Constructs a download URL for a movie or series [MediaItem].
  /// Returns `null` for an item with no usable stream id.
  String? getDownloadUrlForMedia({required MediaItem item}) {
    if (item.streamId.isEmpty) return null;

    final type = item.isSeries ? 'series' : 'movie';
    return buildDownloadUrl(
      type: type,
      itemId: item.streamId,
      containerExtension: item.containerExtension,
    );
  }

  /// Constructs a download URL for a specific TV series episode.
  /// Returns `null` for an episode with no usable id.
  String? getDownloadUrlForEpisode({required EpisodeItem episode}) {
    if (episode.id.isEmpty) return null;

    return buildDownloadUrl(
      type: 'series',
      itemId: episode.id,
      containerExtension: episode.containerExtension,
    );
  }

  /// Formats the on-disk display name for a series episode:
  /// `"{seriesName} S{season}E{episode} - {title}"`, zero-padded to two
  /// digits (e.g. `"Game of Thrones S08E03 - The Great War"`).
  ///
  /// This is the single source of truth for episode naming. It used to be
  /// embedded in the (proxy-era) download URL's `name=` query parameter;
  /// now that download URLs point straight at the provider, it feeds only
  /// [sanitizeFileName] for the local destination filename (see
  /// [downloadEpisode]).
  String formatEpisodeTitle({
    required String seriesName,
    required EpisodeItem episode,
    String? seasonNum,
  }) {
    final season = seasonNum ?? episode.seasonNum ?? '1';
    return '$seriesName S${season.padLeft(2, '0')}E${episode.episodeNum.padLeft(2, '0')} - ${episode.title}';
  }

  /// Retrieves the preferred download directory on the device.
  /// Prefers external downloads directory where accessible, falling back to application documents.
  Future<Directory> getDownloadDirectory() async {
    Directory? dir;
    try {
      if (Platform.isAndroid) {
        dir = await getExternalStorageDirectory();
      } else {
        dir = await getDownloadsDirectory();
      }
    } catch (_) {
      // Fallback if platform directory lookup fails
    }

    dir ??= await getApplicationDocumentsDirectory();
    final downloadDir = Directory(p.join(dir.path, 'downloads'));
    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }
    return downloadDir;
  }

  /// Sanitizes a file name by removing characters forbidden by file systems.
  String sanitizeFileName(String name) {
    return name
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Downloads a file from the given [downloadUrl] and saves it to [destinationPath].
  /// Returns the absolute path of the downloaded file.
  ///
  /// Sends a browser-like `User-Agent`, since Xtream providers commonly
  /// reject clients that don't send one, and follows the 302 redirect to
  /// the CDN that providers commonly issue for stream requests.
  Future<String> downloadFile({
    required String downloadUrl,
    required String destinationPath,
    ProgressCallback? onReceiveProgress,
    CancelToken? cancelToken,
  }) async {
    final file = File(destinationPath);
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }

    try {
      await _dio.download(
        downloadUrl,
        destinationPath,
        onReceiveProgress: onReceiveProgress,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: true,
          headers: const {'User-Agent': 'Mozilla/5.0'},
        ),
      );
      notifyListeners();
      return destinationPath;
    } catch (e) {
      // Clean up incomplete file if download was canceled or failed
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
      // The url (and quite possibly e's own message/toString, e.g. a
      // DioException echoing the request) can carry the account's
      // username/password — redact both before they reach a rethrow that
      // might land in a log or on screen.
      throw DownloadServiceException(
        'Failed to download "${redactCredentials(downloadUrl)}": '
        '${redactCredentials(e.toString())}',
      );
    }
  }

  /// High-level trigger method matching UI call conventions.
  ///
  /// [sourceId] is accepted (not removed) purely for source-compatibility
  /// with existing UI call sites (`media_card.dart`,
  /// `media_details_modal.dart`) that predate the proxy removal — it is now
  /// unused. Credentials and base URL come solely from the [XtreamClient]
  /// injected at construction, since the app now talks to exactly one
  /// active account rather than a multi-source proxy.
  Future<String?> triggerDownload({
    required dynamic sourceId,
    required dynamic type,
    required dynamic itemId,
    String container = 'mp4',
    required String title,
    ProgressCallback? onReceiveProgress,
  }) async {
    final resolvedType = type is MediaType
        ? (type == MediaType.series ? 'series' : 'movie')
        : type.toString().toLowerCase().contains('series')
            ? 'series'
            : 'movie';

    final downloadUrl = buildDownloadUrl(
      type: resolvedType,
      itemId: itemId.toString(),
      containerExtension: container,
    );

    final dir = await getDownloadDirectory();
    final cleanContainer = container.replaceAll(RegExp(r'^\.'), '');
    final cleanName = sanitizeFileName(title);
    final fileName = '$cleanName.$cleanContainer';
    final targetPath = p.join(dir.path, fileName);

    return await downloadFile(
      downloadUrl: downloadUrl,
      destinationPath: targetPath,
      onReceiveProgress: onReceiveProgress,
    );
  }

  /// High-level method to download a movie MediaItem.
  ///
  /// [sourceId] is accepted for source-compatibility but unused — see
  /// [triggerDownload]'s doc comment for why.
  Future<String> downloadMediaItem({
    required String sourceId,
    required MediaItem item,
    ProgressCallback? onReceiveProgress,
    CancelToken? cancelToken,
    String? customFileName,
  }) async {
    final downloadUrl = getDownloadUrlForMedia(item: item);
    if (downloadUrl == null) {
      throw ArgumentError('Could not construct download URL for item: ${item.name}');
    }

    final dir = await getDownloadDirectory();
    final container = (item.containerExtension ?? 'mp4').replaceAll(RegExp(r'^\.'), '');
    final baseName = customFileName ?? item.name;
    final cleanName = sanitizeFileName(baseName);
    final fileName = '$cleanName.$container';
    final targetPath = p.join(dir.path, fileName);

    return await downloadFile(
      downloadUrl: downloadUrl,
      destinationPath: targetPath,
      onReceiveProgress: onReceiveProgress,
      cancelToken: cancelToken,
    );
  }

  /// High-level method to download a TV series episode.
  ///
  /// [sourceId] is accepted for source-compatibility but unused — see
  /// [triggerDownload]'s doc comment for why.
  Future<String> downloadEpisode({
    required String sourceId,
    required EpisodeItem episode,
    required String seriesName,
    String? seasonNum,
    ProgressCallback? onReceiveProgress,
    CancelToken? cancelToken,
  }) async {
    final downloadUrl = getDownloadUrlForEpisode(episode: episode);
    if (downloadUrl == null) {
      throw ArgumentError('Could not construct download URL for episode: ${episode.title}');
    }

    final dir = await getDownloadDirectory();
    final container = (episode.containerExtension ?? 'mp4').replaceAll(RegExp(r'^\.'), '');
    final epTitle = formatEpisodeTitle(
      seriesName: seriesName,
      episode: episode,
      seasonNum: seasonNum,
    );
    final cleanName = sanitizeFileName(epTitle);
    final fileName = '$cleanName.$container';
    final targetPath = p.join(dir.path, fileName);

    return await downloadFile(
      downloadUrl: downloadUrl,
      destinationPath: targetPath,
      onReceiveProgress: onReceiveProgress,
      cancelToken: cancelToken,
    );
  }
}
