import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vod_downloader/core/models/account.dart';
import 'package:vod_downloader/features/auth/presentation/login_screen.dart';
import 'package:vod_downloader/features/catalog/providers/catalog_provider.dart';

class _FakeCatalogNotifier extends CatalogNotifier {
  _FakeCatalogNotifier(
    super.ref, {
    List<Account> initialAccounts = const [],
    String? initialSourceId,
  }) {
    state = state.copyWith(
      savedAccounts: initialAccounts,
      currentSourceId: initialSourceId,
    );
  }

  @override
  Future<void> initCatalog() async {}
}

void main() {
  const sampleAccount = Account(
    id: 'src-1',
    sourceId: 'src-1',
    name: 'Primary Account',
    url: 'http://example.com',
    username: 'user1',
    password: 'pw1',
  );

  group('LoginScreen account management & navigation', () {
    testWidgets('shows Add Account tab when initialMode is "add"',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            catalogProvider.overrideWith(
              (ref) => _FakeCatalogNotifier(
                ref,
                initialAccounts: [sampleAccount],
                initialSourceId: 'src-1',
              ),
            ),
          ],
          child: const MaterialApp(
            home: LoginScreen(initialMode: 'add'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Form fields are present in Add Account tab
      expect(find.text('SERVER URL'), findsOneWidget);
      expect(find.text('USERNAME'), findsOneWidget);
      expect(find.text('PASSWORD'), findsOneWidget);
      expect(find.text('Save & Cache Catalog'), findsOneWidget);
    });

    testWidgets(
        'shows Saved Accounts tab by default when accounts exist and initialMode is null',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            catalogProvider.overrideWith(
              (ref) => _FakeCatalogNotifier(
                ref,
                initialAccounts: [sampleAccount],
                initialSourceId: 'src-1',
              ),
            ),
          ],
          child: const MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Primary Account'), findsOneWidget);
      expect(find.text('Saved Accounts (1)'), findsOneWidget);
    });

    testWidgets('shows back button when user is authenticated and tapping it pops',
        (tester) async {
      final router = GoRouter(
        initialLocation: '/movies',
        routes: [
          GoRoute(
            path: '/movies',
            builder: (context, state) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => context.push('/login'),
                  child: const Text('Go to Login'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/login',
            builder: (context, state) => const LoginScreen(),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            catalogProvider.overrideWith(
              (ref) => _FakeCatalogNotifier(
                ref,
                initialAccounts: [sampleAccount],
                initialSourceId: 'src-1',
              ),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to /login
      await tester.tap(find.text('Go to Login'));
      await tester.pumpAndSettle();

      // Back button is present
      final backButton = find.byTooltip('Back');
      expect(backButton, findsOneWidget);

      // Tap back button
      await tester.tap(backButton);
      await tester.pumpAndSettle();

      // Should be back on /movies
      expect(find.text('Go to Login'), findsOneWidget);
    });

    testWidgets(
        'does not show back button when unauthenticated and cannot pop',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            catalogProvider.overrideWith(
              (ref) => _FakeCatalogNotifier(
                ref,
                initialAccounts: [],
                initialSourceId: null,
              ),
            ),
          ],
          child: const MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Back'), findsNothing);
    });
  });
}
