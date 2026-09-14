import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/database/database_service.dart';
import 'core/theme/app_theme.dart';
import 'features/navigation/app_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SQLite DatabaseService
  await DatabaseService.instance.database;

  // Initialize SharedPreferences
  await SharedPreferences.getInstance();

  runApp(
    const ProviderScope(
      child: VodCatalogApp(),
    ),
  );
}

class VodCatalogApp extends ConsumerWidget {
  const VodCatalogApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'VOD Downloader',
      theme: AppTheme.darkTheme,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
