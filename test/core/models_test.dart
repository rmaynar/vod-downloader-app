import 'package:flutter_test/flutter_test.dart';
import 'package:nodecast_catalog_flutter/core/models/category_item.dart';
import 'package:nodecast_catalog_flutter/core/models/media_item.dart';
import 'package:nodecast_catalog_flutter/core/models/series_details.dart';
import 'package:nodecast_catalog_flutter/core/models/source_account.dart';

void main() {
  group('MediaItem', () {
    test('parses movie correctly from JSON', () {
      final json = {
        'stream_id': 1001,
        'name': 'Inception',
        'category_id': '10',
        'category_name': 'Action',
        'stream_icon': 'https://example.com/inception.jpg',
        'rating': '8.8',
        'year': '2010',
        'container_extension': 'mp4',
      };

      final item = MediaItem.fromJson(json, 'src_1', isSeries: false);
      expect(item.streamId, '1001');
      expect(item.name, 'Inception');
      expect(item.categoryId, '10');
      expect(item.categoryName, 'Action');
      expect(item.posterUrl, 'https://example.com/inception.jpg');
      expect(item.formattedRating, '8.8');
      expect(item.displayYear, '2010');
      expect(item.isSeries, false);
      expect(item.type, MediaType.movie);
    });

    test('parses series correctly and extracts year from releaseDate', () {
      final json = {
        'series_id': 5005,
        'name': 'Breaking Bad',
        'category_id': '20',
        'cover': 'https://example.com/bb.jpg',
        'rating': 0,
        'rating_5based': 4.75,
        'releaseDate': '2008-01-20',
        'plot': 'A chemistry teacher diagnosed with cancer...',
      };

      final item = MediaItem.fromJson(json, 'src_1', isSeries: true);
      expect(item.streamId, '5005');
      expect(item.name, 'Breaking Bad');
      expect(item.posterUrl, 'https://example.com/bb.jpg');
      expect(item.formattedRating, '9.5'); // 4.75 * 2
      expect(item.displayYear, '2008');
      expect(item.isSeries, true);
      expect(item.type, MediaType.series);
    });

    test('SQLite serialization toMap and fromMap works seamlessly', () {
      const original = MediaItem(
        streamId: '42',
        name: 'The Hitchhiker',
        categoryId: '5',
        categoryName: 'Sci-Fi',
        streamIcon: 'https://example.com/guide.jpg',
        rating: '7.5',
        year: '2005',
        containerExtension: 'mkv',
        sourceId: 'src_99',
        isSeries: false,
      );

      final map = original.toMap();
      expect(map['stream_id'], '42');
      expect(map['name'], 'The Hitchhiker');
      expect(map['sourceId'], 'src_99');
      expect(map['data'], isA<String>());

      final restored = MediaItem.fromMap(map);
      expect(restored.streamId, original.streamId);
      expect(restored.name, original.name);
      expect(restored.categoryId, original.categoryId);
      expect(restored.categoryName, original.categoryName);
      expect(restored.streamIcon, original.streamIcon);
      expect(restored.formattedRating, '7.5');
      expect(restored.displayYear, '2005');
      expect(restored.sourceId, 'src_99');
      expect(restored.isSeries, false);
    });
  });

  group('CategoryItem', () {
    test('JSON and SQLite serialization', () {
      final json = {
        'category_id': '101',
        'category_name': 'Documentaries',
      };

      final cat = CategoryItem.fromJson(json, 'src_1', 'vod');
      expect(cat.categoryId, '101');
      expect(cat.categoryName, 'Documentaries');
      expect(cat.sourceId, 'src_1');
      expect(cat.type, 'vod');

      final dbMap = cat.toMap();
      expect(dbMap['category_id'], '101');
      expect(dbMap['category_name'], 'Documentaries');
      expect(dbMap['sourceId'], 'src_1');

      final restored = CategoryItem.fromMap(dbMap, 'vod');
      expect(restored.categoryId, cat.categoryId);
      expect(restored.categoryName, cat.categoryName);
      expect(restored.sourceId, cat.sourceId);
      expect(restored.type, 'vod');
    });
  });

  group('SourceAccount', () {
    test('JSON and SQLite serialization', () {
      final json = {
        'id': 'src_123',
        'name': 'Fast IPTV',
        'url': 'http://iptv.example.com',
        'username': 'testuser',
        'password': 'secretpassword',
        'lastUsedAt': 1700000000000,
      };

      final source = SourceAccount.fromJson(json);
      expect(source.id, 'src_123');
      expect(source.name, 'Fast IPTV');
      expect(source.url, 'http://iptv.example.com');
      expect(source.username, 'testuser');
      expect(source.password, 'secretpassword');
      expect(source.lastUsedAt, 1700000000000);

      final dbMap = source.toMap();
      expect(dbMap['id'], 'src_123');
      expect(dbMap['name'], 'Fast IPTV');
      expect(dbMap['data'], isA<String>());

      final restored = SourceAccount.fromMap(dbMap);
      expect(restored.id, source.id);
      expect(restored.name, source.name);
      expect(restored.url, source.url);
      expect(restored.username, source.username);
      expect(restored.password, source.password);
    });
  });

  group('SeriesDetails and EpisodeItem', () {
    test('parses episodes map of season arrays and sorts numerically', () {
      final json = {
        'info': {
          'name': 'Game of Thrones',
          'plot': 'Nine noble families fight for control...',
          'cover': 'https://example.com/got.jpg',
          'rating': '9.3',
        },
        'episodes': {
          '2': [
            {
              'id': '201',
              'episode_num': 2,
              'title': 'The Night Lands',
              'container_extension': 'mkv',
            },
            {
              'id': '200',
              'episode_num': 1,
              'title': 'The North Remembers',
              'container_extension': 'mkv',
            },
          ],
          '1': [
            {
              'id': '100',
              'episode_num': 1,
              'title': 'Winter Is Coming',
              'container_extension': 'mp4',
            },
          ],
        },
      };

      final details = SeriesDetails.fromJson(json);
      expect(details.name, 'Game of Thrones');
      expect(details.rating, '9.3');
      expect(details.seasonNumbers, ['1', '2']);
      expect(details.totalEpisodes, 3);

      final s2Episodes = details.getEpisodes('2');
      expect(s2Episodes.length, 2);
      expect(s2Episodes[0].episodeNum, '1');
      expect(s2Episodes[0].title, 'The North Remembers');
      expect(s2Episodes[1].episodeNum, '2');
      expect(s2Episodes[1].title, 'The Night Lands');
    });

    test('handles empty episodes list gracefully', () {
      final json = {
        'info': {'name': 'Empty Show'},
        'episodes': [],
      };

      final details = SeriesDetails.fromJson(json);
      expect(details.name, 'Empty Show');
      expect(details.seasonNumbers, isEmpty);
      expect(details.totalEpisodes, 0);
    });
  });
}
