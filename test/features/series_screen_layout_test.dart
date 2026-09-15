import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vod_downloader/core/models/category_item.dart';
import 'package:vod_downloader/core/models/media_item.dart';
import 'package:vod_downloader/features/catalog/presentation/series_screen.dart';
import 'package:vod_downloader/features/catalog/providers/catalog_provider.dart';

/// A CatalogNotifier stand-in that skips real network/DB init (like
/// _RecordingCatalogNotifier in app_shell_and_home_screen_test.dart) and
/// seeds the state directly with a fixed in-memory fixture, so these tests
/// never touch the network, SQLite, or SharedPreferences.
class _FixtureCatalogNotifier extends CatalogNotifier {
  _FixtureCatalogNotifier(
    super.ref, {
    required List<MediaItem> series,
    required List<CategoryItem> seriesCategories,
  }) {
    state = state.copyWith(
      currentSourceId: 'src_test',
      series: series,
      seriesCategories: seriesCategories,
      isLoading: false,
    );
  }

  @override
  Future<void> initCatalog() async {}
}

/// A handful of series, one with a pathologically long title, so the
/// header row is exercised the way a real 11k+ item catalog would.
List<MediaItem> _buildFixture(int count) {
  return List.generate(count, (i) {
    final name = i == 0
        ? 'An Extraordinarily Long Television Series Title That Goes On And On '
            'And Really Should Never Fit On One Line No Matter The Screen Width'
        : 'Series ${i + 1}';
    return MediaItem(
      streamId: '$i',
      name: name,
      categoryId: 'action',
      sourceId: 'src_test',
      isSeries: true,
      rating: '7.0',
    );
  });
}

Future<void> _pumpSeriesScreenAt(
  WidgetTester tester, {
  required Size physicalSize,
  required double devicePixelRatio,
  required List<MediaItem> series,
}) async {
  tester.view.physicalSize = physicalSize;
  tester.view.devicePixelRatio = devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        catalogProvider.overrideWith(
          (ref) => _FixtureCatalogNotifier(
            ref,
            series: series,
            seriesCategories: const [
              CategoryItem(
                categoryId: 'action',
                categoryName: 'Action',
                sourceId: 'src_test',
                type: 'series',
              ),
            ],
          ),
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

  group('SeriesScreen header layout', () {
    testWidgets(
      'does not overflow at phone width once "Filtered: X of Y" renders',
      (tester) async {
        // Matches the logical width of a Pixel-class emulator (1280 physical
        // / 3.0 density) used elsewhere in this suite for phone-width
        // overflow regressions (see app_shell_and_home_screen_test.dart).
        await _pumpSeriesScreenAt(
          tester,
          physicalSize: const Size(1280, 2856),
          devicePixelRatio: 3.0,
          series: _buildFixture(1200),
        );

        // Trigger the "Filtered: X of Y" pill by entering a search query
        // (debounced, so let the timer fire).
        await tester.enterText(find.byType(TextField), 'series');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        expect(find.textContaining('Filtered:'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'does not overflow at the rail breakpoint (>=800dp) once filtered',
      (tester) async {
        await _pumpSeriesScreenAt(
          tester,
          physicalSize: const Size(2400, 2856),
          devicePixelRatio: 3.0, // 800 x 952 logical
          series: _buildFixture(1200),
        );

        await tester.enterText(find.byType(TextField), 'series');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        expect(find.textContaining('Filtered:'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
