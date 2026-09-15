import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vod_downloader/core/models/xtream_source.dart';
import 'package:vod_downloader/core/network/xtream_client.dart';

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

ResponseBody _jsonBody(String body, [int statusCode = 200]) {
  return ResponseBody.fromString(
    body,
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

void main() {
  group('normalizeServerUrl', () {
    test('prepends http:// when no scheme is present', () {
      expect(normalizeServerUrl('example.com:8080'), 'http://example.com:8080');
    });

    test('strips trailing slashes', () {
      expect(normalizeServerUrl('http://example.com/'), 'http://example.com');
      expect(normalizeServerUrl('http://example.com///'), 'http://example.com');
    });

    test('preserves https scheme', () {
      expect(normalizeServerUrl('https://example.com'), 'https://example.com');
    });

    test('trims whitespace', () {
      expect(normalizeServerUrl('  example.com  '), 'http://example.com');
    });
  });

  group('deriveSourceId', () {
    test('is stable across calls', () {
      final a = deriveSourceId('http://example.com', 'user1');
      final b = deriveSourceId('http://example.com', 'user1');
      expect(a, b);
    });

    test('differs for different usernames', () {
      final a = deriveSourceId('http://example.com', 'user1');
      final b = deriveSourceId('http://example.com', 'user2');
      expect(a, isNot(b));
    });

    test('differs for different urls', () {
      final a = deriveSourceId('http://example.com', 'user1');
      final b = deriveSourceId('http://other.com', 'user1');
      expect(a, isNot(b));
    });

    test('produces a 16 char hex string', () {
      final id = deriveSourceId('http://example.com', 'user1');
      expect(id.length, 16);
      expect(RegExp(r'^[0-9a-f]{16}$').hasMatch(id), isTrue);
    });
  });

  group('XtreamClient', () {
    late MockAdapter mockAdapter;
    late Dio dio;
    late XtreamClient client;

    setUp(() {
      mockAdapter = MockAdapter();
      dio = Dio();
      dio.httpClientAdapter = mockAdapter;
      client = XtreamClient(
        baseUrl: 'http://provider.test:8080',
        username: 'myuser',
        password: 'myp@ss',
        dio: dio,
      );
    });

    test('authenticate builds correct url and query params (no action)', () async {
      mockAdapter.handler = (options) {
        expect(options.path, '/player_api.php');
        expect(options.baseUrl, 'http://provider.test:8080');
        expect(options.queryParameters['username'], 'myuser');
        expect(options.queryParameters['password'], 'myp@ss');
        expect(options.queryParameters.containsKey('action'), isFalse);
        return _jsonBody('''{
          "user_info": {"auth": 1, "status": "Active"}
        }''');
      };

      final info = await client.authenticate();
      expect(info.auth, isTrue);
      expect(info.status, 'Active');
    });

    test('getVodCategories builds action=get_vod_categories', () async {
      mockAdapter.handler = (options) {
        expect(options.queryParameters['action'], 'get_vod_categories');
        return _jsonBody('[{"category_id": "1", "category_name": "Action"}]');
      };
      final cats = await client.getVodCategories('src1');
      expect(cats.length, 1);
      expect(cats[0].categoryName, 'Action');
      expect(cats[0].type, 'vod');
    });

    test('getSeriesCategories builds action=get_series_categories', () async {
      mockAdapter.handler = (options) {
        expect(options.queryParameters['action'], 'get_series_categories');
        return _jsonBody('[{"category_id": "2", "category_name": "Drama"}]');
      };
      final cats = await client.getSeriesCategories('src1');
      expect(cats.length, 1);
      expect(cats[0].type, 'series');
    });

    test('getVodStreams builds action=get_vod_streams with category_id', () async {
      mockAdapter.handler = (options) {
        expect(options.queryParameters['action'], 'get_vod_streams');
        expect(options.queryParameters['category_id'], 'cat99');
        expect(options.responseType, ResponseType.plain);
        return ResponseBody.fromString(
          '[{"stream_id": 10, "name": "Matrix", "category_id": "cat99"}]',
          200,
        );
      };
      final streams = await client.getVodStreams('src1', categoryId: 'cat99');
      expect(streams.length, 1);
      expect(streams[0].streamId, '10');
      expect(streams[0].name, 'Matrix');
      expect(streams[0].isSeries, isFalse);
    });

    test('getVodStreams omits category_id when not provided', () async {
      mockAdapter.handler = (options) {
        expect(options.queryParameters.containsKey('category_id'), isFalse);
        return ResponseBody.fromString('[]', 200);
      };
      final streams = await client.getVodStreams('src1');
      expect(streams, isEmpty);
    });

    test('getSeries builds action=get_series with category_id', () async {
      mockAdapter.handler = (options) {
        expect(options.queryParameters['action'], 'get_series');
        expect(options.queryParameters['category_id'], 'cat5');
        return ResponseBody.fromString(
          '[{"series_id": 20, "name": "Breaking Bad", "category_id": "cat5"}]',
          200,
        );
      };
      final series = await client.getSeries('src1', categoryId: 'cat5');
      expect(series.length, 1);
      expect(series[0].streamId, '20');
      expect(series[0].isSeries, isTrue);
    });

    test('getSeriesInfo builds action=get_series_info with series_id', () async {
      mockAdapter.handler = (options) {
        expect(options.queryParameters['action'], 'get_series_info');
        expect(options.queryParameters['series_id'], 'ser55');
        return _jsonBody('''{
          "info": {"name": "Test Show", "plot": "Show plot"},
          "episodes": {
            "1": [{"id": "ep1", "episode_num": 1, "title": "Pilot"}]
          }
        }''');
      };
      final info = await client.getSeriesInfo('ser55');
      expect(info.name, 'Test Show');
      expect(info.totalEpisodes, 1);
      expect(info.getEpisodes('1').first.title, 'Pilot');
    });

    test('authenticate throws on auth:0 with HTTP 200', () async {
      mockAdapter.handler = (options) {
        return _jsonBody('{"user_info": {"auth": 0}}', 200);
      };
      expect(
        () => client.authenticate(),
        throwsA(isA<XtreamException>().having(
          (e) => e.message.toLowerCase(),
          'message',
          contains('invalid'),
        )),
      );
    });

    test('authenticate throws distinctly on auth:1 with non-Active status', () async {
      mockAdapter.handler = (options) {
        return _jsonBody(
          '{"user_info": {"auth": 1, "status": "Expired"}}',
          200,
        );
      };
      expect(
        () => client.authenticate(),
        throwsA(isA<XtreamException>().having(
          (e) => e.message,
          'message',
          allOf(isNot(contains('Invalid Xtream username or password')), contains('Expired')),
        )),
      );
    });

    // The UI branches on `kind` to decide what to tell the user to do, so the
    // classification is behaviour, not a detail. Matching on message text
    // instead would break silently the moment any wording changed.
    test('classifies rejected credentials as kind.credentials', () async {
      mockAdapter.handler = (options) =>
          _jsonBody('{"user_info": {"auth": 0}}', 200);

      await expectLater(
        client.authenticate(),
        throwsA(
          isA<XtreamException>()
              .having((e) => e.kind, 'kind', XtreamErrorKind.credentials)
              .having((e) => e.isAuthFailure, 'isAuthFailure', isTrue),
        ),
      );
    });

    test('classifies an expired account as kind.inactiveAccount', () async {
      mockAdapter.handler = (options) => _jsonBody(
            '{"user_info": {"auth": 1, "status": "Expired"}}',
            200,
          );

      await expectLater(
        client.authenticate(),
        throwsA(
          isA<XtreamException>()
              .having((e) => e.kind, 'kind', XtreamErrorKind.inactiveAccount)
              .having((e) => e.isAuthFailure, 'isAuthFailure', isTrue),
        ),
      );
    });

    test('classifies a malformed body as kind.protocol, not an auth failure',
        () async {
      mockAdapter.handler = (options) => _jsonBody('{"nonsense": true}', 200);

      await expectLater(
        client.authenticate(),
        throwsA(
          isA<XtreamException>()
              .having((e) => e.kind, 'kind', XtreamErrorKind.protocol)
              .having((e) => e.isAuthFailure, 'isAuthFailure', isFalse),
        ),
      );
    });

    // The message is shown verbatim in the UI, so it must never carry the
    // credential values themselves (the word "password" is fine).
    test('an exception message never contains the credential values', () async {
      mockAdapter.handler = (options) =>
          _jsonBody('{"user_info": {"auth": 0}}', 200);

      try {
        await client.authenticate();
        fail('expected authenticate() to throw');
      } on XtreamException catch (e) {
        expect(e.message, isNot(contains('myp@ss')));
        expect(e.message, isNot(contains('myuser')));
      }
    });

    test('authenticate parses valid response including exp_date', () async {
      mockAdapter.handler = (options) {
        return _jsonBody('''{
          "user_info": {
            "auth": 1,
            "status": "Active",
            "exp_date": "1893456000",
            "max_connections": "2",
            "is_trial": "0"
          }
        }''');
      };
      final info = await client.authenticate();
      expect(info.auth, isTrue);
      expect(info.status, 'Active');
      expect(info.expiresAt, isNotNull);
      expect(info.expiresAt!.year, 2030);
      expect(info.maxConnections, 2);
      expect(info.isTrial, isFalse);
    });

    test('normalizes a bare array response', () async {
      mockAdapter.handler = (options) => _jsonBody('[{"category_id": "1", "category_name": "A"}]');
      final cats = await client.getVodCategories('src1');
      expect(cats.length, 1);
    });

    test('normalizes a {"data": [...]} wrapped response', () async {
      mockAdapter.handler = (options) =>
          _jsonBody('{"data": [{"category_id": "1", "category_name": "A"}]}');
      final cats = await client.getVodCategories('src1');
      expect(cats.length, 1);
    });

    test('normalizes an empty object response to an empty list', () async {
      mockAdapter.handler = (options) => _jsonBody('{}');
      final cats = await client.getVodCategories('src1');
      expect(cats, isEmpty);
    });

    test('normalizes an empty array response', () async {
      mockAdapter.handler = (options) => _jsonBody('[]');
      final cats = await client.getVodCategories('src1');
      expect(cats, isEmpty);
    });
  });

  group('buildStreamUrl', () {
    late XtreamClient client;

    setUp(() {
      client = XtreamClient(
        baseUrl: 'http://provider.test:8080/',
        username: 'my user',
        password: 'p@ss word',
      );
    });

    test('builds movie url with encoded credentials', () {
      final url = client.buildStreamUrl(type: 'movie', id: '123', container: 'mp4');
      expect(
        url,
        'http://provider.test:8080/movie/${Uri.encodeComponent('my user')}/${Uri.encodeComponent('p@ss word')}/123.mp4',
      );
    });

    test('builds series url with encoded credentials', () {
      final url = client.buildStreamUrl(type: 'series', id: '456', container: 'mkv');
      expect(
        url,
        'http://provider.test:8080/series/${Uri.encodeComponent('my user')}/${Uri.encodeComponent('p@ss word')}/456.mkv',
      );
    });

    test('does not double a leading dot on the container extension', () {
      final url = client.buildStreamUrl(type: 'movie', id: '789', container: '.mp4');
      expect(url.endsWith('789.mp4'), isTrue);
      expect(url.contains('..'), isFalse);
    });
  });
}
