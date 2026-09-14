import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/database/database_service.dart';
import '../../../core/models/account.dart';
import '../../../core/models/catalog_source.dart';
import '../../../core/models/catalog_stats.dart';
import '../../../core/models/category_item.dart';
import '../../../core/models/media_item.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers/backend_config_provider.dart';
import '../../../core/services/download_service.dart';
export '../../../core/providers/backend_config_provider.dart' show apiClientProvider;

/// State representing the entire catalog and source accounts.
class CatalogState {
  final List<SourceAccount> sources;
  final String? currentSourceId;
  final SourceAccount? currentAccount;
  final List<MediaItem> movies;
  final List<MediaItem> series;
  final List<CategoryItem> vodCategories;
  final List<CategoryItem> seriesCategories;
  final bool isLoading;
  final bool isSyncing;
  final String syncProgress;
  final DateTime? lastSyncTime;
  final String? error;
  final List<SourceAccount> savedAccounts;

  const CatalogState({
    this.sources = const [],
    this.currentSourceId,
    this.currentAccount,
    this.movies = const [],
    this.series = const [],
    this.vodCategories = const [],
    this.seriesCategories = const [],
    this.isLoading = false,
    this.isSyncing = false,
    this.syncProgress = '',
    this.lastSyncTime,
    this.error,
    this.savedAccounts = const [],
  });

  /// Check if an active source account is currently authenticated.
  bool get isAuthenticated => currentSourceId != null && currentSourceId!.isNotEmpty;

  /// Total count of movies in memory.
  int get moviesCount => movies.length;

  /// Total count of TV series in memory.
  int get seriesCount => series.length;

  /// Stats helper object for Settings & Storage card.
  CatalogStats get stats => CatalogStats(
        totalMovies: movies.length,
        totalSeries: series.length,
        totalCategories: vodCategories.length + seriesCategories.length,
        lastSyncTime: lastSyncTime,
      );

  /// Helper getter for UI expecting a [CatalogSource].
  CatalogSource? get currentSource => currentAccount != null
      ? CatalogSource(
          id: currentAccount!.sourceId,
          name: currentAccount!.name,
          url: currentAccount!.url,
          username: currentAccount!.username,
        )
      : null;

  CatalogState copyWith({
    List<SourceAccount>? sources,
    String? currentSourceId,
    bool clearCurrentSourceId = false,
    SourceAccount? currentAccount,
    bool clearCurrentAccount = false,
    List<MediaItem>? movies,
    List<MediaItem>? series,
    List<CategoryItem>? vodCategories,
    List<CategoryItem>? seriesCategories,
    bool? isLoading,
    bool? isSyncing,
    String? syncProgress,
    DateTime? lastSyncTime,
    bool clearLastSyncTime = false,
    String? error,
    bool clearError = false,
    List<SourceAccount>? savedAccounts,
  }) {
    return CatalogState(
      sources: sources ?? this.sources,
      currentSourceId: clearCurrentSourceId
          ? null
          : (currentSourceId ?? this.currentSourceId),
      currentAccount: clearCurrentAccount
          ? null
          : (currentAccount ?? this.currentAccount),
      movies: movies ?? this.movies,
      series: series ?? this.series,
      vodCategories: vodCategories ?? this.vodCategories,
      seriesCategories: seriesCategories ?? this.seriesCategories,
      isLoading: isLoading ?? this.isLoading,
      isSyncing: isSyncing ?? this.isSyncing,
      syncProgress: syncProgress ?? this.syncProgress,
      lastSyncTime:
          clearLastSyncTime ? null : (lastSyncTime ?? this.lastSyncTime),
      error: clearError ? null : (error ?? this.error),
      savedAccounts: savedAccounts ?? this.savedAccounts,
    );
  }
}

/// Global StateNotifier managing the catalog state, SQLite caching, and sync operations.
class CatalogNotifier extends StateNotifier<CatalogState> {
  final Ref ref;
  final DatabaseService _db = DatabaseService.instance;

  CatalogNotifier(this.ref) : super(const CatalogState()) {
    initCatalog();
  }

