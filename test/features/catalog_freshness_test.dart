import 'package:flutter_test/flutter_test.dart';
import 'package:vod_downloader/core/models/media_item.dart';
import 'package:vod_downloader/features/catalog/providers/catalog_provider.dart';

void main() {
  group('isCatalogStale', () {
    test('a catalog that has never synced is stale', () {
      expect(CatalogNotifier.isCatalogStale(null), isTrue);
    });

    test('a catalog synced just now is fresh', () {
      expect(CatalogNotifier.isCatalogStale(DateTime.now()), isFalse);
    });

    test('a catalog synced 11h ago is still fresh', () {
      final elevenHoursAgo =
          DateTime.now().subtract(const Duration(hours: 11));
      expect(CatalogNotifier.isCatalogStale(elevenHoursAgo), isFalse);
    });

    test('a catalog synced 12h ago is stale', () {
      // Exactly at the boundary, plus a second to avoid a flake from the
      // clock ticking between the subtraction and the comparison.
      final twelveHoursAgo =
          DateTime.now().subtract(const Duration(hours: 12, seconds: 1));
      expect(CatalogNotifier.isCatalogStale(twelveHoursAgo), isTrue);
    });

    test('a catalog synced days ago is stale', () {
      final longAgo = DateTime.now().subtract(const Duration(days: 3));
      expect(CatalogNotifier.isCatalogStale(longAgo), isTrue);
    });

    test('the staleness window is 12 hours', () {
      expect(CatalogNotifier.catalogStaleAfter, const Duration(hours: 12));
    });
  });

  group('CatalogState.isInitialSync', () {
    const movie = MediaItem(streamId: '1', name: 'A Movie', sourceId: 's1');

    test('is true while syncing with nothing cached', () {
      const state = CatalogState(isSyncing: true);
      expect(state.isInitialSync, isTrue);
    });

    test('is false when syncing over an existing catalog', () {
      // The whole point of the background refresh: a stale-cache re-sync must
      // NOT put the catalog screens into their blocking loading state.
      const state = CatalogState(isSyncing: true, movies: [movie]);
      expect(state.isInitialSync, isFalse);
    });

    test('series-only cache also counts as having content', () {
      const state = CatalogState(isSyncing: true, series: [movie]);
      expect(state.isInitialSync, isFalse);
    });

    test('is false when not syncing at all, even with an empty catalog', () {
      const state = CatalogState(isSyncing: false);
      expect(state.isInitialSync, isFalse);
    });
  });
}
