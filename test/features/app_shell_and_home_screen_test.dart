import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vod_downloader/core/models/source_account.dart';
import 'package:vod_downloader/features/catalog/presentation/home_screen.dart';
import 'package:vod_downloader/features/catalog/providers/catalog_provider.dart';
import 'package:vod_downloader/features/navigation/app_router.dart';
import 'package:vod_downloader/features/navigation/app_shell.dart';

/// A CatalogNotifier stand-in that skips real network/DB init and records
/// calls made to [syncCatalog], so tests can drive an "authenticated" UI
/// state without touching the network or SQLite.
class _RecordingCatalogNotifier extends CatalogNotifier {
  String? lastSourceIdArg;
  bool? lastForceSyncArg;
  int syncCallCount = 0;

  _RecordingCatalogNotifier(super.ref) {
    state = state.copyWith(
      currentSourceId: 'src_1',
      currentAccount: const SourceAccount(
        id: 'src_1',
        sourceId: 'src_1',
        name: 'Test User',
        url: 'http://test.local',
        username: 'tester',
      ),
    );
  }

  @override
  Future<void> initCatalog() async {}

  @override
  Future<void> syncCatalog({
    String? sourceId,
    bool forceSync = false,
    bool force = false,
  }) async {
    syncCallCount++;
    lastSourceIdArg = sourceId;
    lastForceSyncArg = forceSync;
  }
}

void main() {
  group('AppShell header layout', () {
    testWidgets('does not overflow on a narrow phone width', (tester) async {
      // Matches the logical width of a Pixel-class emulator (1280 physical /
      // 3.0 density) where the header previously overflowed by 34px because
      // the "VOD Downloader" wordmark was never hidden on narrow screens.
      tester.view.physicalSize = const Size(1280, 2856);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) =>
                const AppShell(child: SizedBox.shrink()),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            catalogProvider.overrideWith(
              (ref) => _RecordingCatalogNotifier(ref),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('displays the new icon and title on wider screens without overflow',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) =>
                const AppShell(child: SizedBox.shrink()),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            catalogProvider.overrideWith(
              (ref) => _RecordingCatalogNotifier(ref),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      // Verify the new icon asset is rendered
      final iconFinder = find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'assets/vod-download-icon.jpeg',
      );
      expect(iconFinder, findsOneWidget);

      // Verify the VOD Downloader title is displayed alongside the icon
      expect(find.text('VOD Downloader'), findsOneWidget);
    });

    testWidgets('displays the new icon on narrow screens without overflow',
        (tester) async {
      tester.view.physicalSize = const Size(430, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) =>
                const AppShell(child: SizedBox.shrink()),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            catalogProvider.overrideWith(
              (ref) => _RecordingCatalogNotifier(ref),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      // Icon is rendered on narrow screens
      final iconFinder = find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'assets/vod-download-icon.jpeg',
      );
      expect(iconFinder, findsOneWidget);
    });
  });

  group('HomeScreen force-sync button', () {
    testWidgets('invokes syncCatalog with only named args (forceSync: true)',
        (tester) async {
      late _RecordingCatalogNotifier fakeNotifier;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            catalogProvider.overrideWith((ref) {
              fakeNotifier = _RecordingCatalogNotifier(ref);
              return fakeNotifier;
            }),
          ],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Force refresh catalog'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(fakeNotifier.syncCallCount, 1);
      expect(fakeNotifier.lastForceSyncArg, isTrue);
      // sourceId is intentionally omitted by the caller so syncCatalog
      // falls back to the currently active source.
      expect(fakeNotifier.lastSourceIdArg, isNull);
    });
  });

  group('Account switcher navigation and router', () {
    testWidgets('tapping "Add Another Account" opens /login?mode=add',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      String? lastNavigatedPath;

      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/login',
            builder: (context, state) {
              lastNavigatedPath = state.uri.toString();
              return Scaffold(
                body: Text('Login Screen: ${state.uri.queryParameters['mode']}'),
              );
            },
          ),
          ShellRoute(
            builder: (context, state, child) => AppShell(child: child),
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const Text('Home Screen'),
              ),
            ],
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            catalogProvider.overrideWith(
              (ref) => _RecordingCatalogNotifier(ref),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      // Open the account switcher dropdown
      await tester.tap(find.text('Test User'));
      await tester.pumpAndSettle();

      // Verify bottom sheet is open with both buttons
      expect(find.text('Add Another Account'), findsOneWidget);
      expect(find.text('Manage All Accounts'), findsOneWidget);

      // Tap 'Add Another Account'
      await tester.tap(find.text('Add Another Account'));
      await tester.pumpAndSettle();

      expect(lastNavigatedPath, '/login?mode=add');
      expect(find.text('Login Screen: add'), findsOneWidget);
    });

    testWidgets('tapping "Manage All Accounts" opens /login',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      String? lastNavigatedPath;

      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/login',
            builder: (context, state) {
              lastNavigatedPath = state.uri.toString();
              return Scaffold(
                body: Text('Login Screen: ${state.uri.queryParameters['mode']}'),
              );
            },
          ),
          ShellRoute(
            builder: (context, state, child) => AppShell(child: child),
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const Text('Home Screen'),
              ),
            ],
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            catalogProvider.overrideWith(
              (ref) => _RecordingCatalogNotifier(ref),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      // Open the account switcher dropdown
      await tester.tap(find.text('Test User'));
      await tester.pumpAndSettle();

      // Tap 'Manage All Accounts'
      await tester.tap(find.text('Manage All Accounts'));
      await tester.pumpAndSettle();

      expect(lastNavigatedPath, '/login');
      expect(find.text('Login Screen: null'), findsOneWidget);
    });

    testWidgets(
        'appRouterProvider allows authenticated access to /login and /login?mode=add',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [
          catalogProvider.overrideWith(
            (ref) => _RecordingCatalogNotifier(ref),
          ),
        ],
      );
      addTearDown(container.dispose);

      final router = container.read(appRouterProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      // Authenticated user navigating to /login
      router.go('/login');
      await tester.pumpAndSettle();
      expect(router.routerDelegate.currentConfiguration.uri.path, '/login');

      // Authenticated user navigating to /login?mode=add
      router.go('/login?mode=add');
      await tester.pumpAndSettle();
      expect(router.routerDelegate.currentConfiguration.uri.path, '/login');
      expect(
        router.routerDelegate.currentConfiguration.uri.queryParameters['mode'],
        'add',
      );
    });
  });
}
