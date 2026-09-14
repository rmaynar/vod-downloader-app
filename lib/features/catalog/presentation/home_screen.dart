import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/models/media_item.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/catalog_provider.dart';
import 'widgets/media_card.dart';
import 'widgets/media_details_modal.dart';

class HomeScreen extends ConsumerStatefulWidget {
  final VoidCallback? onNavigateToMovies;
  final VoidCallback? onNavigateToSeries;

  const HomeScreen({
    super.key,
    this.onNavigateToMovies,
    this.onNavigateToSeries,
  });

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with SingleTickerProviderStateMixin {
  late AnimationController _syncAnimationController;

  @override
  void initState() {
    super.initState();
    _syncAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
  }

  @override
  void dispose() {
    _syncAnimationController.dispose();
    super.dispose();
  }

  void _navigateToMovies() {
    if (widget.onNavigateToMovies != null) {
      widget.onNavigateToMovies!();
      return;
    }
    try {
      context.push('/movies');
    } catch (_) {
      try {
        context.go('/movies');
      } catch (_) {}
    }
  }

  void _navigateToSeries() {
    if (widget.onNavigateToSeries != null) {
      widget.onNavigateToSeries!();
      return;
    }
    try {
      context.push('/series');
    } catch (_) {
      try {
        context.go('/series');
      } catch (_) {}
    }
  }

  void _openDetails(MediaItem item, MediaType type) {
    MediaDetailsModal.show(context, item, type: type);
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider);

    if (catalog.isSyncing) {
      if (!_syncAnimationController.isAnimating) {
        _syncAnimationController.repeat();
      }
    } else {
      if (_syncAnimationController.isAnimating) {
        _syncAnimationController.stop();
        _syncAnimationController.reset();
      }
    }

    // Top rated movies (up to 6)
    final topMovies = [...catalog.movies]
        .where((m) => m.numericRating > 0)
        .toList()
      ..sort((a, b) {
        final cmp = b.numericRating.compareTo(a.numericRating);
        if (cmp != 0) return cmp;
        return a.name.compareTo(b.name);
      });
    final top6Movies = topMovies.take(6).toList();

    // Top rated series (up to 6)
    final topSeries = [...catalog.series]
        .where((s) => s.numericRating > 0)
        .toList()
      ..sort((a, b) {
        final cmp = b.numericRating.compareTo(a.numericRating);
        if (cmp != 0) return cmp;
        return a.name.compareTo(b.name);
      });
    final top6Series = topSeries.take(6).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1280),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Hero Banner
                    _buildHeroBanner(
                      moviesCount: catalog.moviesCount,
                      seriesCount: catalog.seriesCount,
                    ),

                    const SizedBox(height: 28),

                    // Stats Cards Row
                    _buildStatsCards(
                      catalog: catalog,
                      isSyncing: catalog.isSyncing,
                    ),

                    const SizedBox(height: 36),

                    // Top Rated Movies Section
                    if (top6Movies.isNotEmpty) ...[
                      _buildSectionHeader(
                        title: 'Top Rated Movies',
                        icon: Icons.star_rounded,
                        iconColor: AppColors.amber,
                        onViewAll: _navigateToMovies,
                      ),
                      const SizedBox(height: 16),
                      _buildMediaGrid(
                        items: top6Movies,
                        type: MediaType.movie,
                      ),
                      const SizedBox(height: 36),
                    ],

