/// Tests for [DownloadQueueNotifier], the download queue state machine.
///
/// The real [BackgroundDownloaderEngine] is never constructed here — it
/// needs a platform. Instead every test drives a [FakeDownloadEngine] (a
/// hand-rolled implementation of the [DownloadEngine] interface with
/// controllable [StreamController]s) through the same seam the notifier
/// uses in production. Persistence goes through a real [DatabaseService]
/// backed by `sqflite_common_ffi`, following the pattern in
/// `test/core/database_service_test.dart`.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:vod_downloader/core/database/database_service.dart';
import 'package:vod_downloader/core/models/media_item.dart';
import 'package:vod_downloader/core/models/series_details.dart';
import 'package:vod_downloader/core/network/xtream_client.dart';
import 'package:vod_downloader/core/services/download_service.dart';
import 'package:vod_downloader/features/downloads/download_engine.dart';
import 'package:vod_downloader/features/downloads/download_queue_provider.dart';
import 'package:vod_downloader/features/downloads/download_task.dart';

/// Fake [DownloadEngine]: records every call the notifier makes, and lets
/// tests push status/progress/canPause events on demand to simulate the
/// underlying plugin's async callbacks.
class FakeDownloadEngine implements DownloadEngine {
  final _statusController = StreamController<EngineStatusUpdate>.broadcast();
  final _progressController =
      StreamController<EngineProgressUpdate>.broadcast();
  final _canPauseController =
      StreamController<EngineCanPauseUpdate>.broadcast();

  /// Task ids the engine currently considers live — mirrors what a real
  /// `restoreFromDisk()` orphan check would see. Seed this directly in
  /// tests that exercise [liveTaskIds] without going through [enqueue].
  final Set<String> liveIds = {};

  final Map<String, int> enqueueCalls = {};
  final Map<String, String> lastUrl = {};

  /// Per-task override for [moveToDownloads]'s return value. If a task id
  /// has no entry, a default fake path is returned.
  final Map<String, String?> moveResults = {};

  int pauseCalls = 0;
  int resumeCalls = 0;
  int cancelCalls = 0;
  bool enqueueShouldFail = false;
  bool initializeCalled = false;

  @override
  Stream<EngineStatusUpdate> get statusUpdates => _statusController.stream;
  @override
  Stream<EngineProgressUpdate> get progressUpdates =>
      _progressController.stream;
  @override
  Stream<EngineCanPauseUpdate> get canPauseUpdates =>
      _canPauseController.stream;

  @override
  Future<void> initialize() async {
    initializeCalled = true;
  }

  @override
  void dispose() {
    _statusController.close();
    _progressController.close();
    _canPauseController.close();
  }

  @override
  Future<bool> enqueue({
    required String taskId,
    required String url,
    required String fileName,
  }) async {
    enqueueCalls[taskId] = (enqueueCalls[taskId] ?? 0) + 1;
    lastUrl[taskId] = url;
    if (enqueueShouldFail) return false;
    liveIds.add(taskId);
    return true;
  }

  @override
  Future<bool> pause(String taskId) async {
    pauseCalls++;
    return true;
  }

  @override
  Future<bool> resume(String taskId) async {
    resumeCalls++;
    return true;
  }

  @override
  Future<bool> cancel(String taskId) async {
    cancelCalls++;
    liveIds.remove(taskId);
    return true;
  }

  @override
  Future<String?> moveToDownloads(String taskId) async {
    if (moveResults.containsKey(taskId)) return moveResults[taskId];
    return '/fake/downloads/$taskId';
  }

  @override
  Future<Set<String>> liveTaskIds() async => Set.of(liveIds);

  // --- test-only helpers to drive the streams, mirroring what
  // BackgroundDownloaderEngine._handleUpdate would fan out in production ---

  void pushStatus(String taskId, EngineStatus status, {String? rawError}) {
    _statusController.add(
      EngineStatusUpdate(taskId: taskId, status: status, rawError: rawError),
    );
  }

  void pushProgress(String taskId, double progress, {int? expectedFileSize}) {
    _progressController.add(
      EngineProgressUpdate(
        taskId: taskId,
        progress: progress,
        expectedFileSize: expectedFileSize,
      ),
    );
  }

