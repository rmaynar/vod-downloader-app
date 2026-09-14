import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show compute;

import '../constants/api_constants.dart';
import '../models/category_item.dart';
import '../models/media_item.dart';
import '../models/series_details.dart';
import '../models/xtream_source.dart';

/// Exception thrown when a direct-to-provider Xtream Codes API request fails,
/// either at the network layer or because the provider reports invalid /
/// inactive credentials.
class XtreamException implements Exception {
  final String message;
  final int? statusCode;

  XtreamException(this.message, {this.statusCode});

  @override
  String toString() => 'XtreamException($statusCode): $message';
}

/// Parsed `user_info` block returned by the Xtream `player_api.php`
/// authentication call (the no-`action` request).
class XtreamUserInfo {
  final bool auth;
  final String status;
  final DateTime? expiresAt;
  final int? maxConnections;
  final bool isTrial;

  const XtreamUserInfo({
    required this.auth,
    required this.status,
    this.expiresAt,
    this.maxConnections,
    this.isTrial = false,
  });

  factory XtreamUserInfo.fromJson(Map<String, dynamic> json) {
    final rawAuth = json['auth'];
    final auth = rawAuth == 1 || rawAuth == '1' || rawAuth == true;

    final status = json['status']?.toString() ?? 'Unknown';

    DateTime? expiresAt;
    final rawExp = json['exp_date'];
    if (rawExp != null) {
      final seconds = int.tryParse(rawExp.toString());
      if (seconds != null && seconds > 0) {
        expiresAt = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
      }
    }

    int? maxConnections;
    final rawMax = json['max_connections'];
    if (rawMax != null) {
      maxConnections = int.tryParse(rawMax.toString());
    }

    final rawTrial = json['is_trial'];
    final isTrial = rawTrial == 1 || rawTrial == '1' || rawTrial == true;

    return XtreamUserInfo(
      auth: auth,
      status: status,
      expiresAt: expiresAt,
      maxConnections: maxConnections,
      isTrial: isTrial,
    );
  }
}

/// Helper to extract a List from a raw decoded Xtream response, which in
/// practice may be a bare array, `{"data": [...]}`, `{"items": [...]}`,
/// `{"result": [...]}`, or an empty object/array when a category truly has
/// no entries. Ported from `ApiClient._normalizeList`.
///
/// Declared top-level (rather than an instance method) so it can also be
/// called from the [compute] isolate used by the bulk VOD/series parsers
/// below, which only have access to top-level and static declarations.
List<dynamic> _normalizeXtreamList(dynamic data) {
  if (data is List) return data;
  if (data is Map) {
    if (data['data'] is List) return data['data'] as List;
    if (data['items'] is List) return data['items'] as List;
    if (data['result'] is List) return data['result'] as List;
  }
  return const [];
}

/// Some providers serve JSON with a non-JSON content-type (commonly
/// `text/html`), which stops Dio's default `ResponseType.json` from
/// auto-decoding the body. Defensively decode when the response arrives as a
/// raw string.
dynamic _ensureDecoded(dynamic raw) {
  if (raw is String) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return raw;
    try {
      return jsonDecode(trimmed);
    } catch (_) {
      return raw;
    }
  }
  return raw;
}

/// Arguments passed across the isolate boundary to [_parseMediaListInIsolate].
/// Kept as a plain, closure-free class so it (and its return value) can be
/// copied safely between isolates by [compute].
class _StreamParseArgs {
  final String rawJson;
  final String sourceId;
  final bool isSeries;

  const _StreamParseArgs(this.rawJson, this.sourceId, this.isSeries);
}

/// Top-level function required by [compute]: decodes the raw bulk
/// `get_vod_streams` / `get_series` JSON payload and maps it into
/// [MediaItem]s entirely off the UI isolate.
List<MediaItem> _parseMediaListInIsolate(_StreamParseArgs args) {
  final decoded = jsonDecode(args.rawJson);
  final list = _normalizeXtreamList(decoded);
  return list
      .whereType<Map<String, dynamic>>()
      .map((item) => MediaItem.fromJson(item, args.sourceId, isSeries: args.isSeries))
      .toList();
}

/// Direct-to-provider Xtream Codes API client.
///
/// Replaces the Node.js proxy (`ApiClient`) by talking to
/// `{base}/player_api.php` directly. See the Xtream Codes contract:
/// - No `action` param authenticates and returns `user_info`/`server_info`.
/// - `get_vod_categories`, `get_vod_streams`, `get_series_categories`,
///   `get_series`, `get_series_info` mirror the proxy's endpoints.
/// - Stream URLs are built directly against `{base}/movie/...` or
///   `{base}/series/...`.
class XtreamClient {
  final Dio _dio;
  final String _baseUrl;
  final String _username;
  final String _password;

  /// Bulk catalog endpoints (`get_vod_streams`, `get_series`) can return
  /// ~40k items / ~40MB of JSON on a real catalog, so they get a much longer
  /// receive timeout than the default.
  static const Duration _bulkReceiveTimeout = Duration(seconds: 180);

  XtreamClient({
    required String baseUrl,
    required String username,
    required String password,
    Dio? dio,
  })  : _baseUrl = normalizeServerUrl(baseUrl),
        // Not using initializing formals (`this._username`) here: the
        // frozen public constructor signature requires the external
        // parameter names `username`/`password`, which can't alias a
        // private field name.
        // ignore: prefer_initializing_formals
        _username = username,
        // ignore: prefer_initializing_formals
        _password = password,
        _dio = dio ?? Dio() {
    _dio.options.baseUrl = _baseUrl;
    _dio.options.connectTimeout = ApiConstants.connectTimeout;
    _dio.options.receiveTimeout = ApiConstants.receiveTimeout;
    _dio.options.sendTimeout = ApiConstants.sendTimeout;
    _dio.options.headers = {
      'Accept': 'application/json',
      ..._dio.options.headers,
    };
  }

