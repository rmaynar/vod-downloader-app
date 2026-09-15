/// Data model for a single queued/in-progress/finished download.
///
/// This is the frozen contract shared with the Downloads screen and the
/// media-card progress UI (built by other agents in parallel) — do not
/// rename fields or change their types without re-syncing with both.
library;

/// Lifecycle states a [DownloadTask] can be in.
enum DownloadStatus { queued, running, paused, complete, failed, canceled }

/// Immutable snapshot of one download's state, independent of the
/// underlying download engine (`background_downloader`) — see
/// `download_engine.dart` for the seam between this model and the real
/// plugin.
class DownloadTask {
  /// Xtream stream id (movie) or episode id. This doubles as the
  /// underlying download engine's task id (see `download_engine.dart`), and
  /// as the lookup key used by `downloadQueueProvider`/`downloadTaskProvider`.
  final String id;

  final String sourceId;

  /// Display title (movie name, or "{series} S01E02 - {title}" for
  /// episodes).
  final String title;

  /// Sanitised on-disk file name, with extension.
  final String fileName;

  final DownloadStatus status;

  /// 0.0 - 1.0. Not meaningful (left at its last value) once [status] is a
  /// terminal state other than [DownloadStatus.complete] (which is always
  /// 1.0).
  final double progress;

  /// Total file size in bytes, once known. May remain null for a while
  /// after a download starts — the server doesn't always report
  /// Content-Length immediately.
  final int? bytesTotal;

  /// Path/URI of the file once it has been moved to public shared storage.
  /// Only ever set together with [DownloadStatus.complete] — see
  /// `download_queue_provider.dart`'s handling of a failed
  /// `moveToSharedStorage` call.
  final String? localUri;

  /// Human-readable, credential-redacted error message. Only meaningful
  /// when [status] is [DownloadStatus.failed].
  final String? error;

  /// Whether this task can currently be paused. Derived at runtime from
  /// `FileDownloader().taskCanResume()`, captured once the task starts
  /// running — see the "CRITICAL TRAP" note in `download_engine.dart`.
  /// Defaults to `true` (optimistic) until the engine reports otherwise, so
  /// the UI briefly shows a pause affordance for a queued task; it flips to
  /// `false` quickly for non-Range servers once the download starts.
  final bool canPause;

  const DownloadTask({
    required this.id,
    required this.sourceId,
    required this.title,
    required this.fileName,
    this.status = DownloadStatus.queued,
    this.progress = 0.0,
    this.bytesTotal,
    this.localUri,
    this.error,
    this.canPause = true,
  });

  DownloadTask copyWith({
    String? id,
    String? sourceId,
    String? title,
    String? fileName,
    DownloadStatus? status,
    double? progress,
    int? bytesTotal,
    bool clearBytesTotal = false,
    String? localUri,
    bool clearLocalUri = false,
    String? error,
    bool clearError = false,
    bool? canPause,
  }) {
    return DownloadTask(
      id: id ?? this.id,
      sourceId: sourceId ?? this.sourceId,
      title: title ?? this.title,
      fileName: fileName ?? this.fileName,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      bytesTotal: clearBytesTotal ? null : (bytesTotal ?? this.bytesTotal),
      localUri: clearLocalUri ? null : (localUri ?? this.localUri),
      error: clearError ? null : (error ?? this.error),
      canPause: canPause ?? this.canPause,
    );
  }

  /// True for a state no further engine update will move out of on its own
  /// (barring an explicit user action like retry).
  bool get isTerminal =>
      status == DownloadStatus.complete ||
      status == DownloadStatus.failed ||
      status == DownloadStatus.canceled;

  /// True for a state that counts as "already in the queue" for the
  /// purposes of idempotent enqueue.
  bool get isActive =>
      status == DownloadStatus.queued ||
      status == DownloadStatus.running ||
      status == DownloadStatus.paused;

  static DownloadStatus statusFromName(String? name) {
    for (final s in DownloadStatus.values) {
      if (s.name == name) return s;
    }
    // Unknown/corrupt status string: fail closed rather than leaving a row
    // stuck claiming to be queued/running forever.
    return DownloadStatus.failed;
  }

  /// Builds the row persisted via `DatabaseService.upsertDownload`. Matches
  /// the `downloads` table's fixed column set exactly — see
  /// `database_service.dart` (not owned by this feature).
  Map<String, dynamic> toRow({required int createdAt}) {
    return {
      'id': id,
      'sourceId': sourceId,
      'title': title,
      'fileName': fileName,
      'status': status.name,
      'progress': progress,
      'bytesTotal': bytesTotal,
      'localUri': localUri,
      'error': error,
      'createdAt': createdAt,
    };
  }

  /// Rehydrates a [DownloadTask] from a `downloads` table row. [canPause]
  /// is not a persisted column (see `download_queue_provider.dart`'s report
  /// on why) — it always starts `true` on restore and is corrected once the
  /// engine reports back for any task that resumes running.
  factory DownloadTask.fromRow(Map<String, dynamic> row) {
    return DownloadTask(
      id: row['id'] as String,
      sourceId: row['sourceId']?.toString() ?? '',
      title: row['title']?.toString() ?? '',
      fileName: row['fileName']?.toString() ?? '',
      status: statusFromName(row['status'] as String?),
      progress: (row['progress'] as num?)?.toDouble() ?? 0.0,
      bytesTotal: (row['bytesTotal'] as num?)?.toInt(),
      localUri: row['localUri'] as String?,
      error: row['error'] as String?,
    );
  }

  @override
  String toString() =>
      'DownloadTask(id: $id, status: $status, progress: $progress)';
}