  void pushCanPause(String taskId, bool canPause) {
    _canPauseController.add(
      EngineCanPauseUpdate(taskId: taskId, canPause: canPause),
    );
  }
}

/// Trick to obtain a real [Ref] without a widget tree: a [Provider]'s own
/// build callback is handed a [Ref], which we capture and hand to
/// [DownloadQueueNotifier]. [DownloadQueueNotifier] only ever reads `ref`
/// through the default resolver closures, which every test below replaces
/// with explicit `currentSourceId`/`downloadService` callbacks — so `ref`
/// itself is never actually read.
final _refProvider = Provider<Ref>((ref) => ref);

const _movie = MediaItem(
  streamId: 'm1',
  name: 'Interstellar',
  sourceId: 'srcA',
  containerExtension: 'mkv',
);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    // The no-isolate factory runs entirely in-process rather than round-
    // tripping through a background isolate. DownloadQueueNotifier persists
    // fire-and-forget (`unawaited(_persist(...))`), so tests need writes to
    // resolve deterministically within a bounded number of event-loop turns
    // (see `settle()` below) rather than racing an isolate IPC round trip.
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory tempDir;
  late DatabaseService db;
  late ProviderContainer container;
  late Ref ref;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('download_queue_test_');
    DatabaseService.testDbPath = p.join(tempDir.path, 'test.db');
    await DatabaseService.resetForTest();
    db = DatabaseService.instance;
    container = ProviderContainer();
    ref = container.read(_refProvider);
  });

  tearDown(() async {
    container.dispose();
    await DatabaseService.resetForTest();
    DatabaseService.testDbPath = null;
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// Lets pending microtasks/futures run to completion: broadcast stream
  /// event delivery, and the chained awaits inside
  /// DownloadQueueNotifier._handleComplete / _persist (itself unawaited by
  /// the notifier, since persistence is fire-and-forget).
  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  DownloadQueueNotifier makeNotifier({
    required FakeDownloadEngine engine,
    String? sourceId = 'srcA',
    DownloadService? downloadService,
  }) {
    final svc = downloadService ??
        DownloadService(
          client: XtreamClient(
            baseUrl: 'http://provider.tv:8080',
            username: 'user1',
            password: 'unused-in-most-tests',
          ),
        );
    final notifier = DownloadQueueNotifier(
      ref,
      engine: engine,
      db: db,
      currentSourceId: () => sourceId,
      downloadService: () => svc,
    );
    addTearDown(notifier.dispose);
    return notifier;
  }

  DownloadTask taskById(DownloadQueueNotifier notifier, String id) =>
      notifier.state.firstWhere((t) => t.id == id);

  group('enqueue', () {
    test('engine.initialize() is called on construction', () async {
      final engine = FakeDownloadEngine();
      makeNotifier(engine: engine);
      await settle();
      expect(engine.initializeCalled, isTrue);
    });

    test(
        'happy path: queued -> running -> progress -> complete with '
        'localUri populated by the move-to-shared-storage step', () async {
      final engine = FakeDownloadEngine();
      final notifier = makeNotifier(engine: engine);

      await notifier.enqueueMovie(item: _movie);
      await settle();

      expect(taskById(notifier, 'm1').status, DownloadStatus.queued);
      expect(engine.enqueueCalls['m1'], 1);
      final queuedRow = await db.getDownload('m1');
      expect(queuedRow, isNotNull);
      expect(queuedRow!['status'], 'queued');

      engine.pushStatus('m1', EngineStatus.running);
      await settle();
      expect(taskById(notifier, 'm1').status, DownloadStatus.running);

      engine.pushProgress('m1', 0.5, expectedFileSize: 2000000000);
      await settle();
      var task = taskById(notifier, 'm1');
      expect(task.progress, 0.5);
      expect(task.bytesTotal, 2000000000);
      final midRow = await db.getDownload('m1');
      expect(midRow!['progress'], 0.5);

      engine.moveResults['m1'] = '/storage/emulated/0/Download/Interstellar.mkv';
      engine.pushStatus('m1', EngineStatus.complete);
      await settle();

      task = taskById(notifier, 'm1');
      expect(task.status, DownloadStatus.complete);
      expect(task.progress, 1.0);
      expect(task.localUri, '/storage/emulated/0/Download/Interstellar.mkv');
      expect(task.error, isNull);

      final finalRow = await db.getDownload('m1');
      expect(finalRow!['status'], 'complete');
      expect(finalRow['localUri'], '/storage/emulated/0/Download/Interstellar.mkv');
    });

    test(
        'a failed moveToDownloads must NOT leave the task complete, and '
        'must record an error', () async {
      final engine = FakeDownloadEngine();
      final notifier = makeNotifier(engine: engine);

      await notifier.enqueueMovie(item: _movie);
      await settle();
      engine.pushStatus('m1', EngineStatus.running);
      await settle();

      engine.moveResults['m1'] = null; // simulates moveToSharedStorage failure
      engine.pushStatus('m1', EngineStatus.complete);
      await settle();

      final task = taskById(notifier, 'm1');
      expect(task.status, isNot(DownloadStatus.complete));
      expect(task.status, DownloadStatus.failed);
      expect(task.error, isNotNull);
      expect(task.localUri, isNull);

      final row = await db.getDownload('m1');
      expect(row!['status'], isNot('complete'));
      expect(row['status'], 'failed');
      expect(row['localUri'], isNull);
    });

    test('engine.enqueue() returning false marks the task failed immediately',
        () async {
      final engine = FakeDownloadEngine()..enqueueShouldFail = true;
      final notifier = makeNotifier(engine: engine);

      await notifier.enqueueMovie(item: _movie);
      await settle();

      final task = taskById(notifier, 'm1');
      expect(task.status, DownloadStatus.failed);
      expect(task.error, 'Failed to start the download.');
    });

    test('idempotent enqueue: an already queued/running/paused item is not '
        're-enqueued', () async {
      final engine = FakeDownloadEngine();
      final notifier = makeNotifier(engine: engine);

      await notifier.enqueueMovie(item: _movie);
      await settle();
      await notifier.enqueueMovie(item: _movie); // still queued
      await settle();
      expect(engine.enqueueCalls['m1'], 1);
      expect(notifier.state.where((t) => t.id == 'm1').length, 1);

      engine.pushStatus('m1', EngineStatus.running);
      await settle();
      await notifier.enqueueMovie(item: _movie); // now running
      await settle();
      expect(engine.enqueueCalls['m1'], 1);

      engine.pushStatus('m1', EngineStatus.paused);
      await settle();
      await notifier.enqueueMovie(item: _movie); // now paused
      await settle();
      expect(engine.enqueueCalls['m1'], 1);
    });

    test('enqueueEpisode builds a "series NsNNeNN - title" file name and '
        'is idempotent the same way', () async {
      final engine = FakeDownloadEngine();
      final notifier = makeNotifier(engine: engine);
      const episode = EpisodeItem(
        id: 'e1',
        episodeNum: '3',
        title: 'The Great War',
        containerExtension: 'mp4',
        seasonNum: '8',
      );

      await notifier.enqueueEpisode(
        episode: episode,
        seriesName: 'Game of Thrones',
      );
      await settle();

      final task = taskById(notifier, 'e1');
      expect(task.title, 'Game of Thrones S08E03 - The Great War');
      expect(task.fileName, startsWith('Game of Thrones S08E03'));
      expect(task.fileName, endsWith('.mp4'));
      expect(engine.enqueueCalls['e1'], 1);

      await notifier.enqueueEpisode(
        episode: episode,
        seriesName: 'Game of Thrones',
      );
      await settle();
      expect(engine.enqueueCalls['e1'], 1);
    });

    test('missing stream id fails clearly rather than enqueueing', () async {
      final engine = FakeDownloadEngine();
      final notifier = makeNotifier(engine: engine);
      const noId = MediaItem(streamId: '', name: 'Broken', sourceId: 'srcA');

      await expectLater(
        notifier.enqueueMovie(item: noId),
        throwsA(isA<DownloadQueueException>()),
      );
      await settle();
      expect(notifier.state, isEmpty);
      expect(engine.enqueueCalls, isEmpty);
    });
  });

  group('canPause safety', () {
    test('canPause=false from the engine is reflected on the task, and '
        'pause() must then no-op rather than calling the engine', () async {
      final engine = FakeDownloadEngine();
      final notifier = makeNotifier(engine: engine);

      await notifier.enqueueMovie(item: _movie);
      await settle();
      engine.pushStatus('m1', EngineStatus.running);
      await settle();

      engine.pushCanPause('m1', false);
      await settle();
      expect(taskById(notifier, 'm1').canPause, isFalse);

      await notifier.pause('m1');
      expect(engine.pauseCalls, 0,
          reason: 'pausing a non-resumable download destroys the transfer '
              '-- the notifier must never call engine.pause() once '
              'canPause is false');
      expect(taskById(notifier, 'm1').status, DownloadStatus.running);

      engine.pushCanPause('m1', true);
      await settle();
      expect(taskById(notifier, 'm1').canPause, isTrue);

      await notifier.pause('m1');
      expect(engine.pauseCalls, 1);
    });
  });

  group('pause / resume / cancel', () {
    test('pause -> resume transitions', () async {
      final engine = FakeDownloadEngine();
      final notifier = makeNotifier(engine: engine);

      await notifier.enqueueMovie(item: _movie);
      await settle();
      engine.pushStatus('m1', EngineStatus.running);
      await settle();

      await notifier.pause('m1');
      expect(engine.pauseCalls, 1);
      engine.pushStatus('m1', EngineStatus.paused);
      await settle();
      expect(taskById(notifier, 'm1').status, DownloadStatus.paused);

      await notifier.resume('m1');
      expect(engine.resumeCalls, 1);
      engine.pushStatus('m1', EngineStatus.running);
      await settle();
      expect(taskById(notifier, 'm1').status, DownloadStatus.running);
    });

    test('cancel() moves a non-terminal task straight to canceled', () async {
      final engine = FakeDownloadEngine();
      final notifier = makeNotifier(engine: engine);

      await notifier.enqueueMovie(item: _movie);
      await settle();

      await notifier.cancel('m1');
      await settle();
      expect(engine.cancelCalls, 1);
      expect(taskById(notifier, 'm1').status, DownloadStatus.canceled);

      // Calling cancel() again on an already-terminal task is a no-op.
      await notifier.cancel('m1');
      expect(engine.cancelCalls, 1);
    });
  });

  group('failed -> retry -> running', () {
    test('retry re-enqueues with the in-memory cached url', () async {
      final engine = FakeDownloadEngine();
      final notifier = makeNotifier(engine: engine);

      await notifier.enqueueMovie(item: _movie);
      await settle();
      engine.pushStatus('m1', EngineStatus.failed, rawError: 'connection reset');
      await settle();

      var task = taskById(notifier, 'm1');
      expect(task.status, DownloadStatus.failed);
      expect(task.error, isNotNull);

      await notifier.retry('m1');
      await settle();
      expect(engine.enqueueCalls['m1'], 2);
      task = taskById(notifier, 'm1');
      expect(task.status, DownloadStatus.queued);
      expect(task.error, isNull);

      engine.pushStatus('m1', EngineStatus.running);
      await settle();
      expect(taskById(notifier, 'm1').status, DownloadStatus.running);
    });
  });

  group('dismiss', () {
    test('removes the task from state and the database, does not reappear '
        'after restoreFromDisk(), and never touches the downloaded file',
        () async {
      final engine = FakeDownloadEngine();
      final notifier = makeNotifier(engine: engine);

      final downloadedFile = File(p.join(tempDir.path, 'Interstellar.mkv'));
      await downloadedFile.writeAsString('fake movie bytes');
      engine.moveResults['m1'] = downloadedFile.path;

      await notifier.enqueueMovie(item: _movie);
      await settle();
      engine.pushStatus('m1', EngineStatus.running);
      await settle();
      engine.pushStatus('m1', EngineStatus.complete);
      await settle();

      final completed = taskById(notifier, 'm1');
      expect(completed.status, DownloadStatus.complete);
      expect(completed.localUri, downloadedFile.path);

      await notifier.dismiss('m1');
      await settle();

      expect(notifier.state.any((t) => t.id == 'm1'), isFalse);
      expect(await db.getDownload('m1'), isNull);
      expect(await downloadedFile.exists(), isTrue,
          reason: 'dismiss() must never delete the downloaded file -- it '
              'lives in the public Downloads folder and must survive the '
              'queue entry being removed');

      await notifier.restoreFromDisk();
      await settle();
      expect(notifier.state.any((t) => t.id == 'm1'), isFalse,
          reason: 'a dismissed task must not reappear after restore');
    });

    test('dismissing a non-terminal task cancels it in the engine first',
        () async {
      final engine = FakeDownloadEngine();
      final notifier = makeNotifier(engine: engine);

      await notifier.enqueueMovie(item: _movie);
      await settle();
      engine.pushStatus('m1', EngineStatus.running);
      await settle();

      await notifier.dismiss('m1');
      await settle();

      expect(engine.cancelCalls, 1);
      expect(notifier.state.any((t) => t.id == 'm1'), isFalse);
      expect(await db.getDownload('m1'), isNull);
    });
  });

  group('clearCompleted', () {
    test('removes only completed tasks, leaving active and failed ones',
        () async {
      final engine = FakeDownloadEngine();
      final notifier = makeNotifier(engine: engine);

      // m1 -> complete
      await notifier.enqueueMovie(item: _movie);
      await settle();
      engine.pushStatus('m1', EngineStatus.running);
      await settle();
      engine.pushStatus('m1', EngineStatus.complete);
      await settle();

      // e1 -> failed
      const episode = EpisodeItem(
        id: 'e1',
        episodeNum: '1',
        title: 'Pilot',
        containerExtension: 'mp4',
        seasonNum: '1',
      );
      await notifier.enqueueEpisode(episode: episode, seriesName: 'Show');
      await settle();
      engine.pushStatus('e1', EngineStatus.failed, rawError: 'boom');
      await settle();

      // m2 -> still queued (active)
      const movie2 = MediaItem(streamId: 'm2', name: 'Other', sourceId: 'srcA');
      await notifier.enqueueMovie(item: movie2);
      await settle();

      expect(taskById(notifier, 'm1').status, DownloadStatus.complete);
      expect(taskById(notifier, 'e1').status, DownloadStatus.failed);
      expect(taskById(notifier, 'm2').status, DownloadStatus.queued);

      await notifier.clearCompleted();
      await settle();

      final ids = notifier.state.map((t) => t.id).toSet();
      expect(ids, {'e1', 'm2'});
      expect(await db.getDownload('m1'), isNull);
      expect(await db.getDownload('e1'), isNotNull);
      expect(await db.getDownload('m2'), isNotNull);
    });
  });

  group('restoreFromDisk', () {
    test('rehydrates persisted tasks and reconciles an orphaned "running" '
        'row (no live engine task) into failed instead of leaving it stuck',
        () async {
      await db.upsertDownload({
        'id': 'orphanRunning',
        'sourceId': 'srcA',
        'title': 'Orphan',
        'fileName': 'orphan.mp4',
        'status': 'running',
        'progress': 0.4,
        'bytesTotal': 1000,
        'localUri': null,
        'error': null,
        'createdAt': 1,
      });
      await db.upsertDownload({
        'id': 'liveRunning',
        'sourceId': 'srcA',
        'title': 'Live',
        'fileName': 'live.mp4',
        'status': 'running',
        'progress': 0.4,
        'bytesTotal': 1000,
        'localUri': null,
        'error': null,
        'createdAt': 2,
      });
      await db.upsertDownload({
        'id': 'doneOne',
        'sourceId': 'srcA',
        'title': 'Done',
        'fileName': 'done.mp4',
        'status': 'complete',
        'progress': 1.0,
        'bytesTotal': 1000,
        'localUri': '/x/done.mp4',
        'error': null,
        'createdAt': 3,
      });

      final engine = FakeDownloadEngine()..liveIds.add('liveRunning');
      final notifier = makeNotifier(engine: engine);

      await notifier.restoreFromDisk();
      await settle();

      final orphan = taskById(notifier, 'orphanRunning');
      expect(orphan.status, DownloadStatus.failed);
      expect(orphan.error, isNotNull);

      final live = taskById(notifier, 'liveRunning');
      expect(live.status, DownloadStatus.running);

      final done = taskById(notifier, 'doneOne');
      expect(done.status, DownloadStatus.complete);

      // The reconciliation itself must be persisted, not just held
      // in-memory, otherwise the orphan reappears "running" on next launch.
      final orphanRow = await db.getDownload('orphanRunning');
      expect(orphanRow!['status'], 'failed');
    });
  });

  group('credential safety', () {
    const sentinel = 'S3CR3T_TOKEN_XYZ';

    test('the account password never reaches a persisted row or a task '
        'error string, even when the engine echoes the raw request url',
        () async {
      final engine = FakeDownloadEngine();
      final svc = DownloadService(
        client: XtreamClient(
          baseUrl: 'http://provider.tv:8080',
          username: 'joe',
          password: sentinel,
        ),
      );
      final notifier = makeNotifier(engine: engine, downloadService: svc);

      await notifier.enqueueMovie(item: _movie);
      await settle();

      // Sanity check: the fake engine really did receive a url containing
      // the sentinel -- otherwise the rest of this test would prove nothing.
      expect(engine.lastUrl['m1'], contains(sentinel));

      Future<void> assertRowClean() async {
        final row = await db.getDownload('m1');
        expect(row, isNotNull);
        for (final entry in row!.entries) {
          final v = entry.value;
          if (v is String) {
            expect(v, isNot(contains(sentinel)),
                reason: 'column ${entry.key} leaked the account password');
          }
        }
      }

      final firstRow = await db.getDownload('m1');
      // Structural check: the persisted schema has no url-shaped column at
      // all -- _urlById is genuinely in-memory only, never written to disk.
      expect(
        firstRow!.keys.toSet(),
        {
          'id', 'sourceId', 'title', 'fileName', 'status', 'progress',
          'bytesTotal', 'localUri', 'error', 'createdAt',
        },
      );
      await assertRowClean();

      engine.pushStatus('m1', EngineStatus.running);
      await settle();
      await assertRowClean();

      // Simulate a platform failure that echoes the raw request url
      // (credentials and all) -- exactly the scenario EngineStatusUpdate's
      // docs warn callers to redact before persisting/displaying.
      engine.pushStatus(
        'm1',
        EngineStatus.failed,
        rawError: 'Connection failed for ${engine.lastUrl['m1']}',
      );
      await settle();

      final task = taskById(notifier, 'm1');
      expect(task.error, isNotNull);
      expect(task.error, isNot(contains(sentinel)));
      await assertRowClean();
    });
  });

  group('no active account', () {
    test('enqueueMovie fails with a clear error rather than crashing',
        () async {
      final engine = FakeDownloadEngine();
      final notifier =
          makeNotifier(engine: engine, downloadService: DownloadService());

      await expectLater(
        notifier.enqueueMovie(item: _movie),
        throwsA(
          isA<DownloadQueueException>().having(
            (e) => e.message,
            'message',
            contains('No active Xtream account'),
          ),
        ),
      );
      await settle();
      expect(notifier.state, isEmpty);
      expect(engine.enqueueCalls, isEmpty);
      expect(await db.getDownload('m1'), isNull);
    });
  });

  group('retry after app restart', () {
    test('retry on a task rehydrated by restoreFromDisk has no cached url '
        'and reports an error instead of crashing or silently doing nothing',
        () async {
      // First "session": enqueue and let it fail.
      final engineA = FakeDownloadEngine();
      final notifierA = makeNotifier(engine: engineA);
      await notifierA.enqueueMovie(item: _movie);
      await settle();
      engineA.pushStatus('m1', EngineStatus.failed, rawError: 'network error');
      await settle();
      expect(taskById(notifierA, 'm1').status, DownloadStatus.failed);

      // Second "session": brand-new notifier/engine (as a real app restart
      // would produce), same on-disk database.
      final engineB = FakeDownloadEngine();
      final notifierB = makeNotifier(engine: engineB);
      await notifierB.restoreFromDisk();
      await settle();
      expect(taskById(notifierB, 'm1').status, DownloadStatus.failed);

      await notifierB.retry('m1');
      await settle();

      expect(engineB.enqueueCalls['m1'], isNull,
          reason: 'must not attempt to re-enqueue with no cached url');
      final task = taskById(notifierB, 'm1');
      expect(task.status, DownloadStatus.failed);
      expect(task.error, contains('restart'));
    });
  });
}
