import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vod_downloader/core/models/category_item.dart';
import 'package:vod_downloader/core/models/media_item.dart';
import 'package:vod_downloader/features/catalog/presentation/movies_screen.dart';
import 'package:vod_downloader/features/catalog/presentation/series_screen.dart';
import 'package:vod_downloader/features/catalog/presentation/widgets/media_card.dart';
import 'package:vod_downloader/features/catalog/providers/catalog_provider.dart';

/// A CatalogNotifier stand-in that skips real network/DB init (like
/// _RecordingCatalogNotifier in app_shell_and_home_screen_test.dart) and
/// seeds the state directly with a fixed in-memory fixture, so these tests
/// never touch the network, SQLite, or SharedPreferences.
class _FixtureCatalogNotifier extends CatalogNotifier {
  _FixtureCatalogNotifier(
    super.ref, {
    List<MediaItem> movies = const [],
    List<MediaItem> series = const [],
    List<CategoryItem> vodCategories = const [],
    List<CategoryItem> seriesCategories = const [],
  }) {
    state = state.copyWith(
      currentSourceId: 'src_test',
      movies: movies,
      series: series,
      vodCategories: vodCategories,
      seriesCategories: seriesCategories,
      isLoading: false,
    );
  }

  @override
  Future<void> initCatalog() async {}
}

/// Five items with deliberately mixed case names, categories, and ratings
/// (including a rating tie) so filtering, category selection, and every
/// sort mode (including its name-ascending tiebreak) can be verified
/// against a known-correct expected order.
List<MediaItem> _buildFixture({required bool isSeries}) {
  MediaItem item(String id, String name, String categoryId, String rating) {
    return MediaItem(
      streamId: id,
      name: name,
      categoryId: categoryId,
      sourceId: 'src_test',
      isSeries: isSeries,
      rating: rating,
    );
  }

  return [
    item('1', 'Zebra Movie', 'action', '7.0'),
    item('2', 'apple movie', 'action', '9.0'),
    item('3', 'Banana Film', 'comedy', '5.0'),
    item('4', 'Cherry Show', 'action', '9.0'),
    item('5', 'Date Night', 'comedy', '3.0'),
  ];
}

List<CategoryItem> _buildCategories(String type) {
  return [
    CategoryItem(categoryId: 'action', categoryName: 'Action', sourceId: 'src_test', type: type),
    CategoryItem(categoryId: 'comedy', categoryName: 'Comedy', sourceId: 'src_test', type: type),
  ];
}

List<String> _cardNames(WidgetTester tester) =>
    tester.widgetList<MediaCard>(find.byType(MediaCard)).map((c) => c.item.name).toList();

