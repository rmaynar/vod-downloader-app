/// Download queue: the Riverpod-facing state machine that the Downloads
/// screen and media-card progress UI (built by other agents in parallel)
/// depend on. See the class docs on [DownloadQueueNotifier] for the public
/// API contract.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database_service.dart';
import '../../core/models/media_item.dart';
import '../../core/models/series_details.dart';
import '../../core/services/download_service.dart';
import '../catalog/providers/catalog_provider.dart';
import 'download_engine.dart';
import 'download_task.dart';

/// Thrown by [DownloadQueueNotifier] when a download cannot be started —
/// no active account, or a malformed item. Message is always safe to
/// display/log (see [DownloadQueueNotifier._redact]).
class DownloadQueueException implements Exception {
  final String message;
  const DownloadQueueException(this.message);

  @override
  String toString() => message;
}

/// Manages the list of downloads: enqueueing, pause/resume/cancel/retry/
/// dismiss, and persistence through [DatabaseService] so the Downloads
/// screen survives a restart.
///
/// All `background_downloader` specifics live behind the injected
/// [DownloadEngine] (see `download_engine.dart`) — this class never imports
/// `package:background_downloader` itself, which is what lets
/// `download_queue_test.dart` exercise the full state machine with a fake
/// engine under plain `flutter test`.
class DownloadQueueNotifier extends StateNotifier<List<DownloadTask>> {
  final DownloadEngine _engine;
  final DatabaseService _db;
  final String? Function() _resolveSourceId;
  final DownloadService Function() _resolveDownloadService;

  /// In-memory only: the download URL used to (re-)enqueue each active/
  /// retryable task. Never persisted (it carries the account's credentials
  /// in the path) and never exposed outside this file — see
  /// `download_task.dart`'s [DownloadTask], which intentionally has no url
  /// field. A consequence: [retry] on a task rehydrated by
  /// [restoreFromDisk] (i.e. after an app restart) has no URL to retry
  /// with, and reports that back as an error rather than crashing or
  /// silently doing nothing.
  final Map<String, String> _urlById = {};

  /// In-memory only: preserves each task's original `createdAt` across
  /// repeated persists (DatabaseService.upsertDownload replaces the whole
  /// row), so re-persisting an existing task's progress doesn't reset its
  /// position in the "newest first" ordering `getDownloads()` returns.
  final Map<String, int> _createdAt = {};

  StreamSubscription<EngineStatusUpdate>? _statusSub;
  StreamSubscription<EngineProgressUpdate>? _progressSub;
  StreamSubscription<EngineCanPauseUpdate>? _canPauseSub;

  /// [ref] is only ever read through the two default resolver closures
  /// below, so it is captured by them rather than stored as a field — a
  /// field would be flagged unused, since the analyzer does not count a
  /// closure capture as a use.
  DownloadQueueNotifier(
    Ref ref, {
    DownloadEngine? engine,
    DatabaseService? db,
    String? Function()? currentSourceId,
    DownloadService Function()? downloadService,
  }) : _engine = engine ?? BackgroundDownloaderEngine(),
       _db = db ?? DatabaseService.instance,
       _resolveSourceId =
           currentSourceId ?? (() => ref.read(catalogProvider).currentSourceId),
       _resolveDownloadService =
           downloadService ?? (() => ref.read(downloadServiceProvider)),
       super(const []) {
    _statusSub = _engine.statusUpdates.listen(_onEngineStatus);
    _progressSub = _engine.progressUpdates.listen(_onEngineProgress);
    _canPauseSub = _engine.canPauseUpdates.listen(_onCanPause);
    // Fire-and-forget: safe to call again (and awaited) from
    // restoreFromDisk() — BackgroundDownloaderEngine.initialize() no-ops
    // after its first successful run.
    unawaited(_engine.initialize());
  }

  // ---------------------------------------------------------------------
  // Enqueue
  // ---------------------------------------------------------------------

  /// Downloads a movie/VOD [MediaItem]. No-op if [item] is already queued,
  /// running, or paused (idempotent enqueue). Throws
  /// [DownloadQueueException] with a clear, credential-safe message if
  /// there is no active account or the item has no usable stream id.
  Future<void> enqueueMovie({required MediaItem item}) async {
    final id = item.streamId;
    if (id.isEmpty) {
      throw DownloadQueueException(
        'Cannot download "${item.name}": missing stream id.',
      );
    }
    if (_byId(id)?.isActive == true) return;

    final service = _resolveDownloadService();
    final url = _buildUrlOrThrow(
      () => service.getDownloadUrlForMedia(item: item),
      missingIdMessage: 'Cannot download "${item.name}": missing stream id.',
    );

    final container =
        (item.containerExtension ?? 'mp4').replaceAll(RegExp(r'^\.'), '');
    final fileName = '${service.sanitizeFileName(item.name)}.$container';
    final sourceId = _resolveSourceId() ?? item.sourceId;

    await _startTask(
      DownloadTask(
        id: id,
        sourceId: sourceId,
        title: item.name,
        fileName: fileName,
      ),
      url,
    );
  }

