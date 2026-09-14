import 'dart:convert';
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
  static const int _dbVersion = 1;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDb(_dbName);
    return _database!;
  }

  Future<Database> _initDb(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _createDb,
    );
  }

  Future<void> _createDb(Database db, int version) async {
    // Movies table
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

    // Series table
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
  }

  /// Save movies list for a given source. Replaces existing cached movies for this source.
  Future<void> saveMovies(String sourceId, List<MediaItem> movies) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'movies',
        where: 'sourceId = ?',
        whereArgs: [sourceId],
      );

      final batch = txn.batch();
      for (final movie in movies) {
        batch.insert(
          'movies',
          movie.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
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
  Future<void> saveSeries(String sourceId, List<MediaItem> seriesList) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'series',
        where: 'sourceId = ?',
        whereArgs: [sourceId],
      );

      final batch = txn.batch();
      for (final s in seriesList) {
        batch.insert(
          'series',
          s.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
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
