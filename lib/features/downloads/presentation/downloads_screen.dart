import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../download_queue_provider.dart';
import '../download_task.dart';

/// Queue of movies and TV episodes being downloaded from the active Xtream
/// provider. Active transfers (queued/running/paused) are shown above
/// finished ones (complete/failed/canceled).
///
/// Per-item controls are driven strictly by [DownloadTask.status] and
/// [DownloadTask.canPause] — see [_DownloadActions] for the one rule that
/// matters most here: a task that cannot be paused must never show a pause
/// button, because pausing a non-resumable transfer destroys it outright.
class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  bool _isFinished(DownloadStatus status) =>
      status == DownloadStatus.complete ||
      status == DownloadStatus.failed ||
      status == DownloadStatus.canceled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(downloadQueueProvider);
    final notifier = ref.read(downloadQueueProvider.notifier);

    final active = tasks.where((t) => !_isFinished(t.status)).toList();
    final finished = tasks.where((t) => _isFinished(t.status)).toList();
    final hasFinished = finished.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Downloads'),
        actions: [
          IconButton(
            tooltip: hasFinished
                ? 'Clear completed downloads'
                : 'No completed downloads to clear',
            onPressed: hasFinished ? () => notifier.clearCompleted() : null,
            icon: const Icon(Icons.clear_all_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: tasks.isEmpty
            ? const _EmptyQueueState()
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  if (active.isNotEmpty) ...[
                    const _SectionHeader(
                      icon: Icons.downloading_rounded,
                      label: 'In progress',
                    ),
                    const SizedBox(height: 10),
                    for (final task in active)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _DownloadCard(task: task, notifier: notifier),
                      ),
                    const SizedBox(height: 8),
                  ],
                  if (finished.isNotEmpty) ...[
                    const _SectionHeader(
                      icon: Icons.history_rounded,
                      label: 'Finished',
                    ),
                    const SizedBox(height: 10),
                    for (final task in finished)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _DownloadCard(task: task, notifier: notifier),
                      ),
                  ],
                  const SizedBox(height: 8),
                  const _StorageLocationHint(),
                ],
              ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: AppColors.textMuted),
        const SizedBox(width: 6),
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}

