import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nodecast_catalog_flutter/core/services/download_service.dart';
import 'package:nodecast_catalog_flutter/main.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

/// Fake Xtream/nodecast backend used to drive the app end-to-end without a
/// real server. Seeds exactly one movie and one series (one season, one
/// episode) and streams a fixed-size dummy payload for any download request,
/// so the app's own download machinery can be exercised against real bytes
/// on disk.
const String _sourceId = 'mock-src-1';
const String _movieStreamId = '9001';
const String _movieName = 'Integration Test Movie';
const String _seriesId = '9101';
const String _seriesName = 'Integration Test Series';
const String _episodeId = '9201';
const String _episodeTitle = 'Integration Test Episode';
const int _oneMebibyte = 1024 * 1024;

class _MockBackend {
  late final HttpServer _server;
  String get baseUrl => 'http://127.0.0.1:${_server.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> stop() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    try {
      final segments = request.uri.pathSegments;

      if (request.method == 'GET' &&
          segments.length == 2 &&
          segments[0] == 'api' &&
          segments[1] == 'sources') {
        return await _json(request, <dynamic>[]);
      }

      if (request.method == 'POST' &&
          segments.length == 2 &&
          segments[0] == 'api' &&
          segments[1] == 'sources') {
        return await _json(request, {
          'id': _sourceId,
          'sourceId': _sourceId,
          'name': 'Integration Test Account',
          'url': 'http://fake-xtream.example.com',
          'username': 'testuser',
        });
      }

      if (request.method == 'POST' &&
          segments.length == 4 &&
          segments[0] == 'api' &&
          segments[1] == 'sources' &&
          segments[3] == 'sync') {
        return await _json(request, <String, dynamic>{});
      }

      if (segments.length == 5 &&
          segments[0] == 'api' &&
          segments[1] == 'proxy' &&
          segments[2] == 'xtream') {
        switch (segments[4]) {
          case 'vod_categories':
            return await _json(request, [
              {'category_id': '1', 'category_name': 'Test Movies'},
            ]);
          case 'series_categories':
            return await _json(request, [
              {'category_id': '2', 'category_name': 'Test Series'},
            ]);
          case 'vod_streams':
            return await _json(request, [
              {
                'stream_id': _movieStreamId,
                'name': _movieName,
                'category_id': '1',
                'category_name': 'Test Movies',
                'container_extension': 'mp4',
              },
            ]);
          case 'series':
            return await _json(request, [
              {
                'series_id': _seriesId,
                'name': _seriesName,
                'category_id': '2',
              },
            ]);
          case 'series_info':
            return await _json(request, {
              'info': {
                'name': _seriesName,
                'plot': 'A fake series used for integration testing.',
                'rating': '8.0',
              },
              'episodes': {
                '1': [
                  {
                    'id': _episodeId,
                    'episode_num': 1,
                    'title': _episodeTitle,
                    'container_extension': 'mp4',
                  },
                ],
              },
            });
        }
      }

      if (segments.length == 5 &&
          segments[0] == 'api' &&
          segments[1] == 'download') {
        return await _bytes(request, _oneMebibyte);
      }

      return await _json(request, {'error': 'not found'}, status: 404);
    } catch (_) {
      request.response.statusCode = 500;
      await request.response.close();
    }
  }

  Future<void> _json(HttpRequest request, dynamic data, {int status = 200}) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(data));
    await request.response.close();
  }

  Future<void> _bytes(HttpRequest request, int length) async {
    request.response.statusCode = 200;
    request.response.headers.contentType = ContentType.binary;
    const chunkSize = 64 * 1024;
    final chunk = List<int>.filled(chunkSize, 0x41);
    var remaining = length;
    while (remaining > 0) {
      final n = remaining < chunkSize ? remaining : chunkSize;
      request.response.add(n == chunkSize ? chunk : chunk.sublist(0, n));
      remaining -= n;
    }
    await request.response.close();
  }
}

/// Pumps frames until [condition] is true or [timeout] elapses.
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 20),
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

