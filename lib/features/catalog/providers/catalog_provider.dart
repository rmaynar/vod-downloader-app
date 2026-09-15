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
import '../../../core/models/xtream_source.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/xtream_client.dart';
import '../../../core/providers/backend_config_provider.dart';
import '../../../core/providers/xtream_provider.dart';
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

  /// Initializes the catalog:
  /// 1. Loads saved accounts from SharedPreferences, falling back to the
  ///    `sources` table in SQLite.
  /// 2. Selects active source.
  /// 3. Loads cached data from SQLite DatabaseService.
  /// 4. Triggers auto-sync if SQLite cache is empty.
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

      // Persist the DB-sourced fallback back into SharedPreferences so
      // subsequent launches read from the faster cache.
      if (rawSaved == null && accounts.isNotEmpty) {
        await prefs.setString(
          ApiConstants.keySavedAccounts,
          jsonEncode(accounts.map((a) => a.toJson()).toList()),
        );
        await _db.saveSources(accounts);
      }

      // 2. Determine active source
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

      // 3. Load cached data from SQLite DatabaseService
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
        sources: accounts,
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

      // 4. Trigger auto-sync if cache is empty
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

  /// Finds the [SourceAccount] (with credentials) for [sourceId], checking
  /// the currently active account first, then saved accounts / sources.
  SourceAccount? _findAccountForSource(String sourceId) {
    if (state.currentAccount != null &&
        (state.currentAccount!.sourceId == sourceId ||
            state.currentAccount!.id == sourceId)) {
      return state.currentAccount;
    }
    final saved = state.savedAccounts.where(
      (a) => a.sourceId == sourceId || a.id == sourceId,
    );
    if (saved.isNotEmpty) return saved.first;
    final sources = state.sources.where(
      (a) => a.sourceId == sourceId || a.id == sourceId,
    );
    return sources.isNotEmpty ? sources.first : null;
  }

  /// Renders an error thrown while talking to the Xtream provider into a
  /// user-facing message. [XtreamException.message] is already
  /// human-readable (auth failure, inactive account, network/timeout); any
  /// other exception falls back to its string form.
  String _describeSyncError(Object error) {
    if (error is XtreamException) return error.message;
    return error.toString();
  }

  /// Downloads categories, movies, series directly from the Xtream provider
  /// via [XtreamClient], saves them to DatabaseService, and updates state.
  ///
  /// `forceSync` no longer triggers a backend proxy re-sync (there is no
  /// backend proxy); it just means "refetch from the provider, ignore the
  /// SQLite cache".
  ///
  /// Errors are never swallowed into an empty catalog: if every fetch fails,
  /// `state.error` is set and the previously cached data (in SQLite and in
  /// state) is left untouched. If only some fetches fail, the ones that
  /// succeeded are still saved/applied and the failure is surfaced via
  /// `state.error` rather than silently wiping the failed slice's cache.
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

    final account = _findAccountForSource(targetId);
    if (account == null) {
      state = state.copyWith(
        error: 'No saved account found for this source. Please sign in again.',
      );
      return;
    }
    if (account.password == null || account.password!.isEmpty) {
      state = state.copyWith(
        error:
            '"${account.displayName}" was saved before a password was required '
            '(from an older sign-in) and can no longer authenticate. Please '
            'remove it and sign in again.',
      );
      return;
    }

    final client = XtreamClient(
      baseUrl: account.url,
      username: account.username,
      password: account.password!,
    );

    state = state.copyWith(
      isSyncing: true,
      clearError: true,
      syncProgress: 'Connecting...',
    );

    try {
      state = state.copyWith(syncProgress: 'Downloading categories...');
      List<CategoryItem>? vodCats;
      List<CategoryItem>? seriesCats;
      String? vodCatsErr;
      String? seriesCatsErr;
      try {
        vodCats = await client.getVodCategories(targetId);
      } catch (e) {
        vodCatsErr = _describeSyncError(e);
      }
      try {
        seriesCats = await client.getSeriesCategories(targetId);
      } catch (e) {
        seriesCatsErr = _describeSyncError(e);
      }

      state = state.copyWith(syncProgress: 'Downloading Movies...');
      List<MediaItem>? movies;
      String? moviesErr;
      try {
        movies = await client.getVodStreams(targetId);
      } catch (e) {
        moviesErr = _describeSyncError(e);
      }

      state = state.copyWith(syncProgress: 'Downloading Series...');
      List<MediaItem>? series;
      String? seriesErr;
      try {
        series = await client.getSeries(targetId);
      } catch (e) {
        seriesErr = _describeSyncError(e);
      }

      final errors = [vodCatsErr, seriesCatsErr, moviesErr, seriesErr]
          .whereType<String>()
          .toSet() // de-dupe identical messages (e.g. one auth failure
          // usually breaks all four calls the same way)
          .toList();

      // Total failure: nothing came back from the provider at all. Do not
      // touch the SQLite cache or state's catalog data — surface the error
      // and leave whatever was previously cached/displayed alone.
      if (vodCats == null && seriesCats == null && movies == null && series == null) {
        state = state.copyWith(
          isSyncing: false,
          syncProgress: '',
          error: errors.isNotEmpty
              ? 'Sync failed: ${errors.join(' | ')}'
              : 'Sync failed: unknown error',
        );
        return;
      }

      state = state.copyWith(syncProgress: 'Saving to SQLite cache...');
      if (vodCats != null) await _db.saveCategories(targetId, 'vod', vodCats);
      if (seriesCats != null) {
        await _db.saveCategories(targetId, 'series', seriesCats);
      }
      if (movies != null) await _db.saveMovies(targetId, movies);
      if (series != null) await _db.saveSeries(targetId, series);

      final now = DateTime.now();
      await _db.setMeta('lastSync_$targetId', now.toIso8601String());

      final combinedError = errors.isNotEmpty
          ? 'Some catalog data failed to sync: ${errors.join(' | ')}'
          : null;
      final progressLabel = combinedError != null ? 'Completed with errors' : 'Completed';

      if (state.currentSourceId == targetId) {
        state = state.copyWith(
          movies: movies ?? state.movies,
          series: series ?? state.series,
          vodCategories: vodCats ?? state.vodCategories,
          seriesCategories: seriesCats ?? state.seriesCategories,
          lastSyncTime: now,
          isSyncing: false,
          syncProgress: progressLabel,
          error: combinedError,
        );
      } else {
        state = state.copyWith(
          isSyncing: false,
          syncProgress: progressLabel,
          error: combinedError,
        );
      }
    } catch (e) {
      state = state.copyWith(
        isSyncing: false,
        syncProgress: '',
        error: 'Sync failed: ${_describeSyncError(e)}',
      );
    }
  }

  /// Authenticates directly against the Xtream Codes provider, derives a
  /// stable local source id, persists a [SourceAccount] (including its
  /// password — required to build stream URLs and to re-authenticate later),
  /// and triggers an initial catalog sync.
  ///
  /// [proxyUrl] is accepted for source-compatibility with older call sites
  /// but is a no-op: there is no backend proxy left to point at.
  Future<void> loginWithXtream({
    required String url,
    required String username,
    required String password,
    String? name,
    String? proxyUrl,
  }) async {
    state = state.copyWith(
      isLoading: true,
      syncProgress: 'Connecting to Xtream server...',
      clearError: true,
    );

    try {
      final cleanUrl = normalizeServerUrl(url);
      final cleanUsername = username.trim();
      final cleanPassword = password.trim();

      // This is now the only credential check: a direct authenticate()
      // call against the provider's player_api.php. It throws
      // XtreamException on bad credentials, an inactive/expired account, or
      // a network/connection failure — the catch block below surfaces
      // whichever it was.
      final client = XtreamClient(
        baseUrl: cleanUrl,
        username: cleanUsername,
        password: cleanPassword,
      );

      state = state.copyWith(syncProgress: 'Verifying credentials...');
      await client.authenticate();

      final sourceId = deriveSourceId(cleanUrl, cleanUsername);

      final account = SourceAccount(
        id: sourceId,
        sourceId: sourceId,
        name: name?.trim().isNotEmpty == true ? name!.trim() : cleanUsername,
        url: cleanUrl,
        username: cleanUsername,
        password: cleanPassword,
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
        sources: updatedAccounts,
        savedAccounts: updatedAccounts,
        currentSourceId: sourceId,
        currentAccount: account,
        isLoading: false,
      );

      state = state.copyWith(syncProgress: 'Fetching and saving catalog...');
      await syncCatalog(sourceId: sourceId, forceSync: true);
    } on XtreamException catch (e) {
      state = state.copyWith(
        isLoading: false,
        isSyncing: false,
        syncProgress: '',
        error: e.message,
      );
      rethrow;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        isSyncing: false,
        syncProgress: '',
        error: e.toString().replaceFirst('Exception: ', ''),
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
  return DownloadService(client: ref.watch(xtreamClientProvider));
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
