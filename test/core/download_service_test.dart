import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nodecast_catalog_flutter/core/models/media_item.dart';
import 'package:nodecast_catalog_flutter/core/models/series_details.dart';
import 'package:nodecast_catalog_flutter/core/network/xtream_client.dart';
import 'package:nodecast_catalog_flutter/core/services/download_service.dart';

/// Credentials used across the suite. The password is deliberately a string
/// that would be obvious if it ever leaked into an error message.
const _kUser = 'joe';
const _kPass = 's3cr3t-p4ss';

DownloadService _serviceWithAccount({String baseUrl = 'http://provider.tv:8080'}) {
  return DownloadService(
    client: XtreamClient(
      baseUrl: baseUrl,
      username: _kUser,
      password: _kPass,
    ),
  );
}

void main() {
  group('DownloadService URL construction', () {
    late DownloadService service;

    setUp(() => service = _serviceWithAccount());

    test('builds a direct provider URL for a movie, not a proxy URL', () {
      final url = service.buildDownloadUrl(
        type: 'movie',
        itemId: '123',
        containerExtension: 'mp4',
      );

      expect(url, 'http://provider.tv:8080/movie/$_kUser/$_kPass/123.mp4');
      // The proxy is gone; nothing may point back at it.
      expect(url, isNot(contains('/api/download')));
    });

    test('builds a direct provider URL for a series episode', () {
      final url = service.buildDownloadUrl(
        type: 'series',
        itemId: '999',
        containerExtension: 'mkv',
      );

      expect(url, 'http://provider.tv:8080/series/$_kUser/$_kPass/999.mkv');
    });

    test('strips a leading dot from the container extension', () {
      final url = service.buildDownloadUrl(
        type: 'movie',
        itemId: '1',
        containerExtension: '.mkv',
      );

      expect(url, endsWith('/1.mkv'));
      expect(url, isNot(contains('..mkv')));
    });

    test('defaults to mp4 when the container is missing or blank', () {
      final missing = service.buildDownloadUrl(type: 'movie', itemId: '1');
      final blank = service.buildDownloadUrl(
        type: 'movie',
        itemId: '2',
        containerExtension: '   ',
      );

      expect(missing, endsWith('/1.mp4'));
      expect(blank, endsWith('/2.mp4'));
    });

    test('normalises a base URL that has a trailing slash', () {
      final url = _serviceWithAccount(baseUrl: 'http://provider.tv:8080/')
          .buildDownloadUrl(type: 'movie', itemId: '7', containerExtension: 'mp4');

      expect(url, 'http://provider.tv:8080/movie/$_kUser/$_kPass/7.mp4');
      expect(url, isNot(contains('//movie')));
    });

    test('getDownloadUrlForMedia routes movies and series to the right path', () {
      const movie = MediaItem(
        streamId: '456',
        name: 'Interstellar',
        sourceId: 'src_1',
        containerExtension: 'mkv',
        isSeries: false,
      );
      const series = MediaItem(
        streamId: '789',
        name: 'Severance',
        sourceId: 'src_1',
        containerExtension: 'mp4',
        isSeries: true,
      );

      expect(
        service.getDownloadUrlForMedia(item: movie),
        'http://provider.tv:8080/movie/$_kUser/$_kPass/456.mkv',
      );
      expect(
        service.getDownloadUrlForMedia(item: series),
        'http://provider.tv:8080/series/$_kUser/$_kPass/789.mp4',
      );
    });

    test('returns null for items and episodes with no usable id', () {
      const noId = MediaItem(streamId: '', name: 'Broken', sourceId: 'src_1');
      const noEpId = EpisodeItem(id: '', episodeNum: '1', title: 'Broken');

      expect(service.getDownloadUrlForMedia(item: noId), isNull);
      expect(service.getDownloadUrlForEpisode(episode: noEpId), isNull);
    });
  });

  group('episode naming', () {
    late DownloadService service;

    setUp(() => service = _serviceWithAccount());

    test('zero-pads season and episode numbers', () {
      const ep = EpisodeItem(
        id: '999',
        episodeNum: '3',
        title: 'The Great War',
        containerExtension: 'mp4',
        seasonNum: '8',
      );

      expect(
        service.formatEpisodeTitle(seriesName: 'Game of Thrones', episode: ep),
        'Game of Thrones S08E03 - The Great War',
      );
    });

    test('an explicit seasonNum overrides the episode\'s own', () {
      const ep = EpisodeItem(
        id: '1',
        episodeNum: '12',
        title: 'Finale',
        seasonNum: '1',
      );

      expect(
        service.formatEpisodeTitle(
          seriesName: 'Show',
          episode: ep,
          seasonNum: '2',
        ),
        'Show S02E12 - Finale',
      );
    });

    test('falls back to season 1 when no season is known', () {
      const ep = EpisodeItem(id: '1', episodeNum: '5', title: 'Pilot');

      expect(
        service.formatEpisodeTitle(seriesName: 'Show', episode: ep),
        'Show S01E05 - Pilot',
      );
    });

    test('sanitizeFileName strips characters illegal in filenames', () {
      final sanitized = service.sanitizeFileName(
        'Movie: Episode 1 <Director\'s / Cut>? *yes* |',
      );

      for (final illegal in ['<', '>', ':', '"', '/', r'\', '|', '?', '*']) {
        expect(sanitized, isNot(contains(illegal)),
            reason: 'should not contain $illegal');
      }
    });

    test('a sanitised episode filename keeps the S..E.. structure', () {
      const ep = EpisodeItem(
        id: '1',
        episodeNum: '2',
        title: 'Who/What: Why?',
        seasonNum: '3',
      );

      final name = service.sanitizeFileName(
        service.formatEpisodeTitle(seriesName: 'Show', episode: ep),
      );

      expect(name, startsWith('Show S03E02 - '));
      expect(name, isNot(contains('/')));
      expect(name, isNot(contains('?')));
    });
  });

  group('credential redaction', () {
    late DownloadService service;

    setUp(() => service = _serviceWithAccount());

    test('hides both username and password in a stream URL', () {
      final url = service.buildDownloadUrl(
        type: 'movie',
        itemId: '123',
        containerExtension: 'mp4',
      );
      final redacted = service.redactCredentials(url);

      expect(redacted, isNot(contains(_kPass)));
      expect(redacted, isNot(contains(_kUser)));
      // Still recognisable as the same request.
      expect(redacted, contains('/movie/'));
      expect(redacted, contains('123.mp4'));
    });

    test('hides query-string style credentials too', () {
      final redacted = service.redactCredentials(
        'http://provider.tv/player_api.php?username=$_kUser&password=$_kPass&action=get_series',
      );

      expect(redacted, isNot(contains(_kPass)));
      expect(redacted, isNot(contains(_kUser)));
      expect(redacted, contains('action=get_series'));
    });

    test('leaves a URL with no credentials untouched', () {
      const plain = 'http://provider.tv/images/poster.jpg';
      expect(service.redactCredentials(plain), plain);
    });

    test('a failed download throws with credentials already redacted', () async {
      // Port 1 is reserved and unbindable, so the request fails fast rather
      // than reaching a real host.
      final failing = _serviceWithAccount(baseUrl: 'http://127.0.0.1:1');
      final url = failing.buildDownloadUrl(
        type: 'movie',
        itemId: '123',
        containerExtension: 'mp4',
      );

      await expectLater(
        failing.downloadFile(
          downloadUrl: url,
          destinationPath: '${Directory.systemTemp.path}/dl_redaction_test.mp4',
        ),
        throwsA(
          isA<DownloadServiceException>().having(
            (e) => e.toString(),
            'message',
            allOf(isNot(contains(_kPass)), isNot(contains(_kUser))),
          ),
        ),
      );
    });
  });

  group('no active account', () {
    test('URL building fails with a clear error rather than a bad URL', () {
      final service = DownloadService(); // no client injected

      expect(
        () => service.buildDownloadUrl(type: 'movie', itemId: '1'),
        throwsA(
          isA<DownloadServiceException>().having(
            (e) => e.toString(),
            'message',
            contains('No active Xtream account'),
          ),
        ),
      );
    });

    test('the same failure surfaces through the high-level helpers', () {
      final service = DownloadService();
      const item = MediaItem(
        streamId: '1',
        name: 'Movie',
        sourceId: 'src_1',
      );

      expect(
        () => service.getDownloadUrlForMedia(item: item),
        throwsA(isA<DownloadServiceException>()),
      );
    });
  });
}
