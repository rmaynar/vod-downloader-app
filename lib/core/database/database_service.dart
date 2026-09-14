import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/account.dart';
import '../models/catalog_stats.dart';
import '../models/category_item.dart';
import '../models/media_item.dart';

/// SQLite Database Service managing local caching of catalogs, sources, and metadata.
/// Replaces Dexie/IndexedDB from the React application.
class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  factory DatabaseService() => instance;

  static const String _dbName = 'vod_catalog.db';
  static const int _dbVersion = 2;

  /// Number of rows written per `batch.commit()` call during bulk inserts.
  /// Keeps a single write transaction for ~40k+ item catalogs from blocking
  /// the isolate for seconds at a time (and risking an ANR) while still
  /// committing atomically as one outer transaction.
  static const int _writeChunkSize = 2000;

  /// Overrides the full database path used by [database]. Intended for
  /// tests only, so each test can point the singleton at an isolated
  /// in-memory or temp-file database instead of the real on-device path.
  @visibleForTesting
  static String? testDbPath;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDb(_dbName);
    return _database!;
  }

  Future<Database> _initDb(String filePath) async {
    final path = testDbPath ?? join(await getDatabasesPath(), filePath);

    return await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _createDb,
      onUpgrade: _onUpgrade,
    );
  }

  /// Closes and clears the cached database handle so the next [database]
  /// access opens a fresh connection (honoring any new [testDbPath]).
  /// Intended for tests only.
  @visibleForTesting
  static Future<void> resetForTest() async {
    final db = _database;
    _database = null;
    if (db != null && db.isOpen) {
      await db.close();
    }
  }

  Future<void> _createDb(Database db, int version) async {
    // Movies table. `rating`/`year` are indexed sort columns extracted from
    // the JSON `data` blob at write time (see _movieRow) so searchMedia can
    // sort large catalogs in SQL instead of decoding JSON for every row in
    // Dart.
    await db.execute('''
      CREATE TABLE movies (
        stream_id TEXT PRIMARY KEY,
        category_id TEXT,
        name TEXT,
        sourceId TEXT,
        data TEXT,
        rating REAL,
        year INTEGER
      )
    ''');
    await db.execute('CREATE INDEX idx_movies_source ON movies(sourceId)');
    await db.execute('CREATE INDEX idx_movies_cat ON movies(sourceId, category_id)');
    await db.execute('CREATE INDEX idx_movies_rating ON movies(sourceId, rating)');
    await db.execute('CREATE INDEX idx_movies_year ON movies(sourceId, year)');

    // Series table
    await db.execute('''
      CREATE TABLE series (
        series_id TEXT PRIMARY KEY,
        category_id TEXT,
        name TEXT,
        sourceId TEXT,
        data TEXT,
        rating REAL,
        year INTEGER
      )
    ''');
    await db.execute('CREATE INDEX idx_series_source ON series(sourceId)');
    await db.execute('CREATE INDEX idx_series_cat ON series(sourceId, category_id)');
    await db.execute('CREATE INDEX idx_series_rating ON series(sourceId, rating)');
    await db.execute('CREATE INDEX idx_series_year ON series(sourceId, year)');

    // VOD Categories table
    await db.execute('''
      CREATE TABLE vod_categories (
        category_id TEXT,
        category_name TEXT,
        sourceId TEXT,
        PRIMARY KEY (category_id, sourceId)
      )
    ''');

    // Series Categories table
    await db.execute('''
      CREATE TABLE series_categories (
        category_id TEXT,
        category_name TEXT,
        sourceId TEXT,
        PRIMARY KEY (category_id, sourceId)
      )
    ''');

    // Sources table
    await db.execute('''
      CREATE TABLE sources (
        id TEXT PRIMARY KEY,
        name TEXT,
        url TEXT,
        username TEXT,
        data TEXT
      )
    ''');

    // Metadata key-value table
    await db.execute('''
      CREATE TABLE meta (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    // Downloads table — defined once in _createDownloadsTable and reused by
    // _migrateToV2 so the fresh-install and upgraded schemas can never
    // diverge.
    await _createDownloadsTable(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _migrateToV2(db);
    }
  }

  /// v1 -> v2 migration. Runs against devices that already hold a v1
  /// database (movies/series/vod_categories/series_categories/sources/meta,
  /// no `downloads` table, no rating/year columns). Only ever ADDs schema
  /// and backfills data — never drops or rewrites existing tables/rows, so
  /// existing cached catalogs survive the upgrade.
  Future<void> _migrateToV2(Database db) async {
    await _createDownloadsTable(db);

    await db.execute('ALTER TABLE movies ADD COLUMN rating REAL');
    await db.execute('ALTER TABLE movies ADD COLUMN year INTEGER');
    await db.execute('CREATE INDEX idx_movies_rating ON movies(sourceId, rating)');
    await db.execute('CREATE INDEX idx_movies_year ON movies(sourceId, year)');

    await db.execute('ALTER TABLE series ADD COLUMN rating REAL');
    await db.execute('ALTER TABLE series ADD COLUMN year INTEGER');
    await db.execute('CREATE INDEX idx_series_rating ON series(sourceId, rating)');
    await db.execute('CREATE INDEX idx_series_year ON series(sourceId, year)');

    // Backfill rating/year for rows cached before the columns existed, by
    // decoding each row's JSON `data` blob once. Done in chunks (same
    // _writeChunkSize as bulk writes) to bound peak memory/time per batch
    // for large existing catalogs.
    await _backfillRatingYear(db, table: 'movies', idColumn: 'stream_id');
    await _backfillRatingYear(db, table: 'series', idColumn: 'series_id');
  }

  /// Creates the `downloads` table + its (sourceId, status) index. Shared by
  /// both _createDb (fresh installs) and _migrateToV2 (existing installs) so
  /// the two paths cannot drift apart.
  Future<void> _createDownloadsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE downloads (
        id          TEXT PRIMARY KEY,
        sourceId    TEXT,
        title       TEXT,
        fileName    TEXT,
        status      TEXT,
        progress    REAL,
        bytesTotal  INTEGER,
        localUri    TEXT,
        error       TEXT,
        createdAt   INTEGER
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_downloads_source_status ON downloads(sourceId, status)',
    );
  }

  Future<void> _backfillRatingYear(
    Database db, {
    required String table,
    required String idColumn,
  }) async {
    int offset = 0;
    while (true) {
      final rows = await db.query(
        table,
        columns: [idColumn, 'data'],
        orderBy: 'rowid',
        limit: _writeChunkSize,
        offset: offset,
      );
      if (rows.isEmpty) break;

      final batch = db.batch();
      for (final row in rows) {
        final id = row[idColumn];
        final dataStr = row['data'];
        double? rating;
        int? year;
        if (dataStr is String && dataStr.isNotEmpty) {
          try {
            final decoded = jsonDecode(dataStr) as Map<String, dynamic>;
            // Reuse MediaItem's own rating/year parsing (fallback to
            // rating_5based, year regex extraction from release_date, etc.)
            // instead of duplicating that logic here.
            final item = MediaItem.fromJson(decoded, '');
            rating = item.formattedRating != null ? item.numericRating : null;
            final y = item.displayYear;
            year = y != null ? int.tryParse(y) : null;
          } catch (_) {
            // Malformed cached JSON: leave rating/year null rather than
            // fail the whole migration.
          }
        }
        batch.update(
          table,
          {'rating': rating, 'year': year},
          where: '$idColumn = ?',
          whereArgs: [id],
        );
      }
      await batch.commit(noResult: true);

      if (rows.length < _writeChunkSize) break;
      offset += _writeChunkSize;
    }
  }

  Map<String, dynamic> _movieRow(MediaItem movie) {
    final row = movie.toMap();
    row['rating'] = movie.formattedRating != null ? movie.numericRating : null;
    final y = movie.displayYear;
    row['year'] = y != null ? int.tryParse(y) : null;
    return row;
  }

  Map<String, dynamic> _seriesRow(MediaItem series) {
    final row = series.toMap();
    row['rating'] = series.formattedRating != null ? series.numericRating : null;
    final y = series.displayYear;
    row['year'] = y != null ? int.tryParse(y) : null;
    return row;
  }

  /// Inserts [rows] into [table] in chunks of [_writeChunkSize], all within
  /// the caller's transaction (so a failure partway through does not leave
  /// a half-written catalog — the whole thing rolls back).
  Future<void> _chunkedInsert(
    DatabaseExecutor txn,
    String table,
    List<Map<String, dynamic>> rows,
  ) async {
    for (var i = 0; i < rows.length; i += _writeChunkSize) {
      final end = i + _writeChunkSize < rows.length ? i + _writeChunkSize : rows.length;
      final chunk = rows.sublist(i, end);
      final batch = txn.batch();
      for (final row in chunk) {
        batch.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    }
  }

  /// Save movies list for a given source. Replaces existing cached movies for this source.
  Future<void> saveMovies(String sourceId, List<MediaItem> movies) {
    return saveMovieRows(sourceId, movies.map(_movieRow).toList());
  }

  /// Save pre-encoded movie rows (e.g. built via [MediaItem.toMap] on a
  /// background isolate, so the caller of [saveMovies] doesn't pay for
  /// `jsonEncode` twice) for a given source. Replaces existing cached movies
  /// for this source.
  ///
  /// Rows that already carry 'rating' (REAL) / 'year' (INTEGER) keys get
  /// indexed sort support in [searchMedia] for free. Rows without them are
  /// stored with NULL rating/year — they still work for name/category
  /// search, they just sort after rated/dated rows under rating_desc /
  /// year_desc (SQLite orders NULL last in DESC order).
  Future<void> saveMovieRows(String sourceId, List<Map<String, dynamic>> rows) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'movies',
        where: 'sourceId = ?',
        whereArgs: [sourceId],
      );
      await _chunkedInsert(txn, 'movies', rows);
    });
  }

  /// Get all movies for a given source, or all sources if [sourceId] is empty.
  Future<List<MediaItem>> getMovies(String sourceId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps;
    if (sourceId.isNotEmpty) {
      maps = await db.query(
        'movies',
        where: 'sourceId = ?',
        whereArgs: [sourceId],
      );
    } else {
      maps = await db.query('movies');
    }

    return maps.map((m) => MediaItem.fromMap(m)).toList();
  }

  /// Save TV series list for a given source. Replaces existing cached series for this source.
  Future<void> saveSeries(String sourceId, List<MediaItem> seriesList) {
    return saveSeriesRows(sourceId, seriesList.map(_seriesRow).toList());
  }

  /// Save pre-encoded series rows. See [saveMovieRows] for the rating/year
  /// column contract.
  Future<void> saveSeriesRows(String sourceId, List<Map<String, dynamic>> rows) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'series',
        where: 'sourceId = ?',
        whereArgs: [sourceId],
      );
      await _chunkedInsert(txn, 'series', rows);
    });
  }

  /// Get all TV series for a given source, or all sources if [sourceId] is empty.
  Future<List<MediaItem>> getSeries(String sourceId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps;
    if (sourceId.isNotEmpty) {
      maps = await db.query(
        'series',
        where: 'sourceId = ?',
        whereArgs: [sourceId],
      );
    } else {
      maps = await db.query('series');
    }

    return maps.map((m) => MediaItem.fromMap(m)).toList();
  }

  /// Search cached movies/series for a source with optional query/category
  /// filters, SQL-side sort, and limit/offset paging.
  Future<List<MediaItem>> searchMedia({
    required String sourceId,
    required bool isSeries,
    String? query,
    String? categoryId,
    String sort = 'name_asc',
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await database;
    final table = isSeries ? 'series' : 'movies';
    final where = <String>['sourceId = ?'];
    final args = <dynamic>[sourceId];

    if (categoryId != null && categoryId.isNotEmpty) {
      where.add('category_id = ?');
      args.add(categoryId);
    }
    final trimmedQuery = query?.trim();
    if (trimmedQuery != null && trimmedQuery.isNotEmpty) {
      where.add('LOWER(name) LIKE ?');
      args.add('%${trimmedQuery.toLowerCase()}%');
    }

    final maps = await db.query(
      table,
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: _orderByForSort(sort),
      limit: limit,
      offset: offset,
    );
    return maps.map((m) => MediaItem.fromMap(m)).toList();
  }

  /// Count of rows [searchMedia] would return for the same filters, ignoring
  /// sort/limit/offset.
  Future<int> countMedia({
    required String sourceId,
    required bool isSeries,
    String? query,
    String? categoryId,
  }) async {
    final db = await database;
    final table = isSeries ? 'series' : 'movies';
    final where = <String>['sourceId = ?'];
    final args = <dynamic>[sourceId];

    if (categoryId != null && categoryId.isNotEmpty) {
      where.add('category_id = ?');
      args.add(categoryId);
    }
    final trimmedQuery = query?.trim();
    if (trimmedQuery != null && trimmedQuery.isNotEmpty) {
      where.add('LOWER(name) LIKE ?');
      args.add('%${trimmedQuery.toLowerCase()}%');
    }

    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $table WHERE ${where.join(' AND ')}',
      args,
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  String _orderByForSort(String sort) {
    switch (sort) {
      case 'name_desc':
        return 'name COLLATE NOCASE DESC';
      case 'rating_desc':
        return 'rating DESC, name COLLATE NOCASE ASC';
      case 'year_desc':
        return 'year DESC, name COLLATE NOCASE ASC';
      case 'name_asc':
      default:
        return 'name COLLATE NOCASE ASC';
    }
  }

  /// Upsert a download row. [row] must include an 'id' key (primary key);
  /// callers own the shape of the rest of the row (status/progress/etc.) —
  /// this layer stays model-agnostic and just stores whatever map is given.
  Future<void> upsertDownload(Map<String, dynamic> row) async {
    final db = await database;
    await db.insert(
      'downloads',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// All download rows, optionally filtered to one source, newest first.
  Future<List<Map<String, dynamic>>> getDownloads({String? sourceId}) async {
    final db = await database;
    if (sourceId != null && sourceId.isNotEmpty) {
      return db.query(
        'downloads',
        where: 'sourceId = ?',
        whereArgs: [sourceId],
        orderBy: 'createdAt DESC',
      );
    }
    return db.query('downloads', orderBy: 'createdAt DESC');
  }

  /// A single download row by id, or null if not found.
  Future<Map<String, dynamic>?> getDownload(String id) async {
    final db = await database;
    final rows = await db.query(
      'downloads',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> deleteDownload(String id) async {
    final db = await database;
    await db.delete('downloads', where: 'id = ?', whereArgs: [id]);
  }

  /// Remove all downloads with status == 'complete'. Leaves queued/running/
  /// paused/failed/canceled rows untouched.
  Future<void> clearCompletedDownloads() async {
    final db = await database;
    await db.delete('downloads', where: 'status = ?', whereArgs: ['complete']);
  }

  /// Save categories for a source and type ('vod' or 'series').
  Future<void> saveCategories(
    String sourceId,
    String type,
    List<CategoryItem> categories,
  ) async {
    final db = await database;
    final table = type == 'vod' ? 'vod_categories' : 'series_categories';

    await db.transaction((txn) async {
      await txn.delete(
        table,
        where: 'sourceId = ?',
        whereArgs: [sourceId],
      );

      final batch = txn.batch();
      for (final cat in categories) {
        batch.insert(
          table,
          cat.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// Get categories for a given source and type ('vod' or 'series').
  Future<List<CategoryItem>> getCategories(String sourceId, String type) async {
    final db = await database;
    final table = type == 'vod' ? 'vod_categories' : 'series_categories';
    final List<Map<String, dynamic>> maps;

    if (sourceId.isNotEmpty) {
      maps = await db.query(
        table,
        where: 'sourceId = ?',
        whereArgs: [sourceId],
      );
    } else {
      maps = await db.query(table);
    }

    return maps.map((m) => CategoryItem.fromMap(m, type)).toList();
  }

  /// Save configured source accounts list.
  Future<void> saveSources(List<SourceAccount> sourcesList) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('sources');

      final batch = txn.batch();
      for (final s in sourcesList) {
        batch.insert(
          'sources',
          s.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// Get all cached source accounts.
  Future<List<SourceAccount>> getSources() async {
    final db = await database;
    final maps = await db.query('sources');
    return maps.map((m) => SourceAccount.fromMap(m)).toList();
  }

  /// Set metadata key-value pair.
  Future<void> setMeta(String key, String value) async {
    final db = await database;
    await db.insert(
      'meta',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get metadata value by key.
  Future<String?> getMeta(String key) async {
    final db = await database;
    final results = await db.query(
      'meta',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (results.isNotEmpty) {
      return results.first['value']?.toString();
    }
    return null;
  }

  /// Clear cached catalog data for a specific source.
  Future<void> clearSourceData(String sourceId) async {
    if (sourceId.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('movies', where: 'sourceId = ?', whereArgs: [sourceId]);
      await txn.delete('series', where: 'sourceId = ?', whereArgs: [sourceId]);
      await txn.delete('vod_categories', where: 'sourceId = ?', whereArgs: [sourceId]);
      await txn.delete('series_categories', where: 'sourceId = ?', whereArgs: [sourceId]);
    });
  }

  /// Clear all cached catalog data and metadata.
  Future<void> clearCatalog() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('movies');
      await txn.delete('series');
      await txn.delete('vod_categories');
      await txn.delete('series_categories');
      await txn.delete('meta');
    });
  }

  Future<void> clearAllCache() async {
    await clearCatalog();
  }

  Future<CatalogStats> getCatalogStats(dynamic sourceId) async {
    final db = await database;
    final sid = sourceId?.toString() ?? '';

    int movieCount = 0;
    int seriesCount = 0;
    int vodCatCount = 0;
    int seriesCatCount = 0;
    DateTime? lastSync;

    if (sid.isNotEmpty) {
      final mRes = await db.rawQuery(
        'SELECT COUNT(*) as count FROM movies WHERE sourceId = ?',
        [sid],
      );
      movieCount = Sqflite.firstIntValue(mRes) ?? 0;

      final sRes = await db.rawQuery(
        'SELECT COUNT(*) as count FROM series WHERE sourceId = ?',
        [sid],
      );
      seriesCount = Sqflite.firstIntValue(sRes) ?? 0;

      final vcRes = await db.rawQuery(
        'SELECT COUNT(*) as count FROM vod_categories WHERE sourceId = ?',
        [sid],
      );
      vodCatCount = Sqflite.firstIntValue(vcRes) ?? 0;

      final scRes = await db.rawQuery(
        'SELECT COUNT(*) as count FROM series_categories WHERE sourceId = ?',
        [sid],
      );
      seriesCatCount = Sqflite.firstIntValue(scRes) ?? 0;

      final lastSyncStr = await getMeta('lastSync_$sid');
      if (lastSyncStr != null) {
        lastSync = DateTime.tryParse(lastSyncStr);
      }
    } else {
      final mRes = await db.rawQuery('SELECT COUNT(*) as count FROM movies');
      movieCount = Sqflite.firstIntValue(mRes) ?? 0;

      final sRes = await db.rawQuery('SELECT COUNT(*) as count FROM series');
      seriesCount = Sqflite.firstIntValue(sRes) ?? 0;

      final vcRes =
          await db.rawQuery('SELECT COUNT(*) as count FROM vod_categories');
      vodCatCount = Sqflite.firstIntValue(vcRes) ?? 0;

      final scRes =
          await db.rawQuery('SELECT COUNT(*) as count FROM series_categories');
      seriesCatCount = Sqflite.firstIntValue(scRes) ?? 0;
    }

    return CatalogStats(
      totalMovies: movieCount,
      totalSeries: seriesCount,
      totalCategories: vodCatCount + seriesCatCount,
      lastSyncTime: lastSync,
    );
  }

  Future<List<Account>> getSavedAccounts() async {
    final db = await database;
    final maps = await db.query('sources');
    return maps.map((m) {
      final sid = m['id']?.toString() ?? '';
      return Account(
        id: sid,
        sourceId: sid,
        url: m['url']?.toString() ?? '',
        username: m['username']?.toString() ?? '',
        name: m['name']?.toString() ?? m['username']?.toString() ?? '',
        lastUsedAt: (m['lastUsedAt'] as int?) ??
            (m['last_used_at'] as int?) ??
            DateTime.now().millisecondsSinceEpoch,
      );
    }).toList();
  }

  Future<void> saveAccount(Account account) async {
    final db = await database;
    await db.insert(
      'sources',
      {
        'id': account.sourceId,
        'name': account.name.isNotEmpty ? account.name : account.username,
        'url': account.url,
        'username': account.username,
        'data': jsonEncode(account.toJson()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteAccount(dynamic sourceId) async {
    final sid = sourceId?.toString() ?? '';
    final db = await database;
    await db.delete('sources', where: 'id = ?', whereArgs: [sid]);
    await clearSourceData(sid);
  }

  /// Close database connection if needed.
  Future<void> close() async {
    final db = _database;
    if (db != null && db.isOpen) {
      await db.close();
      _database = null;
    }
  }
}
