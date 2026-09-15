/// Thin seam between `download_queue_provider.dart` and the
/// `background_downloader` plugin.
///
/// `background_downloader` needs a real platform (Android/iOS) to do
/// anything, so it cannot be exercised from plain `flutter test`. Everything
/// plugin-shaped lives behind [DownloadEngine] here; the queue notifier only
/// ever talks to that interface, so `test/features/download_queue_test.dart`
/// can drive the state machine against a fake implementation instead.
///
/// The plugin's own `DownloadTask` class name collides with our
/// `download_task.dart` model, so the plugin is imported qualified as `bg`
/// throughout this file — nothing outside this file needs to know that.
library;

import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart' as bg;
import 'package:flutter/foundation.dart';

/// Narrowed status vocabulary surfaced by [DownloadEngine], one level above
/// `bg.TaskStatus`. Kept separate from `DownloadStatus` (the UI-facing model
/// in `download_task.dart`) so this file has no dependency on that one.
enum EngineStatus {
  enqueued,
  running,
  paused,
  complete,
  failed,
  canceled,
  notFound,
  waitingToRetry,
}

class EngineStatusUpdate {
  final String taskId;
  final EngineStatus status;

  /// Raw, NOT credential-redacted failure detail (e.g. a platform exception
  /// description, which can echo the request URL). Callers must redact
  /// before persisting or displaying this.
  final String? rawError;

  const EngineStatusUpdate({
    required this.taskId,
    required this.status,
    this.rawError,
  });
}

class EngineProgressUpdate {
  final String taskId;

  /// 0.0-1.0. `background_downloader` also uses negative sentinel values on
  /// [EngineProgressUpdate] streams for failed/canceled/etc; this engine
  /// clamps those into the corresponding [EngineStatusUpdate] instead, so a
  /// [EngineProgressUpdate] delivered here is always genuinely 0.0-1.0.
  final double progress;

  /// Total file size in bytes, if currently known (only meaningful for
  /// 0 < progress < 1 — see `background_downloader`'s own docs on
  /// `expectedFileSize`).
  final int? expectedFileSize;

  const EngineProgressUpdate({
    required this.taskId,
    required this.progress,
    this.expectedFileSize,
  });
}

class EngineCanPauseUpdate {
  final String taskId;
  final bool canPause;

  const EngineCanPauseUpdate({required this.taskId, required this.canPause});
}

/// Engine-agnostic contract for starting/controlling downloads. The real
/// implementation ([BackgroundDownloaderEngine]) wraps
/// `package:background_downloader`; tests supply a fake.
abstract class DownloadEngine {
  /// Prepares the engine for use: wires up notifications, starts task
  /// tracking, and requests the notification permission. Safe to call more
  /// than once — implementations must no-op after the first successful call.
  Future<void> initialize();

  /// Releases the engine's own subscriptions. Must be called when the owner
  /// is disposed, otherwise every `ProviderScope` rebuild leaks a listener
  /// on the process-wide update stream.
  void dispose();

  /// Status transitions, fanned out from a single underlying subscription.
  Stream<EngineStatusUpdate> get statusUpdates;

  /// Progress ticks, fanned out from the same single underlying
  /// subscription as [statusUpdates].
  Stream<EngineProgressUpdate> get progressUpdates;

  /// Fired once a task has been running long enough for the engine to know
  /// whether the server supports resuming a paused download.
  Stream<EngineCanPauseUpdate> get canPauseUpdates;

  /// Enqueues a new download. [taskId] must be unique per in-flight task —
  /// the caller (queue notifier) uses the item id directly, so it also
  /// doubles as the idempotency key.
  Future<bool> enqueue({
    required String taskId,
    required String url,
    required String fileName,
  });

  Future<bool> pause(String taskId);

  Future<bool> resume(String taskId);

  Future<bool> cancel(String taskId);

  /// Moves the downloaded file from app-private storage to the public
  /// Downloads folder. Returns the destination path, or `null` on failure —
  /// callers must NOT treat the task as complete when this returns `null`.
  Future<String?> moveToDownloads(String taskId);

