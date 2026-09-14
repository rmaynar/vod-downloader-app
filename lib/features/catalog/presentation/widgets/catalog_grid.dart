import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

class CatalogGrid<T> extends StatefulWidget {
  final List<T> items;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final bool isLoading;
  final String emptyMessage;
  final int batchSize;
  final ScrollController? scrollController;
  final ScrollPhysics? physics;
  final bool shrinkWrap;
  final EdgeInsetsGeometry? padding;

  const CatalogGrid({
    super.key,
    required this.items,
    required this.itemBuilder,
    this.isLoading = false,
    this.emptyMessage = 'No items found',
    this.batchSize = 50,
    this.scrollController,
    this.physics,
    this.shrinkWrap = false,
    this.padding,
  });

  @override
  State<CatalogGrid<T>> createState() => _CatalogGridState<T>();
}

class _CatalogGridState<T> extends State<CatalogGrid<T>> {
  late int _visibleCount;
  ScrollController? _internalScrollController;

  ScrollController get _effectiveScrollController =>
      widget.scrollController ?? (_internalScrollController ??= ScrollController());

  @override
  void initState() {
    super.initState();
    _visibleCount = widget.batchSize;
    _effectiveScrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant CatalogGrid<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items != oldWidget.items || widget.batchSize != oldWidget.batchSize) {
      _visibleCount = widget.batchSize;
    }
    if (widget.scrollController != oldWidget.scrollController) {
      oldWidget.scrollController?.removeListener(_onScroll);
      _effectiveScrollController.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    _effectiveScrollController.removeListener(_onScroll);
    _internalScrollController?.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!mounted) return;
    if (_visibleCount >= widget.items.length) return;

    if (_effectiveScrollController.position.pixels >=
        _effectiveScrollController.position.maxScrollExtent - 400) {
      setState(() {
        _visibleCount = (_visibleCount + widget.batchSize).clamp(0, widget.items.length);
      });
    }
  }

  int _calculateCrossAxisCount(double width) {
    if (width < 600) {
      return 2; // Mobile phones
    } else if (width < 840) {
      return 3; // Small tablets
    } else if (width < 1100) {
      return 4; // Large tablets / small screens
    } else {
      return 6; // Desktop / landscape
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1. Loading state with empty list
    if (widget.isLoading && widget.items.isEmpty) {
      return _buildLoadingState();
    }

    // 2. Empty state
    if (!widget.isLoading && widget.items.isEmpty) {
      return _buildEmptyState();
    }

    final visibleItems = widget.items.take(_visibleCount).toList();
    final hasMore = _visibleCount < widget.items.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = _calculateCrossAxisCount(constraints.maxWidth);

        return ListView(
          controller: widget.shrinkWrap ? null : _effectiveScrollController,
          physics: widget.physics,
          shrinkWrap: widget.shrinkWrap,
          padding: widget.padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          children: [
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: visibleItems.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                childAspectRatio: 2 / 3.8,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              itemBuilder: (context, index) {
                return widget.itemBuilder(context, visibleItems[index], index);
              },
            ),

            // Bottom Sentinel and Count Indicator Banner
            const SizedBox(height: 24),
            Center(
              child: Column(
                children: [
                  if (hasMore) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Loading more items...',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Text(
                    'Showing ${visibleItems.length} of ${widget.items.length} items',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  if (!hasMore && widget.items.length > widget.batchSize)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'All items loaded',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }

  Widget _buildLoadingState() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = _calculateCrossAxisCount(constraints.maxWidth);
        return GridView.builder(
          shrinkWrap: widget.shrinkWrap,
          physics: widget.physics ?? const AlwaysScrollableScrollPhysics(),
          padding: widget.padding ?? const EdgeInsets.all(16),
          itemCount: 12,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 2 / 3.8,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
          ),
          itemBuilder: (context, index) {
            return Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceLight.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  AspectRatio(
                    aspectRatio: 2 / 3,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(9)),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            height: 12,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            height: 10,
                            width: 80,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        child: Container(
          width: double.infinity,
          constraints: const Duration(seconds: 1) == const Duration(seconds: 1)
              ? const BoxConstraints(maxWidth: 460)
              : null,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.8)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surfaceLight,
                  border: Border.all(color: AppColors.border),
                ),
                child: const Icon(
                  Icons.search_off_rounded,
                  size: 32,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.emptyMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Try adjusting your search query, selecting a different category, or switching sources.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
