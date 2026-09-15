import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/models/media_item.dart';
import '../../../../core/models/series_details.dart';
import '../../../../core/network/xtream_client.dart';
import '../../../../core/providers/xtream_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../downloads/download_queue_provider.dart';
import '../../../downloads/download_task.dart';
import 'fallback_poster.dart';

class MediaDetailsModal extends ConsumerStatefulWidget {
  final MediaItem item;
  final MediaType? type;
  final VoidCallback? onClose;
  final void Function(MediaItem item)? onPlay;

  const MediaDetailsModal({
    super.key,
    required this.item,
    this.type,
    this.onClose,
    this.onPlay,
  });

  static Future<void> show(
    BuildContext context,
    MediaItem item, {
    MediaType? type,
    void Function(MediaItem item)? onPlay,
  }) {
    return showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.8),
      barrierDismissible: true,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: MediaDetailsModal(
            item: item,
            type: type,
            onClose: () => Navigator.of(context).pop(),
            onPlay: onPlay,
          ),
        ),
      ),
    );
  }

  @override
  ConsumerState<MediaDetailsModal> createState() => _MediaDetailsModalState();
}

class _MediaDetailsModalState extends ConsumerState<MediaDetailsModal> {
  SeriesDetails? _seriesDetails;
  bool _isLoadingEpisodes = false;
  String? _episodesError;
  String? _activeSeason;

  @override
  void initState() {
    super.initState();
    _fetchSeriesInfoIfNeeded();
  }

  MediaType get _resolvedType => widget.type ?? widget.item.type;

  Future<void> _fetchSeriesInfoIfNeeded() async {
    if (_resolvedType != MediaType.series) return;

    final xtreamClient = ref.read(xtreamClientProvider);
    if (xtreamClient == null) {
      setState(() {
        _episodesError = 'No active account. Sign in to load episodes.';
      });
      return;
    }

    setState(() {
      _isLoadingEpisodes = true;
      _episodesError = null;
    });

    try {
      final seriesId = widget.item.id;
      final details = await xtreamClient.getSeriesInfo(seriesId);

      if (mounted) {
        setState(() {
          _seriesDetails = details;
          _isLoadingEpisodes = false;
          if (details.seasonNumbers.isNotEmpty) {
            _activeSeason = details.seasonNumbers.first;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingEpisodes = false;
          _episodesError = e is XtreamException
              ? e.message
              : 'Failed to load episode details. Please try again.';
        });
      }
    }
  }

  void _handleDownloadMovie(DownloadTask? task) {
    if (task != null && task.status == DownloadStatus.failed) {
      ref.read(downloadQueueProvider.notifier).retry(task.id);
      return;
    }
    if (task != null && task.status == DownloadStatus.queued) {
      ref.read(downloadQueueProvider.notifier).cancel(task.id);
      return;
    }
    // If it's running, paused, or complete, do nothing.
    // If it's canceled, fall through to re-enqueue.
    if (task != null && task.status != DownloadStatus.canceled) return;

    ref.read(downloadQueueProvider.notifier).enqueueMovie(item: widget.item);
  }

  void _handleDownloadEpisode(EpisodeItem episode, DownloadTask? task) {
    if (task != null && task.status == DownloadStatus.failed) {
      ref.read(downloadQueueProvider.notifier).retry(task.id);
      return;
    }
    if (task != null && task.status == DownloadStatus.queued) {
      ref.read(downloadQueueProvider.notifier).cancel(task.id);
      return;
    }
    if (task != null && task.status != DownloadStatus.canceled) return;

    ref.read(downloadQueueProvider.notifier).enqueueEpisode(
          episode: episode,
          seriesName: widget.item.name,
          seasonNum: _activeSeason,
        );
  }

  // --- Shared download-status styling for the movie button and per-episode
  // chips below. Renders real queue state — queued/running (determinate,
  // driven by task.progress — never a spinner)/complete/failed — instead of
  // the old fixed-timer fake-success state.

  Color _downloadButtonColor(DownloadStatus? status) {
    switch (status) {
      case DownloadStatus.complete:
        return AppColors.emerald;
      case DownloadStatus.failed:
        return AppColors.red.withValues(alpha: 0.15);
      case DownloadStatus.running:
      case DownloadStatus.queued:
      case DownloadStatus.paused:
        return AppColors.primary;
      case DownloadStatus.canceled:
      case null:
        return AppColors.surfaceElevated;
    }
  }

  Color _downloadButtonBorderColor(DownloadStatus? status) {
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
        return AppColors.borderLight;
    }
  }

