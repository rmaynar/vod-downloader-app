import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/models/media_item.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../downloads/download_queue_provider.dart';
import '../../../downloads/download_task.dart';
import 'fallback_poster.dart';

class MediaCard extends ConsumerStatefulWidget {
  final MediaItem item;
  final MediaType? type;
  final void Function(MediaItem item)? onClick;

  const MediaCard({
    super.key,
    required this.item,
    this.type,
    this.onClick,
  });

  @override
  ConsumerState<MediaCard> createState() => _MediaCardState();
}

class _MediaCardState extends ConsumerState<MediaCard> {
  bool _isHovered = false;

  void _handleDownloadTap(DownloadTask? task) {
    final resolvedType = widget.type ?? widget.item.type;

    if (resolvedType == MediaType.series) {
      // For TV series, open details modal so user can pick episodes
      widget.onClick?.call(widget.item);
      return;
    }

    if (task != null && task.status == DownloadStatus.failed) {
      ref.read(downloadQueueProvider.notifier).retry(task.id);
      return;
    }

    if (task != null) {
      // Already queued/running/complete — tapping again does nothing.
      return;
    }

    ref.read(downloadQueueProvider.notifier).enqueueMovie(item: widget.item);
  }

  Color _downloadBgColor(DownloadStatus? status) {
    switch (status) {
      case DownloadStatus.complete:
        return AppColors.emerald;
      case DownloadStatus.failed:
        return AppColors.red;
      case DownloadStatus.running:
      case DownloadStatus.queued:
      case DownloadStatus.paused:
        return AppColors.primary;
      case DownloadStatus.canceled:
      case null:
        return Colors.black.withValues(alpha: 0.78);
    }
  }

  Color _downloadBorderColor(DownloadStatus? status) {
    switch (status) {
      case DownloadStatus.complete:
        return AppColors.emerald;
      case DownloadStatus.failed:
        return AppColors.red;
      case DownloadStatus.running:
      case DownloadStatus.queued:
      case DownloadStatus.paused:
        return AppColors.primary;
      case DownloadStatus.canceled:
      case null:
        return Colors.white.withValues(alpha: 0.25);
    }
  }

  /// Icon/indicator for the current download state. `running` renders a
  /// real determinate ring driven by [DownloadTask.progress] — never an
  /// indeterminate spinner, since these are multi-GB files and a spinner
  /// tells the user nothing about how far along they are.
  Widget _buildDownloadIcon(DownloadTask? task) {
    switch (task?.status) {
      case DownloadStatus.queued:
        return const Icon(
          Icons.schedule_rounded,
          key: ValueKey('queued'),
          color: AppColors.textLight,
          size: 16,
        );
      case DownloadStatus.running:
        return SizedBox(
          key: const ValueKey('running'),
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            value: task!.progress.clamp(0.0, 1.0),
            strokeWidth: 2.4,
            color: Colors.white,
            backgroundColor: Colors.white.withValues(alpha: 0.2),
          ),
        );
      case DownloadStatus.paused:
        return const Icon(
          Icons.pause_rounded,
          key: ValueKey('paused'),
          color: Colors.white,
          size: 18,
        );
      case DownloadStatus.complete:
        return const Icon(
          Icons.check_rounded,
          key: ValueKey('check'),
          color: Colors.white,
          size: 18,
        );
      case DownloadStatus.failed:
        return const Icon(
          Icons.refresh_rounded,
          key: ValueKey('failed'),
          color: Colors.white,
          size: 18,
        );
      case DownloadStatus.canceled:
      case null:
        return const Icon(
          Icons.download_rounded,
          key: ValueKey('download'),
          color: AppColors.textLight,
          size: 18,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final downloadTask = ref.watch(downloadTaskProvider(widget.item.id));

    final resolvedType = widget.type ?? widget.item.type;
    final formattedRating = widget.item.formattedRating;
    final year = widget.item.extractedYear;
    final title = widget.item.name;
    final category = widget.item.categoryName ??
        (resolvedType == MediaType.series ? 'TV Series' : 'Movie');
    final posterUrl = widget.item.posterUrl;

    return MouseRegion(
      cursor: widget.onClick != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        scale: _isHovered ? 1.03 : 1.0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _isHovered ? AppColors.primary : AppColors.border,
              width: 1.2,
            ),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: widget.onClick != null ? () => widget.onClick!(widget.item) : null,
              borderRadius: BorderRadius.circular(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 2:3 Aspect Ratio Poster Container
                  AspectRatio(
                    aspectRatio: 2 / 3,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(8.8)),
                          child: posterUrl != null && posterUrl.trim().isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: posterUrl,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => Container(
                                    color: AppColors.surfaceLight,
                                    child: const Center(
                                      child: SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ),
                                  ),
                                  errorWidget: (context, url, error) => const FallbackPoster(),
                                )
                              : const FallbackPoster(),
                        ),

                        // Top Badges (Type, Year, Rating)
                        Positioned(
                          top: 8,
                          left: 8,
                          right: 8,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Left Badges: Type & Year
                              Flexible(
                                child: Wrap(
                                  spacing: 4,
                                  runSpacing: 4,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.78),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: Colors.white.withValues(alpha: 0.12),
                                          width: 1,
                                        ),
                                      ),
                                      child: Text(
                                        resolvedType == MediaType.series ? 'TV' : 'MOVIE',
                                        style: const TextStyle(
                                          color: AppColors.textLight,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                    if (year != null && year.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.78),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(
                                            color: Colors.white.withValues(alpha: 0.12),
                                            width: 1,
                                          ),
                                        ),
                                        child: Text(
                                          year,
                                          style: const TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),

                              // Rating Badge
                              if (formattedRating != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.85),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: AppColors.amber.withValues(alpha: 0.35),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.star_rounded,
                                        color: AppColors.amber,
                                        size: 13,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        formattedRating,
                                        style: const TextStyle(
                                          color: AppColors.amber,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),

                        // Bottom-Right Download Button
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: Tooltip(
                            message: downloadTask?.status == DownloadStatus.failed
                                ? (downloadTask?.error ?? 'Download failed — tap to retry')
                                : '',
                            child: GestureDetector(
                              onTap: () => _handleDownloadTap(downloadTask),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _downloadBgColor(downloadTask?.status),
                                  border: Border.all(
                                    color: _downloadBorderColor(downloadTask?.status),
                                    width: 1.2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _downloadBgColor(downloadTask?.status)
                                          .withValues(alpha: 0.4),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 150),
                                    child: _buildDownloadIcon(downloadTask),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Title and Category/Rating bottom info
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Line-clamped title (2 lines) with hover color transition
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _isHovered ? AppColors.primary : AppColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                            ),
                          ),

                          // Bottom metadata row
                          Container(
                            padding: const EdgeInsets.only(top: 4),
                            decoration: const BoxDecoration(
                              border: Border(
                                top: BorderSide(
                                  color: Color(0x3327272A),
                                  width: 1,
                                ),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    category,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                if (formattedRating != null) ...[
                                  const SizedBox(width: 4),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.star_rounded,
                                        color: AppColors.amber,
                                        size: 12,
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                        formattedRating,
                                        style: const TextStyle(
                                          color: AppColors.amber,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
