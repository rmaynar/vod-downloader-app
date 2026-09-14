import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/category.dart';
import '../../../core/models/media_item.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/catalog_provider.dart';
import 'widgets/catalog_grid.dart';
import 'widgets/media_card.dart';
import 'widgets/media_details_modal.dart';

enum SeriesSortOption {
  nameAsc('name_asc', 'Name (A-Z)'),
  nameDesc('name_desc', 'Name (Z-A)'),
  ratingDesc('rating_desc', 'Rating (High to Low)'),
  ratingAsc('rating_asc', 'Rating (Low to High)');

  final String key;
  final String label;
  const SeriesSortOption(this.key, this.label);
}

class SeriesScreen extends ConsumerStatefulWidget {
  const SeriesScreen({super.key});

  @override
  ConsumerState<SeriesScreen> createState() => _SeriesScreenState();
}

class _SeriesScreenState extends ConsumerState<SeriesScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedCategoryId = 'all';
  SeriesSortOption _sortOption = SeriesSortOption.nameAsc;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      final text = _searchController.text;
      if (text != _searchQuery) {
        setState(() {
          _searchQuery = text;
        });
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openDetails(MediaItem item) {
    MediaDetailsModal.show(context, item, type: MediaType.series);
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider);
    final series = catalog.series;
    final categories = catalog.seriesCategories;

    // Filter & Sort
    final query = _searchQuery.trim().toLowerCase();
    final hasSearch = query.isNotEmpty;
    final hasCategory = _selectedCategoryId != 'all';
    final isFiltered = hasSearch || hasCategory;

    final filteredSeries = series.where((s) {
      if (hasCategory && s.categoryId != _selectedCategoryId) {
        return false;
      }
      if (hasSearch && !s.name.toLowerCase().contains(query)) {
        return false;
      }
      return true;
    }).toList();

    filteredSeries.sort((a, b) {
      switch (_sortOption) {
        case SeriesSortOption.nameAsc:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case SeriesSortOption.nameDesc:
          return b.name.toLowerCase().compareTo(a.name.toLowerCase());
        case SeriesSortOption.ratingDesc:
          final diff = b.numericRating.compareTo(a.numericRating);
          if (diff != 0) return diff;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case SeriesSortOption.ratingAsc:
          final diff = a.numericRating.compareTo(b.numericRating);
          if (diff != 0) return diff;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Header and Pill
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.tv_rounded, size: 28, color: AppColors.primary),
                              SizedBox(width: 10),
                              Text(
                                'TV Shows',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Browse and stream television shows and series',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),

                      // Total Count Pill
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text.rich(
                          TextSpan(
                            style: const TextStyle(fontSize: 12, color: AppColors.textLight),
                            children: [
                              if (isFiltered) ...[
                                const TextSpan(text: 'Filtered: '),
                                TextSpan(
                                  text: '${filteredSeries.length}',
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                TextSpan(text: ' of ${series.length}'),
                              ] else ...[
                                TextSpan(
                                  text: '${series.length}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const TextSpan(text: ' Series'),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Top Filter Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isMobile = constraints.maxWidth < 650;

                        if (isMobile) {
                          return Column(
                            children: [
                              _buildSearchField(),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(child: _buildCategoryDropdown(categories)),
                                  const SizedBox(width: 8),
                                  Expanded(child: _buildSortDropdown()),
                                ],
                              ),
                            ],
                          );
                        }

                        return Row(
                          children: [
                            // Search field
                            Expanded(child: _buildSearchField()),
                            const SizedBox(width: 12),

                            // Category dropdown
                            SizedBox(
                              width: 200,
                              child: _buildCategoryDropdown(categories),
                            ),
                            const SizedBox(width: 12),

                            // Sort dropdown
                            SizedBox(
                              width: 180,
                              child: _buildSortDropdown(),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),

                // Main Catalog Grid
                Expanded(
                  child: CatalogGrid<MediaItem>(
                    items: filteredSeries,
                    isLoading: catalog.isLoading && series.isEmpty,
                    emptyMessage: isFiltered
                        ? 'No TV shows matched your filter criteria'
                        : 'No TV shows found in this catalog',
                    itemBuilder: (context, item, index) {
                      return MediaCard(
                        item: item,
                        type: MediaType.series,
                        onClick: _openDetails,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Search series by title...',
          hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
          prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMuted, size: 18),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppColors.textLight, size: 16),
                  onPressed: () => _searchController.clear(),
                )
              : null,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildCategoryDropdown(List<MediaCategory> categories) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedCategoryId,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textMuted, size: 18),
          dropdownColor: AppColors.surface,
          style: const TextStyle(color: AppColors.textLight, fontSize: 13),
          onChanged: (val) {
            if (val != null) {
              setState(() => _selectedCategoryId = val);
            }
          },
          items: [
            const DropdownMenuItem(
              value: 'all',
              child: Text('All Categories', overflow: TextOverflow.ellipsis),
            ),
            ...categories.map((cat) {
              return DropdownMenuItem(
                value: cat.categoryId,
                child: Text(cat.categoryName, overflow: TextOverflow.ellipsis),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildSortDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<SeriesSortOption>(
          value: _sortOption,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textMuted, size: 18),
          dropdownColor: AppColors.surface,
          style: const TextStyle(color: AppColors.textLight, fontSize: 13),
          onChanged: (val) {
            if (val != null) {
              setState(() => _sortOption = val);
            }
          },
          items: SeriesSortOption.values.map((opt) {
            return DropdownMenuItem(
              value: opt,
              child: Text(opt.label, overflow: TextOverflow.ellipsis),
            );
          }).toList(),
        ),
      ),
    );
  }
}
