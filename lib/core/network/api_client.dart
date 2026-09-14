import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/api_constants.dart';
import '../models/category_item.dart';
import '../models/media_item.dart';
import '../models/series_details.dart';
import '../models/source_account.dart';

/// Exception thrown when an API request fails.
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic responseData;

  ApiException(this.message, {this.statusCode, this.responseData});

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// HTTP API Client for nodecast proxy backend using Dio.
class ApiClient {
  late final Dio _dio;
  String _baseUrl;

  ApiClient({
    String? baseUrl,
    Dio? customDio,
    Dio? dio,
  }) : _baseUrl = baseUrl ?? ApiConstants.defaultBaseUrl {
    _dio = customDio ??
        dio ??
        Dio(
          BaseOptions(
            baseUrl: _baseUrl,
            connectTimeout: ApiConstants.connectTimeout,
            receiveTimeout: ApiConstants.receiveTimeout,
            sendTimeout: ApiConstants.sendTimeout,
            headers: {
              'Accept': 'application/json',
            },
          ),
        );
  }

  /// Current base URL of the client.
  String get baseUrl => _baseUrl;

  /// Underlying Dio instance.
  Dio get dio => _dio;

  /// Initializes the client by reading any configured baseUrl from SharedPreferences.
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUrl = prefs.getString(ApiConstants.keyBaseUrl);
      if (savedUrl != null && savedUrl.trim().isNotEmpty) {
        updateBaseUrl(savedUrl.trim());
      }
    } catch (_) {
      // SharedPreferences might fail in pure unit tests; keep default
    }
  }

  /// Updates the base URL in memory and optionally persists to SharedPreferences.
  Future<void> updateBaseUrl(String newUrl, {bool persist = true}) async {
    final cleanUrl = newUrl.trim().replaceAll(RegExp(r'/+$'), '');
    _baseUrl = cleanUrl;
    _dio.options.baseUrl = cleanUrl;

    if (persist) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(ApiConstants.keyBaseUrl, cleanUrl);
      } catch (_) {
        // Ignore persistence errors
      }
    }
  }

  /// Helper to extract List from either direct list or {data: [...]} response format.
  List<dynamic> _normalizeList(dynamic data) {
    if (data is List) return data;
    if (data is Map) {
      if (data['data'] is List) return data['data'] as List;
      if (data['items'] is List) return data['items'] as List;
      if (data['result'] is List) return data['result'] as List;
    }
    return const [];
  }

  /// Handles Dio errors and converts them to descriptive ApiException.
  ApiException _handleError(dynamic error) {
    if (error is DioException) {
      final statusCode = error.response?.statusCode;
      final responseData = error.response?.data;
      String message = error.message ?? 'Unknown network error';

      if (responseData is Map && responseData['error'] != null) {
        message = responseData['error'].toString();
      } else if (responseData is Map && responseData['message'] != null) {
        message = responseData['message'].toString();
      } else if (error.type == DioExceptionType.connectionTimeout) {
        message = 'Connection timed out';
      } else if (error.type == DioExceptionType.receiveTimeout) {
        message = 'Server response timed out';
      } else if (error.type == DioExceptionType.connectionError) {
        message = 'Could not connect to proxy server at $_baseUrl';
      }

      return ApiException(message, statusCode: statusCode, responseData: responseData);
    }
    return ApiException(error.toString());
  }

  /// GET /api/sources
  /// Fetches the list of all configured IPTV / Xtream sources.
  Future<List<SourceAccount>> getSources({CancelToken? cancelToken}) async {
    try {
      final response = await _dio.get(
        ApiConstants.endpointSources,
        cancelToken: cancelToken,
      );
      final list = _normalizeList(response.data);
      return list
          .whereType<Map<String, dynamic>>()
          .map((item) => SourceAccount.fromJson(item))
          .toList();
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// GET /api/proxy/xtream/:sourceId/vod_categories
  /// Fetches VOD categories for a source.
  Future<List<CategoryItem>> getVodCategories(
    String sourceId, {
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _dio.get(
        '${ApiConstants.endpointXtreamProxy}/$sourceId/vod_categories',
        cancelToken: cancelToken,
      );
      final list = _normalizeList(response.data);
      return list
          .whereType<Map<String, dynamic>>()
          .map((item) => CategoryItem.fromJson(item, sourceId, 'vod'))
          .toList();
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// GET /api/proxy/xtream/:sourceId/vod_streams
  /// Fetches VOD stream entries (movies) for a source, optionally filtered by category.
  Future<List<MediaItem>> getVodStreams(
    String sourceId, {
    String? categoryId,
    CancelToken? cancelToken,
  }) async {
    try {
      final queryParams = <String, dynamic>{};
      if (categoryId != null && categoryId.isNotEmpty) {
        queryParams['category_id'] = categoryId;
      }

      final response = await _dio.get(
        '${ApiConstants.endpointXtreamProxy}/$sourceId/vod_streams',
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
        cancelToken: cancelToken,
      );
      final list = _normalizeList(response.data);
      return list
          .whereType<Map<String, dynamic>>()
          .map((item) => MediaItem.fromJson(item, sourceId, isSeries: false))
          .toList();
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// GET /api/proxy/xtream/:sourceId/series_categories
  /// Fetches TV series categories for a source.
  Future<List<CategoryItem>> getSeriesCategories(
    String sourceId, {
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _dio.get(
        '${ApiConstants.endpointXtreamProxy}/$sourceId/series_categories',
        cancelToken: cancelToken,
      );
      final list = _normalizeList(response.data);
      return list
          .whereType<Map<String, dynamic>>()
          .map((item) => CategoryItem.fromJson(item, sourceId, 'series'))
          .toList();
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// GET /api/proxy/xtream/:sourceId/series
  /// Fetches TV series entries for a source, optionally filtered by category.
  Future<List<MediaItem>> getSeries(
    String sourceId, {
    String? categoryId,
    CancelToken? cancelToken,
  }) async {
    try {
      final queryParams = <String, dynamic>{};
      if (categoryId != null && categoryId.isNotEmpty) {
        queryParams['category_id'] = categoryId;
      }

      final response = await _dio.get(
        '${ApiConstants.endpointXtreamProxy}/$sourceId/series',
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
        cancelToken: cancelToken,
      );
      final list = _normalizeList(response.data);
      return list
          .whereType<Map<String, dynamic>>()
          .map((item) => MediaItem.fromJson(item, sourceId, isSeries: true))
          .toList();
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// GET /api/proxy/xtream/:sourceId/series_info?series_id=:seriesId
  /// Fetches TV series metadata, seasons, and episodes.
  Future<SeriesDetails> getSeriesInfo(
    String sourceId,
    String seriesId, {
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _dio.get(
        '${ApiConstants.endpointXtreamProxy}/$sourceId/series_info',
        queryParameters: {'series_id': seriesId},
        cancelToken: cancelToken,
      );

      if (response.data is Map<String, dynamic>) {
        return SeriesDetails.fromJson(response.data as Map<String, dynamic>);
      } else {
        throw ApiException('Invalid series info response format', statusCode: response.statusCode);
      }
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// POST /api/sources/:sourceId/sync
  /// Triggers a backend synchronization for a source.
  Future<void> syncSource(String sourceId, {CancelToken? cancelToken}) async {
    try {
      await _dio.post(
        '${ApiConstants.endpointSources}/$sourceId/sync',
        cancelToken: cancelToken,
      );
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// POST /api/sources
  /// Creates a new source with credentials on the proxy server.
  Future<SourceAccount> createSource({
    required String name,
    required String url,
    required String username,
    required String password,
    String type = 'xtream',
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _dio.post(
        ApiConstants.endpointSources,
        data: {
          'type': type,
          'name': name.trim(),
          'url': url.trim(),
          'username': username.trim(),
          'password': password.trim(),
        },
        cancelToken: cancelToken,
      );

      if (response.data is Map<String, dynamic>) {
        return SourceAccount.fromJson(response.data as Map<String, dynamic>);
      } else {
        throw ApiException('Invalid create source response format', statusCode: response.statusCode);
      }
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Tests connection to the proxy server or custom url.
  Future<bool> testConnection({String? customUrl, String? testUrl}) async {
    try {
      final url = customUrl ?? testUrl;
      if (url != null && url.isNotEmpty) {
        final clean = url.trim().replaceAll(RegExp(r'/+$'), '');
        final dio = Dio(BaseOptions(
          baseUrl: clean,
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ));
        final response = await dio.get(ApiConstants.endpointSources);
        return response.statusCode == 200;
      }
      final response = await _dio.get(
        ApiConstants.endpointSources,
        options: Options(sendTimeout: const Duration(seconds: 5), receiveTimeout: const Duration(seconds: 5)),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// POST /api/sources/:sourceId/test
  /// Tests source connection and validity.
  Future<bool> testSource(String sourceId, {CancelToken? cancelToken}) async {
    try {
      final response = await _dio.post(
        '${ApiConstants.endpointSources}/$sourceId/test',
        cancelToken: cancelToken,
      );
      return response.statusCode == 200;
    } catch (e) {
      throw _handleError(e);
    }
  }
}