  /// Task ids the engine currently considers live (enqueued/running/
  /// paused/waiting-to-retry), used by `restoreFromDisk()` to detect a
  /// database row claiming to be active with no backing native task.
  Future<Set<String>> liveTaskIds();
}

/// Real [DownloadEngine] backed by `package:background_downloader`.
class BackgroundDownloaderEngine implements DownloadEngine {
  final _statusController = StreamController<EngineStatusUpdate>.broadcast();
  final _progressController =
      StreamController<EngineProgressUpdate>.broadcast();
  final _canPauseController =
      StreamController<EngineCanPauseUpdate>.broadcast();

  /// Native tasks keyed by id, populated as status updates arrive. Needed
  /// because `pause`/`resume`/`moveToSharedStorage` all take the plugin's
  /// own `bg.DownloadTask` object, not just an id string.
  final Map<String, bg.DownloadTask> _tasks = {};

  bool _initialized = false;

  /// Serialises downloads. Xtream providers commonly cap an account at a
  /// small number of simultaneous connections — 1 is typical — and a second
  /// concurrent transfer is simply refused by the server. Queueing here means
  /// extra downloads wait their turn instead of failing.
  final _taskQueue = bg.MemoryTaskQueue()
    ..maxConcurrent = maxConcurrentDownloads;

  /// Simultaneous downloads allowed. Kept at 1 because that is the common
  /// Xtream `max_connections` value; raising it risks the provider refusing
  /// transfers, and the account's own limit is the real ceiling.
  static const int maxConcurrentDownloads = 1;


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
    if (_initialized) return;
    _initialized = true;

    bg.FileDownloader().configureNotification(
      running: const bg.TaskNotification(
        'Downloading {displayName}',
        '{progress} • {networkSpeed} • {timeRemaining}',
      ),
      complete: const bg.TaskNotification(
        'Download complete',
        '{displayName}',
      ),
      paused: const bg.TaskNotification('Download paused', '{displayName}'),
      error: const bg.TaskNotification('Download failed', '{displayName}'),
      progressBar: true,
    );

    // Deliberately NOT FileDownloader().updates. That stream is
    // single-subscription and hangs off a *mutable* StreamController field
    // inside the plugin (`base_downloader.dart`'s `var updates`), which
    // `resetUpdatesStreamController()` closes and replaces. Anything holding
    // the old stream silently stops receiving events, and the plugin then
    // drops updates entirely because it checks `updates.hasListener` on the
    // *current* controller before emitting. Observed in practice as exactly
    // one event arriving per app run while the download ran to completion.
    //
    // registerCallbacks is the plugin's documented mechanism for exactly
    // this reason, and it is immune to the controller being swapped.
    bg.FileDownloader().addTaskQueue(_taskQueue);
    bg.FileDownloader().registerCallbacks(
      taskStatusCallback: _handleUpdate,
      taskProgressCallback: _handleUpdate,
    );

    await bg.FileDownloader().start();