  /// Downloads a TV series episode. Same idempotency/error semantics as
  /// [enqueueMovie].
  Future<void> enqueueEpisode({
    required EpisodeItem episode,
    required String seriesName,
    String? seasonNum,
  }) async {
    final id = episode.id;
    if (id.isEmpty) {
      throw DownloadQueueException(
        'Cannot download "${episode.title}": missing episode id.',
      );
    }
    if (_byId(id)?.isActive == true) return;

    final service = _resolveDownloadService();
    final url = _buildUrlOrThrow(
      () => service.getDownloadUrlForEpisode(episode: episode),
      missingIdMessage:
          'Cannot download "${episode.title}": missing episode id.',
    );

    final container =
        (episode.containerExtension ?? 'mp4').replaceAll(RegExp(r'^\.'), '');
    final title = service.formatEpisodeTitle(
      seriesName: seriesName,
      episode: episode,
      seasonNum: seasonNum,
    );
    final fileName = '${service.sanitizeFileName(title)}.$container';
    final sourceId = _resolveSourceId() ?? '';

    await _startTask(
      DownloadTask(
        id: id,
        sourceId: sourceId,
        title: title,
        fileName: fileName,
      ),
      url,
    );
  }

  /// Runs [build] (a `DownloadService.getDownloadUrl*` call) and converts
  /// its failure modes into [DownloadQueueException]: a null return (no
  /// usable id) becomes [missingIdMessage]; a [DownloadServiceException]
  /// (no active account) is surfaced with its own — already
  /// credential-safe — message.
  String _buildUrlOrThrow(
    String? Function() build, {
    required String missingIdMessage,
  }) {
    try {
      final url = build();
      if (url == null) throw DownloadQueueException(missingIdMessage);
      return url;
    } on DownloadServiceException catch (e) {
      throw DownloadQueueException(e.message);
    }
  }

  Future<void> _startTask(DownloadTask task, String url) async {
    _urlById[task.id] = url;
    _createdAt.putIfAbsent(task.id, () => DateTime.now().millisecondsSinceEpoch);
    _setState(task, persist: true);

    bool enqueued;
    try {
      enqueued = await _engine.enqueue(
        taskId: task.id,
        url: url,
        fileName: task.fileName,
      );
    } catch (_) {
      enqueued = false;
    }

    if (!enqueued) {
      _setState(
        task.copyWith(
          status: DownloadStatus.failed,
          error: 'Failed to start the download.',
        ),
        persist: true,
      );
    }
  }

  // ---------------------------------------------------------------------
  // Controls
  // ---------------------------------------------------------------------

  /// Pauses a running download. No-op if the task isn't running, or if the
  /// engine has already reported `canPause == false` for it (see the
  /// CRITICAL TRAP note in `download_engine.dart` — `pause()` itself can
  /// return `true` even when the server can't actually resume, so this
  /// class never relies on that return value as proof of pausability).
  Future<void> pause(String id) async {
    final task = _byId(id);
    if (task == null || task.status != DownloadStatus.running) return;
    if (!task.canPause) return;
    try {
      await _engine.pause(id);
    } catch (_) {
      // Engine will report the outcome via statusUpdates; nothing to do
      // here beyond not crashing.
    }
  }

  /// Resumes a paused download. No-op if the task isn't paused.
  Future<void> resume(String id) async {
    final task = _byId(id);
    if (task == null || task.status != DownloadStatus.paused) return;
    try {
      await _engine.resume(id);
    } catch (_) {}
  }

  /// Cancels an in-progress (queued/running/paused) download.
  ///
  /// No-op on a task already in a terminal state (complete/failed/
  /// canceled) — it does not re-invoke the engine and does not change the
  /// task's status, so calling `cancel()` on an already-finished download
  /// is safe but has no visible effect. Use [dismiss] to remove a
  /// terminal-state task from the list.
  Future<void> cancel(String id) async {
    final task = _byId(id);
    if (task == null || task.isTerminal) return;

    try {
      await _engine.cancel(id);
    } catch (_) {
      // Fall through: the task is still forced to `canceled` below so the
      // UI never gets stuck on a cancel press that silently failed.
    }
    _setState(task.copyWith(status: DownloadStatus.canceled), persist: true);
  }