/// Widens the test surface so the screens' header/filter-bar rows (sized
/// for desktop layouts) don't overflow once the "Filtered: X of Y" text
/// appears — unrelated to the filter/sort/debounce behaviour under test.
void _useWideViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpMoviesScreen(
  WidgetTester tester, {
  required List<MediaItem> movies,
  required List<CategoryItem> categories,
}) async {
  _useWideViewport(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        catalogProvider.overrideWith(
          (ref) => _FixtureCatalogNotifier(ref, movies: movies, vodCategories: categories),
        ),
      ],
      child: const MaterialApp(home: MoviesScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpSeriesScreen(
  WidgetTester tester, {
  required List<MediaItem> series,
  required List<CategoryItem> categories,
}) async {
  _useWideViewport(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        catalogProvider.overrideWith(
          (ref) => _FixtureCatalogNotifier(ref, series: series, seriesCategories: categories),
        ),
      ],
      child: const MaterialApp(home: SeriesScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('MoviesScreen filter/sort/perf', () {
    testWidgets('renders items sorted by name ascending by default', (tester) async {
      await _pumpMoviesScreen(
        tester,
        movies: _buildFixture(isSeries: false),
        categories: _buildCategories('vod'),
      );

      expect(_cardNames(tester), [
        'apple movie',
        'Banana Film',
        'Cherry Show',
        'Date Night',
        'Zebra Movie',
      ]);
    });

    testWidgets('filters by category via the category dropdown', (tester) async {
      await _pumpMoviesScreen(
        tester,
        movies: _buildFixture(isSeries: false),
        categories: _buildCategories('vod'),
      );

      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Action (3)').last);
      await tester.pumpAndSettle();

      // "action" contains apple movie, Cherry Show, Zebra Movie (name-asc).
      expect(_cardNames(tester), ['apple movie', 'Cherry Show', 'Zebra Movie']);
    });

    testWidgets('filters by search query case-insensitively', (tester) async {
      await _pumpMoviesScreen(
        tester,
        movies: _buildFixture(isSeries: false),
        categories: _buildCategories('vod'),
      );

      await tester.enterText(find.byType(TextField), 'MoVie');
      await tester.pump(const Duration(milliseconds: 300));

      // Only titles containing "movie" case-insensitively: apple movie, Zebra Movie.
      expect(_cardNames(tester), ['apple movie', 'Zebra Movie']);
    });

    testWidgets('sorts by name-desc, rating-desc, and rating-asc correctly', (tester) async {
      await _pumpMoviesScreen(
        tester,
        movies: _buildFixture(isSeries: false),
        categories: _buildCategories('vod'),
      );

      Future<void> selectSort(String label) async {
        await tester.tap(find.byType(DropdownButton<MovieSortOption>));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
      }

      await selectSort('Name (Z-A)');
      expect(_cardNames(tester), [
        'Zebra Movie',
        'Date Night',
        'Cherry Show',
        'Banana Film',
        'apple movie',
      ]);

      await selectSort('Rating (High to Low)');
      // 9.0 tie between apple movie / Cherry Show broken by name-asc.
      expect(_cardNames(tester), [
        'apple movie',
        'Cherry Show',
        'Zebra Movie',
        'Banana Film',
        'Date Night',
      ]);

      await selectSort('Rating (Low to High)');
      expect(_cardNames(tester), [
        'Date Night',
        'Banana Film',
        'Zebra Movie',
        'apple movie',
        'Cherry Show',
      ]);
    });

    testWidgets('debounces rapid search input into a single filter pass', (tester) async {
      await _pumpMoviesScreen(
        tester,
        movies: _buildFixture(isSeries: false),
        categories: _buildCategories('vod'),
      );

      final dynamic state = tester.state(find.byType(MoviesScreen));
      expect(state.filterPassCount, 1); // initial build computes once.

      // Simulate a burst of keystrokes, each well under the 250ms debounce
      // window apart, so only the final value should ever be recomputed.
      for (final text in ['a', 'ap', 'app', 'appl', 'apple']) {
        await tester.enterText(find.byType(TextField), text);
        await tester.pump(const Duration(milliseconds: 50));
      }
      // No recompute yet: the debounce timer keeps getting reset.
      expect(state.filterPassCount, 1);

      // Let the debounce timer from the last keystroke fire.
      await tester.pump(const Duration(milliseconds: 260));

      expect(state.filterPassCount, 2);
      expect(_cardNames(tester), ['apple movie']);
    });

    testWidgets('disposing while a debounce timer is pending does not throw', (tester) async {
      await _pumpMoviesScreen(
        tester,
        movies: _buildFixture(isSeries: false),
        categories: _buildCategories('vod'),
      );

      await tester.enterText(find.byType(TextField), 'pending query');
      await tester.pump(const Duration(milliseconds: 50)); // timer scheduled, not fired

      // Replace the widget tree, disposing MoviesScreen (and its State,
      // and its pending Timer) before the debounce fires.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

      // Advance past the debounce window; if dispose failed to cancel the
      // timer, its callback would call setState on an unmounted State.
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
    });
  });

  group('SeriesScreen filter/sort/perf', () {
    testWidgets('renders items sorted by name ascending by default', (tester) async {
      await _pumpSeriesScreen(
        tester,
        series: _buildFixture(isSeries: true),
        categories: _buildCategories('series'),
      );

      expect(_cardNames(tester), [
        'apple movie',
        'Banana Film',
        'Cherry Show',
        'Date Night',
        'Zebra Movie',
      ]);
    });

    testWidgets('filters by category via the category dropdown', (tester) async {
      await _pumpSeriesScreen(
        tester,
        series: _buildFixture(isSeries: true),
        categories: _buildCategories('series'),
      );

      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Action').last);
      await tester.pumpAndSettle();

      expect(_cardNames(tester), ['apple movie', 'Cherry Show', 'Zebra Movie']);
    });

    testWidgets('filters by search query case-insensitively', (tester) async {
      await _pumpSeriesScreen(
        tester,
        series: _buildFixture(isSeries: true),
        categories: _buildCategories('series'),
      );

      await tester.enterText(find.byType(TextField), 'MoVie');
      await tester.pump(const Duration(milliseconds: 300));

      expect(_cardNames(tester), ['apple movie', 'Zebra Movie']);
    });

    testWidgets('sorts by name-desc, rating-desc, and rating-asc correctly', (tester) async {
      await _pumpSeriesScreen(
        tester,
        series: _buildFixture(isSeries: true),
        categories: _buildCategories('series'),
      );

      Future<void> selectSort(String label) async {
        await tester.tap(find.byType(DropdownButton<SeriesSortOption>));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
      }

      await selectSort('Name (Z-A)');
      expect(_cardNames(tester), [
        'Zebra Movie',
        'Date Night',
        'Cherry Show',
        'Banana Film',
        'apple movie',
      ]);

      await selectSort('Rating (High to Low)');
      expect(_cardNames(tester), [
        'apple movie',
        'Cherry Show',
        'Zebra Movie',
        'Banana Film',
        'Date Night',
      ]);

      await selectSort('Rating (Low to High)');
      expect(_cardNames(tester), [
        'Date Night',
        'Banana Film',
        'Zebra Movie',
        'apple movie',
        'Cherry Show',
      ]);
    });

    testWidgets('debounces rapid search input into a single filter pass', (tester) async {
      await _pumpSeriesScreen(
        tester,
        series: _buildFixture(isSeries: true),
        categories: _buildCategories('series'),
      );

      final dynamic state = tester.state(find.byType(SeriesScreen));
      expect(state.filterPassCount, 1);

      for (final text in ['a', 'ap', 'app', 'appl', 'apple']) {
        await tester.enterText(find.byType(TextField), text);
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(state.filterPassCount, 1);

      await tester.pump(const Duration(milliseconds: 260));

      expect(state.filterPassCount, 2);
      expect(_cardNames(tester), ['apple movie']);
    });

    testWidgets('disposing while a debounce timer is pending does not throw', (tester) async {
      await _pumpSeriesScreen(
        tester,
        series: _buildFixture(isSeries: true),
        categories: _buildCategories('series'),
      );

      await tester.enterText(find.byType(TextField), 'pending query');
      await tester.pump(const Duration(milliseconds: 50));

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
    });
  });
}