    if (Platform.isAndroid) {
      try {
        await bg.FileDownloader().permissions.request(
          bg.PermissionType.notifications,
        );
        // Denied is a legitimate outcome (Android 13+ prompts the user) —
        // downloads must keep working either way, just without a system
        // notification, so the result is intentionally not branched on.
      } catch (e) {
        // A permission-plumbing failure (e.g. no Activity attached yet)
        // must never block downloads from working.
        debugPrint('DownloadEngine: notification permission request failed: $e');
      }
    }
  }

  @override
  void dispose() {
    _initialized = false;
    _statusController.close();
    _progressController.close();
    _canPauseController.close();
  }

  void _handleUpdate(bg.TaskUpdate update) {
    final taskId = update.task.taskId;
    if (update.task is bg.DownloadTask) {
      _tasks[taskId] = update.task as bg.DownloadTask;
    }

    switch (update) {
      case bg.TaskStatusUpdate():
        _statusController.add(
          EngineStatusUpdate(
            taskId: taskId,
            status: _mapStatus(update.status),
            rawError: update.exception?.description,
          ),
        );
        if (update.status == bg.TaskStatus.running &&
            update.task is bg.DownloadTask) {
          unawaited(_resolveCanPause(update.task as bg.DownloadTask));
        }
      case bg.TaskProgressUpdate():
        // background_downloader encodes failed/canceled/notFound/
        // waitingToRetry as negative progress sentinels on this stream;
        // those transitions are already reported via TaskStatusUpdate, so
        // only forward genuine 0.0-1.0 progress here.
        if (update.progress >= 0.0) {
          _progressController.add(
            EngineProgressUpdate(
              taskId: taskId,
              progress: update.progress.clamp(0.0, 1.0),
              expectedFileSize:
                  update.hasExpectedFileSize ? update.expectedFileSize : null,
            ),
          );
        }
    }
  }

  Future<void> _resolveCanPause(bg.DownloadTask task) async {
    bool canResume;
    try {
      canResume = await bg.FileDownloader().taskCanResume(task);
    } catch (_) {
      // Unknown -> assume not resumable rather than showing a pause
      // affordance that will silently fail per the CRITICAL TRAP: pause()
      // itself returns true even when the server can't actually resume.
      canResume = false;
    }
    _canPauseController.add(
      EngineCanPauseUpdate(taskId: task.taskId, canPause: canResume),
    );
  }

  EngineStatus _mapStatus(bg.TaskStatus status) => switch (status) {
    bg.TaskStatus.enqueued => EngineStatus.enqueued,
    bg.TaskStatus.running => EngineStatus.running,
    bg.TaskStatus.paused => EngineStatus.paused,
    bg.TaskStatus.complete => EngineStatus.complete,
    bg.TaskStatus.failed => EngineStatus.failed,
    bg.TaskStatus.canceled => EngineStatus.canceled,
    bg.TaskStatus.notFound => EngineStatus.notFound,
    bg.TaskStatus.waitingToRetry => EngineStatus.waitingToRetry,
  };

  @override
  Future<bool> enqueue({
    required String taskId,
    required String url,
    required String fileName,
  }) async {
    final task = bg.DownloadTask(
      taskId: taskId,
      url: url,
      filename: fileName,
      // Some Xtream providers reject requests with no User-Agent.
      headers: const {'User-Agent': 'Mozilla/5.0'},
      updates: bg.Updates.statusAndProgress,
      allowPause: true,
      // App-private storage first; download_queue_provider.dart moves the
      // finished file to public shared storage on completion. Writing
      // directly to a content:// URI disables pause/resume entirely, so
      // this must never target shared storage directly.
      baseDirectory: bg.BaseDirectory.applicationDocuments,
      directory: 'downloads',
      displayName: fileName,
    );
    _tasks[taskId] = task;
    // Via the queue, not FileDownloader().enqueue, so maxConcurrent is
    // honoured. add() is fire-and-forget: the task is queued now and
    // enqueued with the plugin when a slot frees up, so the status stream
    // is what reports it actually starting.
    _taskQueue.add(task);
    return true;
  }

  @override
  Future<bool> pause(String taskId) async {
    final task = _tasks[taskId];
    if (task == null) return false;
    return bg.FileDownloader().pause(task);
  }

  @override
  Future<bool> resume(String taskId) async {
    final task = _tasks[taskId];
    if (task == null) return false;
    return bg.FileDownloader().resume(task);
  }

  @override
  Future<bool> cancel(String taskId) =>
      bg.FileDownloader().cancelTaskWithId(taskId);

  @override
  Future<String?> moveToDownloads(String taskId) async {
    final task = _tasks[taskId];
    if (task == null) return null;
    return bg.FileDownloader().moveToSharedStorage(
      task,
      bg.SharedStorage.downloads,
    );
  }

  @override
  Future<Set<String>> liveTaskIds() async {
    final tasks = await bg.FileDownloader().allTasks(allGroups: true);
    return tasks.map((t) => t.taskId).toSet();
  }
}
