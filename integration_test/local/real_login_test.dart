import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nodecast_catalog_flutter/main.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

/// Diagnostic test for real-account login issues, safe to commit: it holds
/// no credentials itself. Real values come from integration_test/local/
/// secrets.properties (gitignored, personal-machine-only - copy
/// secrets.template in that same directory to secrets.properties and fill
/// in your own account), loaded at build time via:
///
///   flutter test integration_test/local/real_login_test.dart -d DEVICE_ID \
///     --dart-define-from-file=integration_test/local/secrets.properties
///
/// integration_test runs this code on the device itself, so it cannot read
/// the host's secrets.properties as a plain file at runtime - dart-define
/// values are baked in at build time instead, which is what makes this work.
const String _serverUrl = String.fromEnvironment('xtream_serverUrl');
const String _username = String.fromEnvironment('xtream_username');
const String _password = String.fromEnvironment('xtream_password');
const String _label = String.fromEnvironment('xtream_label');

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 30),
  String? description,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      final visibleText = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .whereType<String>()
          .where((s) => s.trim().isNotEmpty)
          .toSet()
          .join(' | ');
      fail(
        'Timed out waiting for: ${description ?? condition}\n'
        'Currently visible text: $visibleText',
      );
    }
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reproduce real-credential login failure', (tester) async {
    if (_serverUrl.isEmpty || _username.isEmpty || _password.isEmpty) {
      fail(
        'No credentials supplied. Copy '
        'integration_test/local/secrets.template to '
        'integration_test/local/secrets.properties, fill in real values, '
        'and re-run with:\n'
        '  --dart-define-from-file=integration_test/local/secrets.properties',
      );
    }

    // Start from a clean, logged-out state. Nothing is configured beyond the
    // credentials below: the app now authenticates straight against the
    // provider's player_api.php, so this passing is itself the proof that no
    // backend proxy is involved. Run it with the Node server stopped.
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    final dbPath = p.join(await getDatabasesPath(), 'vod_catalog.db');
    await deleteDatabase(dbPath);

    await tester.pumpWidget(const ProviderScope(child: VodCatalogApp()));
    await tester.pump(const Duration(milliseconds: 500));

    await _pumpUntil(
      tester,
      () => find.text('Add Xtream Account').evaluate().isNotEmpty,
      description: 'login screen to appear',
    );

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), _serverUrl);
    await tester.enterText(fields.at(1), _username);
    await tester.enterText(fields.at(2), _password);
    await tester.enterText(fields.at(3), _label);

    final submitButton = find.text('Save & Cache Catalog');
    await tester.ensureVisible(submitButton);
    await tester.pump();
    await tester.tap(submitButton);

    // Poll for either success (redirect to Movies) or a visible error
    // banner, printing whichever shows up so the failure is diagnosable
    // without guessing.
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (true) {
      await tester.pump(const Duration(milliseconds: 250));
      final errorFinder = find.byWidgetPredicate(
        (w) => w is Text && (w.data?.startsWith('ApiException') ?? false),
      );
      if (errorFinder.evaluate().isNotEmpty) {
        final errorText = tester.widget<Text>(errorFinder).data;
        // ignore: avoid_print
        print('[real-login-diag] Login failed with: $errorText');
        fail('Login failed: $errorText');
      }
      if (find.text('Add Xtream Account').evaluate().isEmpty &&
          find.text('TV Shows').evaluate().isNotEmpty) {
        // ignore: avoid_print
        print('[real-login-diag] Login succeeded, Movies screen reached.');
        break;
      }
      if (DateTime.now().isAfter(deadline)) {
        final visibleText = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .whereType<String>()
            .where((s) => s.trim().isNotEmpty)
            .toSet()
            .join(' | ');
        fail('Timed out waiting for login to resolve.\n'
            'Currently visible text: $visibleText');
      }
    }
  });
}
