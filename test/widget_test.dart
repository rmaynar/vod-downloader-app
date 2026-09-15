import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vod_downloader/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: VodCatalogApp(),
      ),
    );
    expect(find.byType(VodCatalogApp), findsOneWidget);
  });
}