                    // Top Rated Series Section
                    if (top6Series.isNotEmpty) ...[
                      _buildSectionHeader(
                        title: 'Top Rated Series',
                        icon: Icons.tv_rounded,
                        iconColor: AppColors.secondary,
                        onViewAll: _navigateToSeries,
                      ),
                      const SizedBox(height: 16),
                      _buildMediaGrid(
                        items: top6Series,
                        type: MediaType.series,
                      ),
                      const SizedBox(height: 36),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeroBanner({required int moviesCount, required int seriesCount}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0x991E1B4B),
            Color(0xFF12121A),
            Color(0x663B0764),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tag Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome_rounded, size: 14, color: AppColors.primary),
                SizedBox(width: 6),
                Text(
                  'High-Performance Local Catalog',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Main Headline
          RichText(
            text: const TextSpan(
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -0.5,
                height: 1.2,
              ),
              children: [
                TextSpan(text: 'Explore Your '),
                TextSpan(
                  text: 'VOD Downloader',
                  style: TextStyle(color: Color(0xFF818CF8)),
                ),
                TextSpan(text: ' Library'),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Subtitle
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: const Text(
              'Instant client-side browsing powered by local cache. Search thousands of movies and TV series with zero latency and smooth infinite scrolling.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Quick Action Buttons
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ElevatedButton.icon(
                onPressed: _navigateToMovies,
                icon: const Icon(Icons.movie_outlined, size: 18, color: Colors.white),
                label: Text(
                  'Browse Movies (${moviesCount.toString()})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 4,
                  shadowColor: AppColors.primary.withValues(alpha: 0.4),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _navigateToSeries,
                icon: const Icon(Icons.tv_rounded, size: 18, color: AppColors.textLight),
                label: Text(
                  'Browse TV Shows (${seriesCount.toString()})',
                  style: const TextStyle(
                    color: AppColors.textLight,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A1A25),
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCards({
    required CatalogState catalog,
    required bool isSyncing,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 720;

        final cards = [
          // 1. Movies In Cache
          _buildStatCard(
            icon: Icons.movie_outlined,
            iconColor: AppColors.primary,
            iconBg: AppColors.primary.withValues(alpha: 0.12),
            title: 'MOVIES IN CACHE',
            value: catalog.isLoading && catalog.movies.isEmpty
                ? '...'
                : catalog.moviesCount.toString(),
          ),

          // 2. TV Series In Cache
          _buildStatCard(
            icon: Icons.tv_rounded,
            iconColor: AppColors.secondary,
            iconBg: AppColors.secondary.withValues(alpha: 0.12),
            title: 'TV SERIES IN CACHE',
            value: catalog.isLoading && catalog.series.isEmpty
                ? '...'
                : catalog.seriesCount.toString(),
          ),

          // 3. Active Source & Re-sync
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.emerald.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.emerald.withValues(alpha: 0.2)),
                        ),
                        child: const Icon(
                          Icons.layers_outlined,
                          size: 24,
                          color: AppColors.emerald,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'ACTIVE SOURCE',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              catalog.currentSource?.name ??
                                  (catalog.currentSourceId != null
                                      ? 'Source #${catalog.currentSourceId}'
                                      : '—'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  onPressed: isSyncing
                      ? null
                      : () => ref
                          .read(catalogProvider.notifier)
                          .syncCatalog(forceSync: true),
                  tooltip: 'Force refresh catalog',
                  icon: AnimatedBuilder(
                    animation: _syncAnimationController,
                    builder: (context, child) {
                      return Transform.rotate(
                        angle: _syncAnimationController.value * 2 * math.pi,
                        child: child,
                      );
                    },
                    child: Icon(
                      Icons.sync_rounded,
                      color: isSyncing ? AppColors.primary : AppColors.textLight,
                      size: 22,
                    ),
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1A25),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: AppColors.border),
                    ),
                    padding: const EdgeInsets.all(10),
                  ),
                ),
              ],
            ),
          ),
        ];

        if (isNarrow) {
          return Column(
            children: cards
                .map((card) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: card,
                    ))
                .toList(),
          );
        }

        return Row(
          children: cards
              .map((card) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: card,
                    ),
                  ))
              .toList(),
        );
      },
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: iconColor.withValues(alpha: 0.25)),
            ),
            child: Icon(icon, size: 24, color: iconColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onViewAll,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: iconColor),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        InkWell(
          onTap: onViewAll,
          borderRadius: BorderRadius.circular(6),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              children: [
                Text(
                  'View all',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(width: 4),
                Icon(Icons.arrow_forward_rounded, size: 14, color: AppColors.primary),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMediaGrid({
    required List<MediaItem> items,
    required MediaType type,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        int crossAxisCount = 2;
        if (width >= 1100) {
          crossAxisCount = 6;
        } else if (width >= 800) {
          crossAxisCount = 4;
        } else if (width >= 550) {
          crossAxisCount = 3;
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 2 / 3.8,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            return MediaCard(
              item: item,
              type: type,
              onClick: (selected) => _openDetails(selected, type),
            );
          },
        );
      },
    );
  }
}