/// Pumps frames until [file] exists on disk with exactly [expectedSize]
/// bytes. Downloads are fire-and-forget from the UI's perspective, so
/// completion can only be observed by polling the real file.
Future<void> _pumpUntilDownloaded(
  WidgetTester tester,
  File file,
  int expectedSize, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    if (await file.exists() && await file.length() == expectedSize) return;
    if (DateTime.now().isAfter(deadline)) {
      fail(
        'Download did not complete in time: ${file.path} '
        '(exists=${await file.exists()})',
      );
    }
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late _MockBackend backend;

  setUpAll(() async {
    backend = _MockBackend();
    await backend.start();
  });

  tearDownAll(() => backend.stop());

  testWidgets('login, download a movie, download a series episode',
      (tester) async {
    // --- Start from a clean, logged-out state pointed at the fake backend ---
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await prefs.setString('backend_proxy_url', backend.baseUrl);

    final dbPath = p.join(await getDatabasesPath(), 'vod_catalog.db');
    await deleteDatabase(dbPath);

    final downloadDir = await DownloadService().getDownloadDirectory();
    if (await downloadDir.exists()) {
      await downloadDir.delete(recursive: true);
    }

    await tester.pumpWidget(const ProviderScope(child: VodCatalogApp()));

    // "Add Xtream Account" is static UI and renders in the very first
    // frame, so waiting on it alone doesn't guarantee BackendConfigNotifier
    // has finished its async SharedPreferences read yet. Without this pump,
    // the login form can be submitted before the mock backend URL is
    // actually loaded, racing loginWithXtream against the default URL.
    await tester.pump(const Duration(milliseconds: 500));

    await _pumpUntil(
      tester,
      () => find.text('Add Xtream Account').evaluate().isNotEmpty,
      description: 'login screen to appear',
    );

    // --- Login ---
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'http://fake-xtream.example.com');
    await tester.enterText(fields.at(1), 'testuser');
    await tester.enterText(fields.at(2), 'testpass');

    final submitButton = find.text('Save & Cache Catalog');
    await tester.ensureVisible(submitButton);
    await tester.pump();
    await tester.tap(submitButton);

    // Login triggers a chain of awaited HTTP calls (verify source, create
    // source, sync categories/movies/series) before redirecting; poll for
    // the seeded movie to appear on the Movies screen rather than assuming
    // a single pumpAndSettle covers it all.
    await _pumpUntil(
      tester,
      () => find.text(_movieName).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 40),
      description: 'catalog to sync and the seeded movie to appear',
    );

    // --- Download the movie ---
    final movieCard = find.text(_movieName);
    await tester.ensureVisible(movieCard);
    await tester.tap(movieCard);
    await tester.pumpAndSettle();

    final downloadMovieButton = find.text('Download Movie');
    expect(downloadMovieButton, findsOneWidget);
    await tester.tap(downloadMovieButton);
    await tester.pump();

    final movieFile = File(p.join(downloadDir.path, '$_movieName.mp4'));
    await _pumpUntilDownloaded(tester, movieFile, _oneMebibyte);
    expect(await movieFile.length(), _oneMebibyte);

    final closeButton = find.text('Close');
    await tester.ensureVisible(closeButton);
    await tester.tap(closeButton);
    await tester.pumpAndSettle();

    // --- Download a TV series episode ---
    final tvShowsTab = find.text('TV Shows');
    await tester.ensureVisible(tvShowsTab);
    await tester.tap(tvShowsTab);
    await _pumpUntil(
      tester,
      () => find.text(_seriesName).evaluate().isNotEmpty,
      description: 'seeded series to appear on TV Shows screen',
    );

    final seriesCard = find.text(_seriesName);
    await tester.ensureVisible(seriesCard);
    await tester.tap(seriesCard);
    await tester.pump();

    // Episode list loads via a separate async series-info request.
    await _pumpUntil(
      tester,
      () => find.text('Download').evaluate().isNotEmpty,
      description: 'episode list to load and its download button to appear',
    );

    final downloadEpisodeButton = find.text('Download');
    await tester.tap(downloadEpisodeButton);
    await tester.pump();

    final episodeFileName = '$_seriesName S1E1 - $_episodeTitle.mp4';
    final episodeFile = File(p.join(downloadDir.path, episodeFileName));
    await _pumpUntilDownloaded(tester, episodeFile, _oneMebibyte);
    expect(await episodeFile.length(), _oneMebibyte);
  });
}