  Color _downloadButtonTextColor(DownloadStatus? status) {
    switch (status) {
      case DownloadStatus.failed:
        return AppColors.red;
      case DownloadStatus.canceled:
      case null:
        return AppColors.textLight;
      case DownloadStatus.complete:
      case DownloadStatus.running:
      case DownloadStatus.queued:
      case DownloadStatus.paused:
        return Colors.white;
    }
  }

  Widget _downloadButtonIcon(DownloadTask? task, {required double size}) {
    switch (task?.status) {
      case DownloadStatus.queued:
        return Icon(Icons.schedule_rounded, size: size, color: Colors.white);
      case DownloadStatus.running:
        return SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            value: task!.progress.clamp(0.0, 1.0),
            strokeWidth: 2,
            color: Colors.white,
            backgroundColor: Colors.white.withValues(alpha: 0.25),
          ),
        );
      case DownloadStatus.paused:
        return Icon(Icons.pause_rounded, size: size, color: Colors.white);
      case DownloadStatus.complete:
        return Icon(Icons.check_rounded, size: size, color: Colors.white);
      case DownloadStatus.failed:
        return Icon(Icons.refresh_rounded, size: size, color: AppColors.red);
      case DownloadStatus.canceled:
      case null:
        return Icon(Icons.download_rounded, size: size, color: AppColors.textLight);
    }
  }

  String _downloadButtonLabel(DownloadTask? task) {
    switch (task?.status) {
      case DownloadStatus.queued:
        return 'Queued';
      case DownloadStatus.running:
        return '${(task!.progress.clamp(0.0, 1.0) * 100).round()}%';
      case DownloadStatus.paused:
        return 'Paused';
      case DownloadStatus.complete:
        return 'Downloaded';
      case DownloadStatus.failed:
        return 'Retry';
      case DownloadStatus.canceled:
      case null:
        return 'Download';
    }
  }

  String _movieButtonLabel(DownloadTask? task) {
    switch (task?.status) {
      case DownloadStatus.queued:
        return 'Queued...';
      case DownloadStatus.running:
        return 'Downloading ${(task!.progress.clamp(0.0, 1.0) * 100).round()}%';
      case DownloadStatus.paused:
        return 'Paused';
      case DownloadStatus.complete:
        return 'Downloaded';
      case DownloadStatus.failed:
        return 'Retry Download';
      case DownloadStatus.canceled:
      case null:
        return 'Download Movie';
    }
  }

  @override
  Widget build(BuildContext context) {
    final formattedRating = widget.item.formattedRating;
    final year = widget.item.extractedYear;
    final category = widget.item.categoryName ??
        (_resolvedType == MediaType.series ? 'TV Series' : 'Movie');
    final plot = widget.item.plot;
    final duration = widget.item.duration;
    final genre = widget.item.genre;
    final director = widget.item.director;
    final cast = widget.item.cast;
    final posterUrl = widget.item.posterUrl;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 650;

        return Container(
          width: 860,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.7),
                blurRadius: 28,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Modal Content
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: isMobile
                    ? _buildMobileLayout(
                        posterUrl: posterUrl,
                        year: year,
                        formattedRating: formattedRating,
                        duration: duration,
                        category: category,
                        genre: genre,
                        plot: plot,
                        director: director,
                        cast: cast,
                      )
                    : _buildDesktopLayout(
                        posterUrl: posterUrl,
                        year: year,
                        formattedRating: formattedRating,
                        duration: duration,
                        category: category,
                        genre: genre,
                        plot: plot,
                        director: director,
                        cast: cast,
                      ),
              ),

              // Close Button Top Right
              Positioned(
                top: 12,
                right: 12,
                child: Material(
                  color: Colors.black.withValues(alpha: 0.65),
                  shape: const CircleBorder(
                    side: BorderSide(color: Color(0x33FFFFFF)),
                  ),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: widget.onClose ?? () => Navigator.of(context).pop(),
                    child: const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Icon(
                        Icons.close_rounded,
                        color: AppColors.textLight,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDesktopLayout({
    required String? posterUrl,
    required String? year,
    required String? formattedRating,
    required String? duration,
    required String? category,
    required String? genre,
    required String? plot,
    required String? director,
    required String? cast,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left Column: Poster Image
        SizedBox(
          width: 280,
          child: Stack(
            fit: StackFit.expand,
            children: [
              posterUrl != null && posterUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: posterUrl,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: AppColors.surfaceLight,
                        child: const Center(
                          child: CircularProgressIndicator(color: AppColors.primary),
                        ),
                      ),
                      errorWidget: (context, url, error) => const FallbackPoster(),
                    )
                  : const FallbackPoster(),
              // Gradient edge
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                width: 32,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [Colors.transparent, AppColors.surface],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Right Column: Details & Episodes
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: _buildDetailsContent(
                      year: year,
                      formattedRating: formattedRating,
                      duration: duration,
                      category: category,
                      genre: genre,
                      plot: plot,
                      director: director,
                      cast: cast,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _buildActionFooter(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout({
    required String? posterUrl,
    required String? year,
    required String? formattedRating,
    required String? duration,
    required String? category,
    required String? genre,
    required String? plot,
    required String? director,
    required String? cast,
  }) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: posterUrl != null && posterUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: posterUrl,
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) => const FallbackPoster(),
                        )
                      : const FallbackPoster(),
                ),
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: _buildDetailsContent(
                    year: year,
                    formattedRating: formattedRating,
                    duration: duration,
                    category: category,
                    genre: genre,
                    plot: plot,
                    director: director,
                    cast: cast,
                  ),
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: _buildActionFooter(),
        ),
      ],
    );
  }

  Widget _buildDetailsContent({
    required String? year,
    required String? formattedRating,
    required String? duration,
    required String? category,
    required String? genre,
    required String? plot,
    required String? director,
    required String? cast,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top Badges Row
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            // Media Type Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _resolvedType == MediaType.series
                        ? Icons.tv_rounded
                        : Icons.movie_outlined,
                    size: 14,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _resolvedType == MediaType.series ? 'TV SERIES' : 'MOVIE',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),

            // Release Year Badge
            if (year != null && year.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_today_rounded, size: 12, color: AppColors.textMuted),
                    const SizedBox(width: 5),
                    Text(
                      year,
                      style: const TextStyle(
                        color: AppColors.textLight,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

            // Rating Badge
            if (formattedRating != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.amber.withValues(alpha: 0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_rounded, size: 14, color: AppColors.amber),
                    const SizedBox(width: 4),
                    Text(
                      '$formattedRating / 10',
                      style: const TextStyle(
                        color: AppColors.amber,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),

            // Duration Badge
            if (duration != null && duration.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.access_time_rounded, size: 13, color: AppColors.textMuted),
                    const SizedBox(width: 5),
                    Text(
                      duration,
                      style: const TextStyle(
                        color: AppColors.textLight,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),

        const SizedBox(height: 12),

        // Title
        Text(
          widget.item.name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
        ),

        const SizedBox(height: 8),

        // Category and Genre
        if (category != null || genre != null)
          Row(
            children: [
              if (category != null) ...[
                const Icon(Icons.label_outline_rounded, size: 14, color: AppColors.primary),
                const SizedBox(width: 4),
                Text(
                  category,
                  style: const TextStyle(color: AppColors.textLight, fontSize: 12),
                ),
              ],
              if (category != null && genre != null) ...[
                const SizedBox(width: 8),
                const Text('•', style: TextStyle(color: AppColors.textMuted)),
                const SizedBox(width: 8),
              ],
              if (genre != null)
                Flexible(
                  child: Text(
                    genre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ),
            ],
          ),

        const SizedBox(height: 16),

        // Synopsis
        const Text(
          'SYNOPSIS',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          plot != null && plot.trim().isNotEmpty
              ? plot
              : 'No synopsis available for this title.',
          style: const TextStyle(
            color: AppColors.textLight,
            fontSize: 13,
            height: 1.45,
          ),
        ),

        const SizedBox(height: 16),

        // Director and Cast
        if (director != null || cast != null) ...[
          Container(
            padding: const EdgeInsets.only(top: 12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (director != null && director.isNotEmpty) ...[
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      children: [
                        const TextSpan(
                          text: 'Director: ',
                          style: TextStyle(
                            color: AppColors.textLight,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(text: director),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                if (cast != null && cast.isNotEmpty) ...[
                  RichText(
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      children: [
                        const TextSpan(
                          text: 'Cast: ',
                          style: TextStyle(
                            color: AppColors.textLight,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(text: cast),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // TV Series Episodes Section
        if (_resolvedType == MediaType.series) _buildSeriesEpisodesSection(),
      ],
    );
  }

  Widget _buildSeriesEpisodesSection() {
    final seasons = _seriesDetails?.seasonNumbers ?? [];
    final activeEpisodes = _seriesDetails?.getEpisodes(_activeSeason ?? '') ?? [];

    return Container(
      padding: const EdgeInsets.only(top: 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'EPISODES & DOWNLOADS',
                style: TextStyle(
                  color: AppColors.textLight,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              if (seasons.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${seasons.length} ${seasons.length == 1 ? "Season" : "Seasons"}',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          if (_isLoadingEpisodes)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Loading episode list...',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            )
          else if (_episodesError != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.red.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
              ),
              child: Text(
                _episodesError!,
                style: const TextStyle(color: AppColors.red, fontSize: 12),
              ),
            )
          else if (seasons.isNotEmpty) ...[
            // Season tabs
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final seasonNum in seasons)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: InkWell(
                        onTap: () => setState(() => _activeSeason = seasonNum),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: _activeSeason == seasonNum
                                ? AppColors.primary
                                : AppColors.surfaceLight,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _activeSeason == seasonNum
                                  ? AppColors.primary
                                  : AppColors.border,
                            ),
                          ),
                          child: Text(
                            'Season $seasonNum',
                            style: TextStyle(
                              color: _activeSeason == seasonNum
                                  ? Colors.white
                                  : AppColors.textLight,
                              fontSize: 12,
                              fontWeight: _activeSeason == seasonNum
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Episodes list
            if (activeEpisodes.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    'No episodes found for Season $_activeSeason.',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: activeEpisodes.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final ep = activeEpisodes[index];
                    final epTask = ref.watch(downloadTaskProvider(ep.id));

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 32,
                            child: Text(
                              'E${ep.episodeNum}',
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              ep.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textLight,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          if (ep.duration != null && ep.duration!.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              ep.duration!,
                              style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                          const SizedBox(width: 10),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 108),
                            child: Tooltip(
                              message: epTask?.status == DownloadStatus.failed
                                  ? (epTask?.error ?? 'Download failed — tap to retry')
                                  : '',
                              child: InkWell(
                                onTap: () => _handleDownloadEpisode(ep, epTask),
                                borderRadius: BorderRadius.circular(6),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _downloadButtonColor(epTask?.status),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: _downloadButtonBorderColor(epTask?.status),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _downloadButtonIcon(epTask, size: 13),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          _downloadButtonLabel(epTask),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: _downloadButtonTextColor(epTask?.status),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionFooter() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // Close Button
        OutlinedButton(
          onPressed: widget.onClose ?? () => Navigator.of(context).pop(),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppColors.border),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            backgroundColor: AppColors.surfaceLight,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          child: const Text(
            'Close',
            style: TextStyle(color: AppColors.textLight, fontSize: 13),
          ),
        ),

        // Download Movie Button (for movies)
        if (_resolvedType == MediaType.movie) ...[
          const SizedBox(width: 10),
          Builder(
            builder: (context) {
              final movieTask = ref.watch(downloadTaskProvider(widget.item.id));
              return Tooltip(
                message: movieTask?.status == DownloadStatus.failed
                    ? (movieTask?.error ?? 'Download failed — tap to retry')
                    : '',
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: ElevatedButton.icon(
                    onPressed: () => _handleDownloadMovie(movieTask),
                    icon: _downloadButtonIcon(movieTask, size: 16),
                    label: Text(
                      _movieButtonLabel(movieTask),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: movieTask?.status == DownloadStatus.failed
                            ? AppColors.red
                            : Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _downloadButtonColor(movieTask?.status),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                  ),
                ),
              );
            },
          ),
        ],

        // Optional Play button
        if (widget.onPlay != null) ...[
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: () => widget.onPlay!(widget.item),
            icon: const Icon(Icons.play_arrow_rounded, size: 18, color: Colors.white),
            label: const Text(
              'Play Now',
              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
          ),
        ],
      ],
    );
  }
}