  ApiClient get _api => ref.read(apiClientProvider);

  /// Initializes the catalog:
  /// 1. Loads saved accounts from SharedPreferences / DB.
  /// 2. Queries backend API for sources.
  /// 3. Selects active source.
  /// 4. Loads cached data from SQLite DatabaseService.
  /// 5. Triggers auto-sync if SQLite cache is empty.
  Future<void> initCatalog() async {
    state = state.copyWith(
      isLoading: true,
      syncProgress: 'Loading accounts...',
      clearError: true,
    );

    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. Load saved accounts from SharedPreferences
      List<SourceAccount> accounts = [];
      final rawSaved = prefs.getString(ApiConstants.keySavedAccounts);
      if (rawSaved != null && rawSaved.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawSaved);
          if (decoded is List) {
            accounts = decoded
                .whereType<Map<String, dynamic>>()
                .map((j) => SourceAccount.fromJson(j))
                .toList();
          }
        } catch (_) {}
      }

      // Fallback to SQLite saved accounts if SharedPreferences is empty
      if (accounts.isEmpty) {
        accounts = await _db.getSources();
      }

      // 2. Query backend API for sources
      List<SourceAccount> apiSources = [];
      try {
        apiSources = await _api.getSources();
      } catch (_) {
        // Backend proxy might be offline or starting up; proceed with local cache
      }

      // Merge backend sources with saved accounts
      bool accountsChanged = false;
      for (final s in apiSources) {
        final alreadySaved = accounts.any(
          (a) => a.sourceId == s.sourceId || a.id == s.id,
        );
        if (!alreadySaved) {
          accounts.add(s);
          accountsChanged = true;
        }
      }

      if (accountsChanged || (rawSaved == null && accounts.isNotEmpty)) {
        await prefs.setString(
          ApiConstants.keySavedAccounts,
          jsonEncode(accounts.map((a) => a.toJson()).toList()),
        );
        await _db.saveSources(accounts);
      }

      // 3. Determine active source
      String? activeId = prefs.getString(ApiConstants.keyCurrentSourceId);
      if (activeId == null || activeId.isEmpty) {
        activeId = await _db.getMeta(ApiConstants.metaKeyCurrentSource);
      }

      SourceAccount? activeAccount;
      if (activeId != null && activeId.isNotEmpty) {
        final matches = accounts.where(
          (a) => a.sourceId == activeId || a.id == activeId,
        );
        activeAccount = matches.isNotEmpty
            ? matches.first
            : (accounts.isNotEmpty ? accounts.first : null);
      } else if (accounts.isNotEmpty) {
        activeAccount = accounts.first;
        activeId = activeAccount.sourceId;
      }

      if (activeAccount != null) {
        activeId = activeAccount.sourceId;
        await prefs.setString(ApiConstants.keyCurrentSourceId, activeId);
        await _db.setMeta(ApiConstants.metaKeyCurrentSource, activeId);
      } else {
        activeId = null;
      }

      // 4. Load cached data from SQLite DatabaseService
      List<MediaItem> cachedMovies = [];
      List<MediaItem> cachedSeries = [];
      List<CategoryItem> cachedVodCats = [];
      List<CategoryItem> cachedSeriesCats = [];
      DateTime? lastSync;

      if (activeId != null && activeId.isNotEmpty) {
        cachedMovies = await _db.getMovies(activeId);
        cachedSeries = await _db.getSeries(activeId);
        cachedVodCats = await _db.getCategories(activeId, 'vod');
        cachedSeriesCats = await _db.getCategories(activeId, 'series');
        final syncStr = await _db.getMeta('lastSync_$activeId');
        if (syncStr != null && syncStr.isNotEmpty) {
          lastSync = DateTime.tryParse(syncStr);
        }
      }

      state = state.copyWith(
        sources: apiSources.isNotEmpty ? apiSources : accounts,
        savedAccounts: accounts,
        currentSourceId: activeId,
        currentAccount: activeAccount,
        movies: cachedMovies,
        series: cachedSeries,
        vodCategories: cachedVodCats,
        seriesCategories: cachedSeriesCats,
        lastSyncTime: lastSync,
        isLoading: false,
        syncProgress: '',
      );

      // 5. Trigger auto-sync if cache is empty
      if (activeId != null &&
          activeId.isNotEmpty &&
          cachedMovies.isEmpty &&
          cachedSeries.isEmpty) {
        await syncCatalog(sourceId: activeId, forceSync: false);
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to initialize catalog: $e',
      );
    }
  }

  /// Switch active source, load SQLite cache, auto-sync if empty.
  Future<void> setCurrentSourceId(String sourceId) async {
    if (sourceId.isEmpty) return;

    state = state.copyWith(
      currentSourceId: sourceId,
      isLoading: true,
      clearError: true,
      syncProgress: 'Loading source data...',
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(ApiConstants.keyCurrentSourceId, sourceId);
      await _db.setMeta(ApiConstants.metaKeyCurrentSource, sourceId);

      SourceAccount? matched = state.savedAccounts.cast<SourceAccount?>().firstWhere(
            (a) => a?.sourceId == sourceId || a?.id == sourceId,
            orElse: () => state.sources.cast<SourceAccount?>().firstWhere(
                  (s) => s?.sourceId == sourceId || s?.id == sourceId,
                  orElse: () => SourceAccount(
                    id: sourceId,
                    sourceId: sourceId,
                    name: 'Source $sourceId',
                    url: '',
                    username: '',
                    lastUsedAt: DateTime.now().millisecondsSinceEpoch,
                  ),
                ),
          );

      final cachedMovies = await _db.getMovies(sourceId);
      final cachedSeries = await _db.getSeries(sourceId);
      final cachedVodCats = await _db.getCategories(sourceId, 'vod');
      final cachedSeriesCats = await _db.getCategories(sourceId, 'series');
      final syncStr = await _db.getMeta('lastSync_$sourceId');
      final lastSync = syncStr != null ? DateTime.tryParse(syncStr) : null;

      state = state.copyWith(
        currentAccount: matched,
        movies: cachedMovies,
        series: cachedSeries,
        vodCategories: cachedVodCats,
        seriesCategories: cachedSeriesCats,
        lastSyncTime: lastSync,
        isLoading: false,
        syncProgress: '',
      );

      if (cachedMovies.isEmpty && cachedSeries.isEmpty) {
        await syncCatalog(sourceId: sourceId, forceSync: false);
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to switch source: $e',
      );
    }
  }

  /// Downloads categories, movies, series from ApiClient, saves to DatabaseService, updates state.
  Future<void> syncCatalog({
    String? sourceId,
    bool forceSync = false,
    bool force = false,
  }) async {
    final targetId = sourceId ?? state.currentSourceId;
    if (targetId == null || targetId.isEmpty) {
      state = state.copyWith(error: 'No active source selected to sync.');
      return;
    }

    if (state.isSyncing) return;

    final shouldForce = forceSync || force;
    state = state.copyWith(
      isSyncing: true,
      clearError: true,
      syncProgress: shouldForce ? 'Syncing backend proxy...' : 'Connecting...',
    );

    try {
      if (shouldForce) {
        state = state.copyWith(syncProgress: 'Syncing backend proxy...');
        try {
          await _api.syncSource(targetId);
        } catch (_) {
          // Continue even if backend proxy sync endpoint fails
        }
      }

      state = state.copyWith(syncProgress: 'Downloading categories...');
      final vodCats = await _api
          .getVodCategories(targetId)
          .catchError((_) => <CategoryItem>[]);
      final seriesCats = await _api
          .getSeriesCategories(targetId)
          .catchError((_) => <CategoryItem>[]);

      state = state.copyWith(syncProgress: 'Downloading Movies...');
      final movies = await _api
          .getVodStreams(targetId)
          .catchError((_) => <MediaItem>[]);

      state = state.copyWith(syncProgress: 'Downloading Series...');
      final series = await _api
          .getSeries(targetId)
          .catchError((_) => <MediaItem>[]);

      state = state.copyWith(syncProgress: 'Saving to SQLite cache...');
      await _db.saveCategories(targetId, 'vod', vodCats);
      await _db.saveCategories(targetId, 'series', seriesCats);
      await _db.saveMovies(targetId, movies);
      await _db.saveSeries(targetId, series);

      final now = DateTime.now();
      await _db.setMeta('lastSync_$targetId', now.toIso8601String());

      if (state.currentSourceId == targetId) {
        state = state.copyWith(
          movies: movies,
          series: series,
          vodCategories: vodCats,
          seriesCategories: seriesCats,
          lastSyncTime: now,
          isSyncing: false,
          syncProgress: 'Completed',
        );
      } else {
        state = state.copyWith(
          isSyncing: false,
          syncProgress: 'Completed',
        );
      }
    } catch (e) {
      state = state.copyWith(
        isSyncing: false,
        syncProgress: '',
        error: 'Sync failed: $e',
      );
    }
  }

  /// Verifies backend sources, creates source if new, saves to savedAccounts and SQLite, triggers sync, updates currentSourceId.
  Future<void> loginWithXtream({
    required String url,
    required String username,
    required String password,
    String? name,
    String? proxyUrl,
  }) async {
    state = state.copyWith(
      isLoading: true,
      syncProgress: 'Connecting to backend...',
      clearError: true,
    );

    try {
      if (proxyUrl != null && proxyUrl.trim().isNotEmpty) {
        await _api.updateBaseUrl(proxyUrl.trim());
      }

      var cleanUrl = url.trim();
      if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
        cleanUrl = 'http://$cleanUrl';
      }
      cleanUrl = cleanUrl.replaceAll(RegExp(r'/+$'), '');
      final cleanUsername = username.trim();

      state = state.copyWith(syncProgress: 'Verifying backend sources...');
      final allSources = await _api.getSources();

      SourceAccount? matched;
      for (final s in allSources) {
        final sUrl = s.url.trim().replaceAll(RegExp(r'/+$'), '');
        if (sUrl.toLowerCase() == cleanUrl.toLowerCase() &&
            s.username.trim().toLowerCase() == cleanUsername.toLowerCase()) {
          matched = s;
          break;
        }
      }

      String sourceId;
      if (matched != null) {
        sourceId = matched.sourceId;
      } else {
        state = state.copyWith(syncProgress: 'Registering Xtream source...');
        final created = await _api.createSource(
          name: name?.trim().isNotEmpty == true ? name!.trim() : cleanUsername,
          url: cleanUrl,
          username: cleanUsername,
          password: password.trim(),
        );
        sourceId = created.sourceId;
      }

      final account = SourceAccount(
        id: sourceId,
        sourceId: sourceId,
        name: name?.trim().isNotEmpty == true ? name!.trim() : cleanUsername,
        url: cleanUrl,
        username: cleanUsername,
        password: password.trim(),
        lastUsedAt: DateTime.now().millisecondsSinceEpoch,
      );

      final updatedAccounts = [
        account,
        ...state.savedAccounts.where((a) => a.sourceId != sourceId),
      ];

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        ApiConstants.keySavedAccounts,
        jsonEncode(updatedAccounts.map((a) => a.toJson()).toList()),
      );
      await prefs.setString(ApiConstants.keyCurrentSourceId, sourceId);
      await _db.saveSources(updatedAccounts);
      await _db.setMeta(ApiConstants.metaKeyCurrentSource, sourceId);

      state = state.copyWith(
        savedAccounts: updatedAccounts,
        currentSourceId: sourceId,
        currentAccount: account,
        isLoading: false,
      );

      state = state.copyWith(syncProgress: 'Fetching and saving catalog...');
      await syncCatalog(sourceId: sourceId, forceSync: true);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        isSyncing: false,
        syncProgress: '',
        error: e.toString().replaceFirst('ApiException: ', '').replaceFirst('Exception: ', ''),
      );
      rethrow;
    }
  }

  /// Switch active account by sourceId or Account instance.
  Future<void> switchAccount(dynamic accountOrSourceId) async {
    final String sourceId = (accountOrSourceId is SourceAccount)
        ? accountOrSourceId.sourceId
        : (accountOrSourceId is Account)
            ? accountOrSourceId.sourceId.toString()
            : accountOrSourceId.toString();

    if (sourceId.isEmpty) return;

    final updatedAccounts = state.savedAccounts.map((acc) {
      if (acc.sourceId == sourceId) {
        return acc.copyWith(lastUsedAt: DateTime.now().millisecondsSinceEpoch);
      }
      return acc;
    }).toList();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        ApiConstants.keySavedAccounts,
        jsonEncode(updatedAccounts.map((a) => a.toJson()).toList()),
      );
      await _db.saveSources(updatedAccounts);
    } catch (_) {}

    state = state.copyWith(savedAccounts: updatedAccounts);
    await setCurrentSourceId(sourceId);
  }

  /// Clears SQLite data for source, removes from savedAccounts.
  Future<void> removeAccount(dynamic accountOrSourceId) async {
    final String sourceId = (accountOrSourceId is SourceAccount)
        ? accountOrSourceId.sourceId
        : (accountOrSourceId is Account)
            ? accountOrSourceId.sourceId.toString()
            : accountOrSourceId.toString();

    if (sourceId.isEmpty) return;

    try {
      await _db.clearSourceData(sourceId);
    } catch (_) {}

    final remaining = state.savedAccounts.where((a) => a.sourceId != sourceId).toList();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        ApiConstants.keySavedAccounts,
        jsonEncode(remaining.map((a) => a.toJson()).toList()),
      );
      await _db.saveSources(remaining);
    } catch (_) {}

    state = state.copyWith(savedAccounts: remaining);

    if (state.currentSourceId == sourceId) {
      if (remaining.isNotEmpty) {
        await setCurrentSourceId(remaining.first.sourceId);
      } else {
        await logout();
      }
    }
  }

  /// Logout: clears currentSourceId.
  Future<void> logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(ApiConstants.keyCurrentSourceId);
      await _db.setMeta(ApiConstants.metaKeyCurrentSource, '');
    } catch (_) {}

    state = state.copyWith(
      clearCurrentSourceId: true,
      clearCurrentAccount: true,
      movies: [],
      series: [],
      vodCategories: [],
      seriesCategories: [],
      clearLastSyncTime: true,
    );
  }

  /// Clears local SQLite cache for current source or all data.
  Future<void> clearCache() async {
    final targetId = state.currentSourceId;
    if (targetId != null && targetId.isNotEmpty) {
      await _db.clearSourceData(targetId);
    } else {
      await _db.clearCatalog();
    }
    state = state.copyWith(
      movies: [],
      series: [],
      vodCategories: [],
      seriesCategories: [],
      clearLastSyncTime: true,
    );
  }

  /// Helper to refresh stats.
  Future<void> refreshStats() async {}
}

/// Download service provider.
final downloadServiceProvider = ChangeNotifierProvider<DownloadService>((ref) {
  final api = ref.watch(apiClientProvider);
  return DownloadService(apiClient: api);
});

/// Main catalog StateNotifierProvider.
final catalogProvider =
    StateNotifierProvider<CatalogNotifier, CatalogState>((ref) {
  return CatalogNotifier(ref);
});

/// Convenient provider for current account.
final currentAccountProvider = Provider<SourceAccount?>((ref) {
  return ref.watch(catalogProvider).currentAccount;
});

/// Convenient provider for authentication status.
final isAuthenticatedProvider = Provider<bool>((ref) {
  final state = ref.watch(catalogProvider);
  return state.currentSourceId != null && state.currentSourceId!.isNotEmpty;
});

/// Convenient provider for movies list.
final moviesProvider = Provider<List<MediaItem>>((ref) {
  return ref.watch(catalogProvider).movies;
});

/// Convenient provider for series list.
final seriesProvider = Provider<List<MediaItem>>((ref) {
  return ref.watch(catalogProvider).series;
});