  /// Underlying Dio instance (exposed for tests / diagnostics).
  Dio get dio => _dio;

  /// Base URL this client talks to (normalized: scheme present, no trailing
  /// slash).
  String get baseUrl => _baseUrl;

  Map<String, dynamic> _queryParams(String? action, [Map<String, String>? extra]) {
    return <String, dynamic>{
      'username': _username,
      'password': _password,
      'action': ?action,
      ...?extra,
    };
  }

  XtreamException _handleError(dynamic error) {
    if (error is XtreamException) return error;
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
        message = 'Could not connect to Xtream server at $_baseUrl';
      }

      return XtreamException(message, statusCode: statusCode);
    }
    return XtreamException(error.toString());
  }

  /// Authenticates against the provider (the Xtream `player_api.php` request
  /// with no `action` param) and returns the parsed `user_info`.
  ///
  /// Invalid credentials return HTTP 200 with `{"user_info":{"auth":0}}` —
  /// never infer success from the status code. An account with `auth:1` but
  /// a non-"Active" status (expired, banned, disabled) fails distinctly from
  /// outright invalid credentials.
  Future<XtreamUserInfo> authenticate() async {
    try {
      final response = await _dio.get(
        '/player_api.php',
        queryParameters: _queryParams(null),
      );

      final data = _ensureDecoded(response.data);
      if (data is! Map || data['user_info'] is! Map) {
        throw XtreamException(
          'Invalid response from Xtream server',
          statusCode: response.statusCode,
        );
      }

      final userInfo = XtreamUserInfo.fromJson(
        Map<String, dynamic>.from(data['user_info'] as Map),
      );

      if (!userInfo.auth) {
        throw XtreamException('Invalid Xtream username or password');
      }
      if (userInfo.status != 'Active') {
        throw XtreamException(
          'Xtream account is not active (status: ${userInfo.status})',
        );
      }

      return userInfo;
    } on XtreamException {
      rethrow;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<List<CategoryItem>> getVodCategories(String sourceId) async {
    try {
      final response = await _dio.get(
        '/player_api.php',
        queryParameters: _queryParams('get_vod_categories'),
      );
      final list = _normalizeXtreamList(_ensureDecoded(response.data));
      return list
          .whereType<Map<String, dynamic>>()
          .map((item) => CategoryItem.fromJson(item, sourceId, 'vod'))
          .toList();
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<List<CategoryItem>> getSeriesCategories(String sourceId) async {
    try {
      final response = await _dio.get(
        '/player_api.php',
        queryParameters: _queryParams('get_series_categories'),
      );
      final list = _normalizeXtreamList(_ensureDecoded(response.data));
      return list
          .whereType<Map<String, dynamic>>()
          .map((item) => CategoryItem.fromJson(item, sourceId, 'series'))
          .toList();
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<List<MediaItem>> getVodStreams(String sourceId, {String? categoryId}) {
    return _getBulkMediaList(
      action: 'get_vod_streams',
      sourceId: sourceId,
      categoryId: categoryId,
      isSeries: false,
    );
  }

  Future<List<MediaItem>> getSeries(String sourceId, {String? categoryId}) {
    return _getBulkMediaList(
      action: 'get_series',
      sourceId: sourceId,
      categoryId: categoryId,
      isSeries: true,
    );
  }

  /// Shared implementation for the two bulk catalog endpoints. Fetches with
  /// `ResponseType.plain` (so Dio doesn't attempt to decode ~40MB of JSON on
  /// the UI isolate) and a longer receive timeout, then does `jsonDecode` +
  /// model mapping inside [compute] so the UI isolate never blocks.
  Future<List<MediaItem>> _getBulkMediaList({
    required String action,
    required String sourceId,
    String? categoryId,
    required bool isSeries,
  }) async {
    try {
      final extra = <String, String>{};
      if (categoryId != null && categoryId.isNotEmpty) {
        extra['category_id'] = categoryId;
      }

      final response = await _dio.get<String>(
        '/player_api.php',
        queryParameters: _queryParams(action, extra),
        options: Options(
          responseType: ResponseType.plain,
          receiveTimeout: _bulkReceiveTimeout,
        ),
      );

      final rawJson = response.data ?? '';
      return await compute(
        _parseMediaListInIsolate,
        _StreamParseArgs(rawJson, sourceId, isSeries),
      );
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<SeriesDetails> getSeriesInfo(String seriesId) async {
    try {
      final response = await _dio.get(
        '/player_api.php',
        queryParameters: _queryParams('get_series_info', {'series_id': seriesId}),
      );

      final data = _ensureDecoded(response.data);
      if (data is Map<String, dynamic>) {
        return SeriesDetails.fromJson(data);
      } else if (data is Map) {
        return SeriesDetails.fromJson(Map<String, dynamic>.from(data));
      }
      throw XtreamException(
        'Invalid series info response format',
        statusCode: response.statusCode,
      );
    } on XtreamException {
      rethrow;
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Builds a direct playback/download URL:
  /// `{base}/movie/{u}/{p}/{id}.{container}` or
  /// `{base}/series/{u}/{p}/{id}.{container}`.
  ///
  /// Username and password path segments are URL-encoded. A leading `.` on
  /// [container] is stripped so the extension is never doubled.
  String buildStreamUrl({
    required String type,
    required String id,
    required String container,
  }) {
    final cleanContainer = container.startsWith('.') ? container.substring(1) : container;
    final encodedUser = Uri.encodeComponent(_username);
    final encodedPass = Uri.encodeComponent(_password);
    return '$_baseUrl/$type/$encodedUser/$encodedPass/$id.$cleanContainer';
  }
}