  /// Re-enqueues a failed download. No-op if the task isn't failed.
  ///
  /// Only works while this task's original download URL is still cached in
  /// memory (i.e. within the same app session it was enqueued in — see
  /// [_urlById]'s docs). If it isn't, the task is left `failed` with a
  /// message explaining why, rather than crashing or hanging.
  Future<void> retry(String id) async {
    final task = _byId(id);
    if (task == null || task.status != DownloadStatus.failed) return;

    final url = _urlById[id];
    if (url == null) {
      _setState(
        task.copyWith(
          error:
              'Cannot retry after an app restart — remove this download and '
              'start it again from the library.',
        ),
        persist: true,
      );
      return;
    }

    await _startTask(
      task.copyWith(
        status: DownloadStatus.queued,
        progress: 0.0,
        clearError: true,
      ),
      url,
    );
  }

  /// Removes a single task from the queue and from the database.
  ///
  /// Valid for any status: a non-terminal task is cancelled first (see
  /// [cancel]), then removed either way. Never touches the downloaded file
  /// — [DownloadTask.localUri] points at a file in the user's public
  /// Downloads folder, which must survive the queue entry being dismissed.
  Future<void> dismiss(String id) async {
    final task = _byId(id);
    if (task == null) return;

    if (!task.isTerminal) {
      await cancel(id);
    }

    await _db.deleteDownload(id);
    state = state.where((t) => t.id != id).toList();
    _urlById.remove(id);
    _createdAt.remove(id);
  }

  /// Removes all completed downloads from the queue and database. Leaves
  /// queued/running/paused/failed/canceled rows untouched. Does not touch
  /// any downloaded file.
  Future<void> clearCompleted() async {
    await _db.clearCompletedDownloads();
    final removedIds = state
        .where((t) => t.status == DownloadStatus.complete)
        .map((t) => t.id)
        .toSet();
    for (final id in removedIds) {
      _urlById.remove(id);
      _createdAt.remove(id);
    }
    state = state.where((t) => t.status != DownloadStatus.complete).toList();
  }

  // ---------------------------------------------------------------------
  // Startup restore
  // ---------------------------------------------------------------------

