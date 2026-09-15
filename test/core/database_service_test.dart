import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vod_downloader/core/database/database_service.dart';
import 'package:vod_downloader/core/models/media_item.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Replicates the schema.
Future<void> _v1OnCreate(Database db, int version) async {
  await db.execute('''
    CREATE TABLE movies (
      stream_id TEXT PRIMARY KEY,
      category_id TEXT,
      name TEXT,
      sourceId TEXT,
      data TEXT
    )
  ''');
  await db.execute('CREATE INDEX idx_movies_source ON movies(sourceId)');
  await db.execute('CREATE INDEX idx_movies_cat ON movies(sourceId, category_id)');

  await db.execute('''
    CREATE TABLE series (
      series_id TEXT PRIMARY KEY,
      category_id TEXT,
      name TEXT,
      sourceId TEXT,
      data TEXT
    )
  ''');
  await db.execute('CREATE INDEX idx_series_source ON series(sourceId)');
  await db.execute('CREATE INDEX idx_series_cat ON series(sourceId, category_id)');

  await db.execute('''
    CREATE TABLE vod_categories (
      category_id TEXT,
      category_name TEXT,
      sourceId TEXT,
      PRIMARY KEY (category_id, sourceId)
    )
  ''');

  await db.execute('''
    CREATE TABLE series_categories (
      category_id TEXT,
      category_name TEXT,
      sourceId TEXT,
      PRIMARY KEY (category_id, sourceId)
    )
  ''');

  await db.execute('''
    CREATE TABLE sources (
      id TEXT PRIMARY KEY,
      name TEXT,
      url TEXT,
      username TEXT,
      data TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE meta (
      key TEXT PRIMARY KEY,
      value TEXT
    )
  ''');
}

Future<Database> _openV1Db(String path) {
  return databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(version: 1, onCreate: _v1OnCreate),
  );
}

