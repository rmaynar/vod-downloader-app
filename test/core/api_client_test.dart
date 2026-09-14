import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodecast_catalog_flutter/core/constants/api_constants.dart';
import 'package:nodecast_catalog_flutter/core/network/api_client.dart';

class MockAdapter implements HttpClientAdapter {
  late ResponseBody Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('ApiConstants', () {
    test('constants have expected values', () {
      expect(ApiConstants.defaultBaseUrl, 'http://10.0.2.2:3000');
      expect(ApiConstants.keyBaseUrl, 'vodcatalog_base_url');
      expect(ApiConstants.keyCurrentSourceId, 'vodcatalog_current_source_id');
      expect(ApiConstants.keySavedAccounts, 'vodcatalog_saved_accounts');
      expect(ApiConstants.endpointSources, '/api/sources');
      expect(ApiConstants.endpointDownload, '/api/download');
      expect(ApiConstants.endpointXtreamProxy, '/api/proxy/xtream');
    });
  });

  group('ApiClient', () {
    late ApiClient apiClient;
    late MockAdapter mockAdapter;

    setUp(() {
      mockAdapter = MockAdapter();
      final dio = Dio(BaseOptions(baseUrl: ApiConstants.defaultBaseUrl));
      dio.httpClientAdapter = mockAdapter;
      apiClient = ApiClient(customDio: dio);
    });

    test('getSources returns list of sources', () async {
      mockAdapter.handler = (options) {
        expect(options.path, '/api/sources');
        expect(options.method, 'GET');
        return ResponseBody.fromString(
          '''[
            {"id": "s1", "name": "Source 1", "url": "http://s1.com", "username": "u1", "lastUsedAt": 1000},
            {"id": "s2", "name": "Source 2", "url": "http://s2.com", "username": "u2", "lastUsedAt": 2000}
          ]''',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      };

      final sources = await apiClient.getSources();
      expect(sources.length, 2);
      expect(sources[0].id, 's1');
      expect(sources[0].name, 'Source 1');
      expect(sources[1].id, 's2');
    });

    test('getVodStreams with category_id sends query param', () async {
      mockAdapter.handler = (options) {
        expect(options.path, '/api/proxy/xtream/src1/vod_streams');
        expect(options.queryParameters['category_id'], 'cat99');
        return ResponseBody.fromString(
          '''[
            {"stream_id": 10, "name": "Matrix", "category_id": "cat99"}
          ]''',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      };

      final streams = await apiClient.getVodStreams('src1', categoryId: 'cat99');
      expect(streams.length, 1);
      expect(streams[0].streamId, '10');
      expect(streams[0].name, 'Matrix');
    });

    test('getSeriesInfo parses series and episodes correctly', () async {
      mockAdapter.handler = (options) {
        expect(options.path, '/api/proxy/xtream/src1/series_info');
        expect(options.queryParameters['series_id'], 'ser55');
        return ResponseBody.fromString(
          '''{
            "info": {"name": "Test Show", "plot": "Show plot"},
            "episodes": {
              "1": [
                {"id": "ep1", "episode_num": 1, "title": "Pilot"}
              ]
            }
          }''',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      };

      final info = await apiClient.getSeriesInfo('src1', 'ser55');
      expect(info.name, 'Test Show');
      expect(info.totalEpisodes, 1);
      expect(info.getEpisodes('1').first.title, 'Pilot');
    });

    test('createSource sends post payload and returns source', () async {
      mockAdapter.handler = (options) {
        expect(options.path, '/api/sources');
        expect(options.method, 'POST');
        expect(options.data['name'], 'New IPTV');
        return ResponseBody.fromString(
          '''{
            "id": "new_1",
            "name": "New IPTV",
            "url": "http://iptv.test",
            "username": "user",
            "lastUsedAt": 3000
          }''',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      };

      final created = await apiClient.createSource(
        name: 'New IPTV',
        url: 'http://iptv.test',
        username: 'user',
        password: 'pass',
      );

      expect(created.id, 'new_1');
      expect(created.name, 'New IPTV');
    });
  });
}