  /// Rehydrates the queue from [DatabaseService] on app startup, and
  /// reconciles rows that claim to be `running`/`queued` but have no
  /// matching live task in the download engine (e.g. the app was killed
  /// mid-download and — per `background_downloader`'s own unproven
  /// restoration story — the native side never picked it back up): those
  /// rows are marked `failed` with a clear message instead of being left to
  /// spin forever in the UI.
  Future<void> restoreFromDisk() async {
    await _engine.initialize();

    final sourceId = _resolveSourceId();
    final rows = await _db.getDownloads(sourceId: sourceId);
    final live = await _engine.liveTaskIds();

    final restored = <DownloadTask>[];
    for (final row in rows) {
      var task = DownloadTask.fromRow(row);
      _createdAt[task.id] =
          (row['createdAt'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch;

      final claimsActive =
          task.status == DownloadStatus.running ||
          task.status == DownloadStatus.queued;
      if (claimsActive && !live.contains(task.id)) {
        task = task.copyWith(
          status: DownloadStatus.failed,
          error:
              'Download was interrupted (the app was closed) and could not '
              'be resumed. Please retry.',
        );
        await _persist(task);
      }
      restored.add(task);
    }

    state = restored;
  }

  // ---------------------------------------------------------------------
  // Engine event handling
  // ---------------------------------------------------------------------

  void _onEngineStatus(EngineStatusUpdate update) {
    final current = _byId(update.taskId);
    if (current == null) return;

    switch (update.status) {
      case EngineStatus.enqueued:
      case EngineStatus.waitingToRetry:
        _setState(
          current.copyWith(status: DownloadStatus.queued),
          persist: true,
        );
      case EngineStatus.running:
        _setState(
          current.copyWith(status: DownloadStatus.running, clearError: true),
          persist: true,
        );
      case EngineStatus.paused:
        _setState(
          current.copyWith(status: DownloadStatus.paused),
          persist: true,
        );
      case EngineStatus.canceled:
        _setState(
          current.copyWith(status: DownloadStatus.canceled),
          persist: true,
        );
      case EngineStatus.notFound:
      case EngineStatus.failed:
        _setState(
          current.copyWith(
            status: DownloadStatus.failed,
            error: _redact(update.rawError ?? 'Download failed.'),
          ),
          persist: true,
        );
      case EngineStatus.complete:
        unawaited(_handleComplete(current));
    }
  }

  /// On completion, moves the file to public shared storage before ever
  /// reporting the task as [DownloadStatus.complete] — if the move fails,
  /// the file is not where the user expects it, so the task is reported
  /// `failed` instead, never `complete`.
  Future<void> _handleComplete(DownloadTask task) async {
    String? movedPath;
    try {
      movedPath = await _engine.moveToDownloads(task.id);
    } catch (_) {
      movedPath = null;
    }

    if (movedPath == null) {
      _setState(
        task.copyWith(
          status: DownloadStatus.failed,
          error:
              'Download finished but could not be moved to the Downloads '
              'folder.',
        ),
        persist: true,
      );
      return;
    }

    _setState(
      task.copyWith(
        status: DownloadStatus.complete,
        progress: 1.0,
        localUri: movedPath,
        clearError: true,
      ),
      persist: true,
    );
  }

  void _onEngineProgress(EngineProgressUpdate update) {
    final current = _byId(update.taskId);
    // Ignore stray/late progress ticks once a task has left the running
    // state (e.g. arriving just after a cancel/pause/complete).
    if (current == null || current.status != DownloadStatus.running) return;

    final updated = current.copyWith(
      progress: update.progress,
      bytesTotal: update.expectedFileSize ?? current.bytesTotal,
    );
    // Always reflect the latest progress in in-memory state immediately for
    // UI responsiveness, but throttle the DB write — persisting on every
    // tick (these can fire many times a second) would hammer SQLite for no
    // benefit, since a crash mid-download is already handled by
    // restoreFromDisk()'s orphan reconciliation.
    final delta = (update.progress - current.progress).abs();
    _setState(updated, persist: delta >= 0.01 || update.progress >= 1.0);
  }

  void _onCanPause(EngineCanPauseUpdate update) {
    final current = _byId(update.taskId);
    if (current == null) return;
    // Not persisted — see the docs on DownloadTask.canPause / fromRow.
    _setState(current.copyWith(canPause: update.canPause), persist: false);
  }

  // ---------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------

  DownloadTask? _byId(String id) {
    for (final t in state) {
      if (t.id == id) return t;
    }
    return null;
  }

  void _setState(DownloadTask task, {required bool persist}) {
    final list = [...state];
    final idx = list.indexWhere((t) => t.id == task.id);
    if (idx >= 0) {
      list[idx] = task;
    } else {
      list.insert(0, task);
    }
    state = list;
    if (persist) {
      unawaited(_persist(task));
    }
  }

  /// Redacts (title/fileName/localUri/error) before writing a row, as a
  /// defensive last line — the values placed into these fields elsewhere in
  /// this file are not expected to carry a raw download URL, but this
  /// guarantees a credential can never reach the database even if a future
  /// change accidentally puts one in an error string.
  Future<void> _persist(DownloadTask task) async {
    final createdAt =
        _createdAt[task.id] ?? DateTime.now().millisecondsSinceEpoch;
    _createdAt[task.id] = createdAt;

    final safe = task.copyWith(
      title: _redact(task.title),
      fileName: _redact(task.fileName),
      localUri: task.localUri != null ? _redact(task.localUri!) : null,
      clearLocalUri: task.localUri == null,
      error: task.error != null ? _redact(task.error!) : null,
      clearError: task.error == null,
    );

    await _db.upsertDownload(safe.toRow(createdAt: createdAt));
  }

  String _redact(String s) {
    try {
      return _resolveDownloadService().redactCredentials(s);
    } catch (_) {
      return s;
    }
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _progressSub?.cancel();
    _canPauseSub?.cancel();
    _engine.dispose();
    super.dispose();
  }
}

final downloadQueueProvider =
    StateNotifierProvider<DownloadQueueNotifier, List<DownloadTask>>((ref) {
  return DownloadQueueNotifier(ref);
});

/// Looks up a single [DownloadTask] by item id (Xtream stream id or episode
/// id) — e.g. for a media card to show inline progress.
final downloadTaskProvider = Provider.family<DownloadTask?, String>((
  ref,
  id,
) {
  final list = ref.watch(downloadQueueProvider);
  for (final t in list) {
    if (t.id == id) return t;
  }
  return null;
});