/// Structural (not textual) schema description for a database: for each
/// known table, its ordered column definitions plus its indexes' ordered
/// columns. Used to compare a fresh onCreate() schema against a migrated
/// onUpgrade() schema without being sensitive to incidental SQL text
/// formatting differences between `CREATE TABLE ... col TYPE` and
/// `ALTER TABLE ... ADD COLUMN`.
Future<Map<String, dynamic>> _schemaSnapshot(Database db) async {
  const tables = [
    'movies',
    'series',
    'vod_categories',
    'series_categories',
    'sources',
    'meta',
    'downloads',
  ];
  final snapshot = <String, dynamic>{};

  for (final table in tables) {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    snapshot['columns:$table'] = columns
        .map((c) => '${c['name']}:${c['type']}:${c['notnull']}:${c['pk']}')
        .toList();

    final indexList = await db.rawQuery('PRAGMA index_list($table)');
    final indexNames = indexList.map((r) => r['name'] as String).toList()..sort();
    final indexDetails = <String, List<String>>{};
    for (final name in indexNames) {
      final info = await db.rawQuery('PRAGMA index_info($name)');
      indexDetails[name] = info.map((r) => r['name'] as String).toList();
    }
    snapshot['indexes:$table'] = indexDetails;
  }

  return snapshot;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late DatabaseService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('db_service_test_');
    DatabaseService.testDbPath = p.join(tempDir.path, 'test.db');
    await DatabaseService.resetForTest();
    service = DatabaseService.instance;
  });

  tearDown(() async {
    await DatabaseService.resetForTest();
    DatabaseService.testDbPath = null;
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('schema v1 -> v2 migration', () {
    test('preserves existing rows and adds the downloads table', () async {
      final v1Path = DatabaseService.testDbPath!;
      final v1Db = await _openV1Db(v1Path);

      const movieItem = MediaItem(
        streamId: 'm1',
        name: 'Old Movie',
        categoryId: 'cat1',
        sourceId: 'src1',
        rating: '7.5',
        year: '2001',
      );
      await v1Db.insert('movies', movieItem.toMap());

      const seriesItem = MediaItem(
        streamId: 's1',
        name: 'Old Series',
        categoryId: 'cat2',
        sourceId: 'src1',
        isSeries: true,
        rating: '8.0',
        year: '1999',
      );
      await v1Db.insert('series', seriesItem.toMap());

      await v1Db.insert('vod_categories', {
        'category_id': 'cat1',
        'category_name': 'Action',
        'sourceId': 'src1',
      });
      await v1Db.insert('sources', {
        'id': 'src1',
        'name': 'Test Source',
        'url': 'http://example.com',
        'username': 'user1',
        'data': '{}',
      });
      await v1Db.insert('meta', {
        'key': 'lastSync_src1',
        'value': '2020-01-01T00:00:00.000Z',
      });

      await v1Db.close();

      // Opening through the service at _dbVersion (2) must trigger onUpgrade
      // rather than throw, and existing rows must survive untouched.
      final movies = await service.getMovies('src1');
      final series = await service.getSeries('src1');
      final cats = await service.getCategories('src1', 'vod');
      final sources = await service.getSources();
      final meta = await service.getMeta('lastSync_src1');

      expect(movies.length, 1);
      expect(movies.first.streamId, 'm1');
      expect(movies.first.name, 'Old Movie');
      expect(series.length, 1);
      expect(series.first.streamId, 's1');
      expect(series.first.name, 'Old Series');
      expect(cats.length, 1);
      expect(cats.first.categoryName, 'Action');
      expect(sources.length, 1);
      expect(meta, '2020-01-01T00:00:00.000Z');

      // downloads table exists post-migration and is usable.
      await service.upsertDownload({
        'id': 'd1',
        'sourceId': 'src1',
        'title': 'x',
        'fileName': 'x.mp4',
        'status': 'queued',
        'progress': 0.0,
        'bytesTotal': 100,
        'localUri': null,
        'error': null,
        'createdAt': 1,
      });
      final dl = await service.getDownload('d1');
      expect(dl, isNotNull);

      // rating/year were backfilled from the JSON `data` blob during
      // migration.
      final db = await service.database;
      final rawMovie =
          await db.query('movies', where: 'stream_id = ?', whereArgs: ['m1']);
      expect(rawMovie.first['rating'], 7.5);
      expect(rawMovie.first['year'], 2001);

      final rawSeries =
          await db.query('series', where: 'series_id = ?', whereArgs: ['s1']);
      expect(rawSeries.first['rating'], 8.0);
      expect(rawSeries.first['year'], 1999);
    });

    test('fresh onCreate at v2 produces an identical schema to a migrated db',
        () async {
      final freshDb = await service.database;
      final freshSchema = await _schemaSnapshot(freshDb);
      await DatabaseService.resetForTest();

      final migPath = p.join(tempDir.path, 'migrated.db');
      final v1Db = await _openV1Db(migPath);
      await v1Db.close();

      DatabaseService.testDbPath = migPath;
      final migratedDb = await DatabaseService.instance.database;
      final migratedSchema = await _schemaSnapshot(migratedDb);

      expect(migratedSchema, freshSchema);
    });
  });

  group('chunked bulk writes', () {
    test('saveMovies round-trips ~5000 items across chunk boundaries',
        () async {
      final items = List.generate(
        5000,
        (i) => MediaItem(
          streamId: 'm$i',
          name: 'Movie $i',
          categoryId: 'cat${i % 5}',
          sourceId: 'srcBig',
          rating: (i % 10).toString(),
          year: (2000 + (i % 25)).toString(),
        ),
      );

      await service.saveMovies('srcBig', items);
      final result = await service.getMovies('srcBig');

      expect(result.length, 5000);
      expect(result.map((m) => m.streamId).toSet().length, 5000);
    });

    test('saveMovieRows stores pre-encoded rows directly', () async {
      final rows = List.generate(
        10,
        (i) => <String, dynamic>{
          'stream_id': 'r$i',
          'category_id': 'catA',
          'name': 'Row Movie $i',
          'sourceId': 'srcRows',
          'data': '{"name":"Row Movie $i","sourceId":"srcRows"}',
          'rating': 5.0,
          'year': 2010,
        },
      );

      await service.saveMovieRows('srcRows', rows);
      final result = await service.getMovies('srcRows');
      expect(result.length, 10);
    });

    test('saveSeries and saveSeriesRows round-trip', () async {
      final items = List.generate(
        50,
        (i) => MediaItem(
          streamId: 'se$i',
          name: 'Series $i',
          categoryId: 'catS',
          sourceId: 'srcSeries',
          isSeries: true,
        ),
      );
      await service.saveSeries('srcSeries', items);
      expect((await service.getSeries('srcSeries')).length, 50);
    });
  });

  group('searchMedia / countMedia', () {
    setUp(() async {
      final movies = [
        const MediaItem(
          streamId: '1',
          name: 'Alpha',
          categoryId: 'c1',
          sourceId: 'srcSearch',
          rating: '9.0',
          year: '2020',
        ),
        const MediaItem(
          streamId: '2',
          name: 'Bravo',
          categoryId: 'c1',
          sourceId: 'srcSearch',
          rating: '5.0',
          year: '2018',
        ),
        const MediaItem(
          streamId: '3',
          name: 'Charlie Alpha',
          categoryId: 'c2',
          sourceId: 'srcSearch',
          rating: '7.0',
          year: '2022',
        ),
        const MediaItem(
          streamId: '4',
          name: 'Delta',
          categoryId: 'c2',
          sourceId: 'srcSearch',
        ),
        const MediaItem(
          streamId: '5',
          name: 'echo',
          categoryId: 'c1',
          sourceId: 'srcSearch',
          rating: '3.0',
          year: '2015',
        ),
      ];
      await service.saveMovies('srcSearch', movies);
    });

    test('filters by case-insensitive substring query', () async {
      final result = await service.searchMedia(
        sourceId: 'srcSearch',
        isSeries: false,
        query: 'alpha',
        limit: 100,
      );
      expect(result.map((m) => m.streamId).toSet(), {'1', '3'});
    });

    test('filters by categoryId', () async {
      final result = await service.searchMedia(
        sourceId: 'srcSearch',
        isSeries: false,
        categoryId: 'c1',
        limit: 100,
      );
      expect(result.map((m) => m.streamId).toSet(), {'1', '2', '5'});
    });

    test('sorts name_asc and name_desc case-insensitively', () async {
      final asc = await service.searchMedia(
        sourceId: 'srcSearch',
        isSeries: false,
        sort: 'name_asc',
        limit: 100,
      );
      expect(asc.map((m) => m.name).toList(),
          ['Alpha', 'Bravo', 'Charlie Alpha', 'Delta', 'echo']);

      final desc = await service.searchMedia(
        sourceId: 'srcSearch',
        isSeries: false,
        sort: 'name_desc',
        limit: 100,
      );
      expect(desc.map((m) => m.name).toList(),
          ['echo', 'Delta', 'Charlie Alpha', 'Bravo', 'Alpha']);
    });

    test('sorts rating_desc with unrated rows last', () async {
      final result = await service.searchMedia(
        sourceId: 'srcSearch',
        isSeries: false,
        sort: 'rating_desc',
        limit: 100,
      );
      expect(result.map((m) => m.name).toList(),
          ['Alpha', 'Charlie Alpha', 'Bravo', 'echo', 'Delta']);
    });

    test('sorts year_desc with unset years last', () async {
      final result = await service.searchMedia(
        sourceId: 'srcSearch',
        isSeries: false,
        sort: 'year_desc',
        limit: 100,
      );
      expect(result.map((m) => m.name).toList(),
          ['Charlie Alpha', 'Alpha', 'Bravo', 'echo', 'Delta']);
    });

    test('pages correctly with limit/offset', () async {
      final page1 = await service.searchMedia(
        sourceId: 'srcSearch',
        isSeries: false,
        sort: 'name_asc',
        limit: 2,
        offset: 0,
      );
      final page2 = await service.searchMedia(
        sourceId: 'srcSearch',
        isSeries: false,
        sort: 'name_asc',
        limit: 2,
        offset: 2,
      );
      final page3 = await service.searchMedia(
        sourceId: 'srcSearch',
        isSeries: false,
        sort: 'name_asc',
        limit: 2,
        offset: 4,
      );

      expect(page1.map((m) => m.name).toList(), ['Alpha', 'Bravo']);
      expect(page2.map((m) => m.name).toList(), ['Charlie Alpha', 'Delta']);
      expect(page3.map((m) => m.name).toList(), ['echo']);
    });

    test('countMedia agrees with the unpaged result length', () async {
      final noFilterCount = await service.countMedia(
        sourceId: 'srcSearch',
        isSeries: false,
      );
      final noFilterList = await service.searchMedia(
        sourceId: 'srcSearch',
        isSeries: false,
        limit: 100,
      );
      expect(noFilterCount, noFilterList.length);
      expect(noFilterCount, 5);

      final catCount = await service.countMedia(
        sourceId: 'srcSearch',
        isSeries: false,
        categoryId: 'c1',
      );
      expect(catCount, 3);

      final queryCount = await service.countMedia(
        sourceId: 'srcSearch',
        isSeries: false,
        query: 'alpha',
      );
      expect(queryCount, 2);
    });
  });

  group('downloads CRUD', () {
    test('round-trips rows and clearCompletedDownloads only removes complete',
        () async {
      final rows = <Map<String, dynamic>>[
        {
          'id': 'd1',
          'sourceId': 'srcD',
          'title': 'A',
          'fileName': 'a.mp4',
          'status': 'queued',
          'progress': 0.0,
          'bytesTotal': 100,
          'localUri': null,
          'error': null,
          'createdAt': 1,
        },
        {
          'id': 'd2',
          'sourceId': 'srcD',
          'title': 'B',
          'fileName': 'b.mp4',
          'status': 'complete',
          'progress': 1.0,
          'bytesTotal': 200,
          'localUri': 'content://b',
          'error': null,
          'createdAt': 2,
        },
        {
          'id': 'd3',
          'sourceId': 'srcD',
          'title': 'C',
          'fileName': 'c.mp4',
          'status': 'complete',
          'progress': 1.0,
          'bytesTotal': 300,
          'localUri': 'content://c',
          'error': null,
          'createdAt': 3,
        },
        {
          'id': 'd4',
          'sourceId': 'other',
          'title': 'D',
          'fileName': 'd.mp4',
          'status': 'running',
          'progress': 0.5,
          'bytesTotal': 400,
          'localUri': null,
          'error': null,
          'createdAt': 4,
        },
      ];
      for (final row in rows) {
        await service.upsertDownload(row);
      }

      expect((await service.getDownloads()).length, 4);
      expect((await service.getDownloads(sourceId: 'srcD')).length, 3);

      final single = await service.getDownload('d2');
      expect(single, isNotNull);
      expect(single!['status'], 'complete');
      expect(await service.getDownload('missing'), isNull);

      // Upsert overwrites an existing row by id.
      await service.upsertDownload({...rows[0], 'status': 'running', 'progress': 0.3});
      final updated = await service.getDownload('d1');
      expect(updated!['status'], 'running');
      expect(updated['progress'], 0.3);

      await service.deleteDownload('d4');
      expect(await service.getDownload('d4'), isNull);

      await service.clearCompletedDownloads();
      final remaining = await service.getDownloads();
      expect(remaining.map((r) => r['id']).toSet(), {'d1'});
    });
  });
}