/// Reminds the user where finished downloads live on disk. Completed files
/// are moved to the public Downloads folder so they survive an app
/// uninstall and are visible to other apps (file managers, media players).
class _StorageLocationHint extends StatelessWidget {
  const _StorageLocationHint();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.folder_outlined, size: 14, color: AppColors.textDim),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Completed downloads are saved to the public Download folder '
              '(/storage/emulated/0/Download), so you can find them from '
              'other apps too.',
              style: const TextStyle(
                color: AppColors.textDim,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyQueueState extends StatelessWidget {
  const _EmptyQueueState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.indigo.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.indigo.withValues(alpha: 0.3)),
              ),
              child: const Icon(
                Icons.download_rounded,
                color: AppColors.indigoLight,
                size: 32,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'No downloads yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Downloads you start from a movie or episode\'s download '
              'button will show up here, with progress while they run and '
              'the finished file afterwards.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DownloadCard extends StatelessWidget {
  final DownloadTask task;
  final DownloadQueueNotifier notifier;

  const _DownloadCard({required this.task, required this.notifier});

  static const Map<DownloadStatus, ({IconData icon, Color color, String label})>
      _statusMeta = {
    DownloadStatus.queued: (
      icon: Icons.schedule_rounded,
      color: AppColors.textMuted,
      label: 'Queued',
    ),
    DownloadStatus.running: (
      icon: Icons.downloading_rounded,
      color: AppColors.indigoLight,
      label: 'Downloading',
    ),
    DownloadStatus.paused: (
      icon: Icons.pause_circle_outline_rounded,
      color: AppColors.warning,
      label: 'Paused',
    ),
    DownloadStatus.complete: (
      icon: Icons.check_circle_outline_rounded,
      color: AppColors.success,
      label: 'Complete',
    ),
    DownloadStatus.failed: (
      icon: Icons.error_outline_rounded,
      color: AppColors.error,
      label: 'Failed',
    ),
    DownloadStatus.canceled: (
      icon: Icons.cancel_outlined,
      color: AppColors.textMuted,
      label: 'Canceled',
    ),
  };

  Future<void> _openFile(BuildContext context) async {
    final uriString = task.localUri;
    if (uriString == null || uriString.isEmpty) {
      _showSnack(
        context,
        'This file\'s location is no longer known.',
        isError: true,
      );
      return;
    }

    // localUri may already be a proper URI (file://, content://) or a bare
    // filesystem path, depending on how the queue records it once the file
    // is moved to public storage — handle both.
    final parsed = Uri.tryParse(uriString);
    final target = (parsed != null && parsed.scheme.isNotEmpty)
        ? parsed
        : Uri.file(uriString);

    bool opened = false;
    Object? failure;
    try {
      opened = await launchUrl(target, mode: LaunchMode.externalApplication);
    } catch (e) {
      failure = e;
    }

    if (!context.mounted) return;

    if (!opened) {
      // The most common cause: the user (or another app) deleted or moved
      // the file after it finished downloading.
      _showSnack(
        context,
        failure != null
            ? 'Could not open this file. It may have been deleted or moved.'
            : 'No app found to open this file.',
        isError: true,
      );
    }
  }

  void _showSnack(BuildContext context, String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.info,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final meta = _statusMeta[task.status]!;
    final isInFlight = task.status == DownloadStatus.running ||
        task.status == DownloadStatus.queued ||
        task.status == DownloadStatus.paused;
    final percent = (task.progress.clamp(0.0, 1.0) * 100).round();
    final sizeLabel =
        task.bytesTotal != null ? _formatBytes(task.bytesTotal!) : null;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: meta.color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: meta.color.withValues(alpha: 0.35)),
                ),
                child: Icon(meta.icon, size: 18, color: meta.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      task.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textDim,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Status row: label + percentage/size, with a progress bar for
          // active transfers.
          Row(
            children: [
              Text(
                meta.label,
                style: TextStyle(
                  color: meta.color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (isInFlight) ...[
                const SizedBox(width: 8),
                Text(
                  '$percent%',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
              if (sizeLabel != null) ...[
                const Text(
                  ' • ',
                  style: TextStyle(color: AppColors.textDim, fontSize: 12),
                ),
                Flexible(
                  child: Text(
                    sizeLabel,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),

          if (isInFlight) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: task.status == DownloadStatus.queued
                    ? null
                    : task.progress.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: AppColors.surface,
                valueColor: AlwaysStoppedAnimation<Color>(meta.color),
              ),
            ),
          ],

          // The queue already redacts provider credentials out of any
          // stored error text — this screen never displays a raw URL on
          // top of that.
          if (task.status == DownloadStatus.failed && task.error != null) ...[
            const SizedBox(height: 8),
            Text(
              task.error!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.errorLight,
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ],

          const SizedBox(height: 10),
          _DownloadActions(
            task: task,
            notifier: notifier,
            onOpen: () => _openFile(context),
          ),
        ],
      ),
    );
  }
}

/// Renders exactly the actions valid for [task.status]. See the class doc
/// on [DownloadsScreen] for why `canPause == false` must hide (not merely
/// disable) the pause control.
class _DownloadActions extends StatelessWidget {
  final DownloadTask task;
  final DownloadQueueNotifier notifier;
  final VoidCallback onOpen;

  const _DownloadActions({
    required this.task,
    required this.notifier,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[];

    switch (task.status) {
      case DownloadStatus.running:
        if (task.canPause) {
          buttons.add(_ActionButton(
            icon: Icons.pause_rounded,
            label: 'Pause',
            onPressed: () => notifier.pause(task.id),
          ));
        } else {
          // No pause control at all — this CDN doesn't support resumable
          // (HTTP Range) transfers, so pausing would silently destroy the
          // download. Surface why, rather than just omitting it silently.
          buttons.add(
            const Tooltip(
              message:
                  "Can't be paused — this source doesn't support resuming, "
                  'so pausing would lose progress.',
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: AppColors.textDim,
                ),
              ),
            ),
          );
        }
        buttons.add(_ActionButton(
          icon: Icons.close_rounded,
          label: 'Cancel',
          isDestructive: true,
          onPressed: () => notifier.cancel(task.id),
        ));
        break;

      case DownloadStatus.queued:
        buttons.add(_ActionButton(
          icon: Icons.close_rounded,
          label: 'Cancel',
          isDestructive: true,
          onPressed: () => notifier.cancel(task.id),
        ));
        break;

      case DownloadStatus.paused:
        buttons.add(_ActionButton(
          icon: Icons.play_arrow_rounded,
          label: 'Resume',
          onPressed: () => notifier.resume(task.id),
        ));
        buttons.add(_ActionButton(
          icon: Icons.close_rounded,
          label: 'Cancel',
          isDestructive: true,
          onPressed: () => notifier.cancel(task.id),
        ));
        break;

      case DownloadStatus.failed:
        buttons.add(_ActionButton(
          icon: Icons.refresh_rounded,
          label: 'Retry',
          onPressed: () => notifier.retry(task.id),
        ));
        buttons.add(_ActionButton(
          icon: Icons.delete_outline_rounded,
          label: 'Dismiss',
          onPressed: () => notifier.cancel(task.id),
        ));
        break;

      case DownloadStatus.complete:
        buttons.add(_ActionButton(
          icon: Icons.open_in_new_rounded,
          label: 'Open',
          onPressed: onOpen,
        ));
        buttons.add(_ActionButton(
          icon: Icons.delete_outline_rounded,
          label: 'Dismiss',
          onPressed: () => notifier.cancel(task.id),
        ));
        break;

      case DownloadStatus.canceled:
        buttons.add(_ActionButton(
          icon: Icons.delete_outline_rounded,
          label: 'Dismiss',
          onPressed: () => notifier.cancel(task.id),
        ));
        break;
    }

    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 6,
      children: buttons,
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool isDestructive;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? AppColors.errorLight : AppColors.indigoLight;
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.4)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

/// Formats a byte count in the largest sensible readable unit
/// (e.g. `1.2 GB`, `340 MB`, `512 KB`) rather than showing a raw integer.
String _formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var unitIndex = 0;
  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex++;
  }
  final decimals = unitIndex == 0 ? 0 : (size < 10 ? 2 : 1);
  return '${size.toStringAsFixed(decimals)} ${units[unitIndex]}';
}
