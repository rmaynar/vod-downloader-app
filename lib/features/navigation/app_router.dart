import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/presentation/login_screen.dart';
import '../catalog/presentation/home_screen.dart';
import '../catalog/presentation/movies_screen.dart';
import '../catalog/presentation/series_screen.dart';
import '../catalog/providers/catalog_provider.dart';
import '../downloads/presentation/downloads_screen.dart';
import '../settings/presentation/settings_screen.dart';
import 'app_shell.dart';

/// Listenable that notifies GoRouter when catalog auth state changes.
class _RouterListenable extends ChangeNotifier {
  final Ref _ref;

  _RouterListenable(this._ref) {
    _ref.listen<CatalogState>(
      catalogProvider,
      (previous, next) {
        if (previous?.currentSourceId != next.currentSourceId ||
            previous?.isLoading != next.isLoading) {
          notifyListeners();
        }
      },
    );
  }
}

final routerListenableProvider = Provider<_RouterListenable>((ref) {
  return _RouterListenable(ref);
});

/// Riverpod Provider providing the application's GoRouter instance.
final appRouterProvider = Provider<GoRouter>((ref) {
  final listenable = ref.watch(routerListenableProvider);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: listenable,
    redirect: (context, state) {
      final catalogState = ref.read(catalogProvider);
      final isAuthenticated = catalogState.currentSourceId != null &&
          catalogState.currentSourceId!.isNotEmpty;
      final isLoggingIn = state.matchedLocation == '/login';

      // If not authenticated and not on /login, redirect to /login
      if (!isAuthenticated && !isLoggingIn) {
        return '/login';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) {
          final mode = state.uri.queryParameters['mode'];
          return LoginScreen(initialMode: mode);
        },
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: '/movies',
            builder: (context, state) => const MoviesScreen(),
          ),
          GoRoute(
            path: '/series',
            builder: (context, state) => const SeriesScreen(),
          ),
          GoRoute(
            path: '/downloads',
            builder: (context, state) => const DownloadsScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreen(),
          ),
        ],
      ),
    ],
  );
});

/// Fallback global GoRouter instance for non-Riverpod access if needed.
GoRouter? _globalAppRouter;

GoRouter get appRouter {
  return _globalAppRouter ??= GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) {
          final mode = state.uri.queryParameters['mode'];
          return LoginScreen(initialMode: mode);
        },
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: '/movies',
            builder: (context, state) => const MoviesScreen(),
          ),
          GoRoute(
            path: '/series',
            builder: (context, state) => const SeriesScreen(),
          ),
          GoRoute(
            path: '/downloads',
            builder: (context, state) => const DownloadsScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreen(),
          ),
        ],
      ),
    ],
  );
}
