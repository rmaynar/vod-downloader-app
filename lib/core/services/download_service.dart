import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../constants/api_constants.dart';
import '../models/media_item.dart';
import '../models/series_details.dart';

/// Service responsible for constructing download URLs and downloading media files to local storage.
class DownloadService extends ChangeNotifier {
  final dynamic _apiClient;
  final Dio _dio;

  DownloadService({
    dynamic apiClient,
    Dio? dio,
  })  : _apiClient = apiClient,
        _dio = dio ??
            (apiClient != null && apiClient.dio is Dio
                ? (apiClient.dio as Dio)
                : Dio());

  /// Gets the active base URL from the configured apiClient or default.
  String get _baseUrl {
    if (_apiClient != null) {
      try {
        final url = _apiClient.baseUrl;
        if (url is String && url.isNotEmpty) {
          return url;
        }
      } catch (_) {}
    }
    return ApiConstants.defaultBaseUrl;
  }

  /// Constructs the absolute download URL matching the proxy endpoint:
  /// `/api/download/:sourceId/:type/:itemId?container=:container&name=:name`
  String buildDownloadUrl({
    required String sourceId,
    required String type, // 'movie' or 'series'
    required String itemId,
    required String name,
    String? containerExtension,
    String? baseUrl,
  }) {
    final host = (baseUrl ?? _baseUrl).replaceAll(RegExp(r'/+$'), '');
    final cleanContainer =
        (containerExtension ?? 'mp4').replaceAll(RegExp(r'^\.'), '').trim();
    final safeContainer =
        cleanContainer.isNotEmpty ? cleanContainer : 'mp4';
    final safeName = Uri.encodeComponent(name.trim());

    return '$host${ApiConstants.endpointDownload}/$sourceId/$type/$itemId?container=$safeContainer&name=$safeName';
  }

  /// Constructs a download URL for a movie or series MediaItem.
  String? getDownloadUrlForMedia({
    required String sourceId,
    required MediaItem item,
    String? baseUrl,
  }) {
    if (sourceId.isEmpty || item.streamId.isEmpty) return null;

    final type = item.isSeries ? 'series' : 'movie';
    final title = item.name.isNotEmpty ? item.name : '$type-${item.streamId}';

    return buildDownloadUrl(
      sourceId: sourceId,
      type: type,
      itemId: item.streamId,
      name: title,
      containerExtension: item.containerExtension,
      baseUrl: baseUrl,
    );
  }

  /// Constructs a download URL for a specific TV series episode.
  String? getDownloadUrlForEpisode({
    required String sourceId,
    required EpisodeItem episode,
    required String seriesName,
    String? seasonNum,
    String? baseUrl,
  }) {
    if (sourceId.isEmpty || episode.id.isEmpty) return null;

    final season = seasonNum ?? episode.seasonNum ?? '1';
    final formattedTitle =
        '$seriesName S${season.padLeft(2, '0')}E${episode.episodeNum.padLeft(2, '0')} - ${episode.title}';

    return buildDownloadUrl(
      sourceId: sourceId,
      type: 'series',
      itemId: episode.id,
      name: formattedTitle,
      containerExtension: episode.containerExtension,
      baseUrl: baseUrl,
    );
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
      rethrow;
    }
  }

  /// High-level trigger method matching UI call conventions.
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
      sourceId: sourceId.toString(),
      type: resolvedType,
      itemId: itemId.toString(),
      name: title,
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
  Future<String> downloadMediaItem({
    required String sourceId,
    required MediaItem item,
    ProgressCallback? onReceiveProgress,
    CancelToken? cancelToken,
    String? customFileName,
  }) async {
    final downloadUrl = getDownloadUrlForMedia(
      sourceId: sourceId,
      item: item,
    );
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
  Future<String> downloadEpisode({
    required String sourceId,
    required EpisodeItem episode,
    required String seriesName,
    String? seasonNum,
    ProgressCallback? onReceiveProgress,
    CancelToken? cancelToken,
  }) async {
    final season = seasonNum ?? episode.seasonNum ?? '1';
    final downloadUrl = getDownloadUrlForEpisode(
      sourceId: sourceId,
      episode: episode,
      seriesName: seriesName,
      seasonNum: season,
    );
    if (downloadUrl == null) {
      throw ArgumentError('Could not construct download URL for episode: ${episode.title}');
    }

    final dir = await getDownloadDirectory();
    final container = (episode.containerExtension ?? 'mp4').replaceAll(RegExp(r'^\.'), '');
    final epTitle =
        '$seriesName S${season.padLeft(2, '0')}E${episode.episodeNum.padLeft(2, '0')} - ${episode.title}';
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
