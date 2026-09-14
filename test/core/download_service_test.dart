import 'package:flutter_test/flutter_test.dart';
import 'package:nodecast_catalog_flutter/core/models/media_item.dart';
import 'package:nodecast_catalog_flutter/core/models/series_details.dart';
import 'package:nodecast_catalog_flutter/core/services/download_service.dart';

void main() {
  group('DownloadService', () {
    late DownloadService downloadService;

    setUp(() {
      downloadService = DownloadService();
    });

    test('buildDownloadUrl formats correct download URL matching proxy endpoint', () {
      final url = downloadService.buildDownloadUrl(
        baseUrl: 'http://10.0.2.2:3000',
        sourceId: 'src_1',
        type: 'movie',
        itemId: '123',
        name: 'The Matrix (1999)',
        containerExtension: '.mp4',
      );

      expect(
        url,
        'http://10.0.2.2:3000/api/download/src_1/movie/123?container=mp4&name=The%20Matrix%20(1999)',
      );
    });

    test('getDownloadUrlForMedia constructs valid URL for movie', () {
      const item = MediaItem(
        streamId: '456',
        name: 'Interstellar',
        sourceId: 'src_1',
        containerExtension: 'mkv',
        isSeries: false,
      );

      final url = downloadService.getDownloadUrlForMedia(
        baseUrl: 'http://localhost:3000',
        sourceId: 'src_1',
        item: item,
      );

      expect(
        url,
        'http://localhost:3000/api/download/src_1/movie/456?container=mkv&name=Interstellar',
      );
    });

    test('getDownloadUrlForEpisode constructs valid URL for series episode', () {
      const ep = EpisodeItem(
        id: '999',
        episodeNum: '3',
        title: 'The Great War',
        containerExtension: 'mp4',
        seasonNum: '8',
      );

      final url = downloadService.getDownloadUrlForEpisode(
        baseUrl: 'http://localhost:3000',
        sourceId: 'src_1',
        episode: ep,
        seriesName: 'Game of Thrones',
      );

      expect(
        url,
        'http://localhost:3000/api/download/src_1/series/999?container=mp4&name=Game%20of%20Thrones%20S08E03%20-%20The%20Great%20War',
      );
    });

    test('sanitizeFileName removes forbidden characters', () {
      final sanitized = downloadService.sanitizeFileName('Movie: Episode 1 <Director\'s / Cut>? *yes* |');
      expect(sanitized, isNot(contains(':')));
      expect(sanitized, isNot(contains('<')));
      expect(sanitized, isNot(contains('/')));
      expect(sanitized, isNot(contains('?')));
      expect(sanitized, isNot(contains('*')));
      expect(sanitized, isNot(contains('|')));
    });
  });
}
