import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/category_item.dart';
import '../../../core/models/media_item.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/catalog_provider.dart';
import 'widgets/catalog_grid.dart';
import 'widgets/media_card.dart';
import 'widgets/media_details_modal.dart';

enum MovieSortOption {
  nameAsc('name_asc', 'Name (A-Z)'),
  nameDesc('name_desc', 'Name (Z-A)'),
  ratingDesc('rating_desc', 'Rating (High to Low)'),
  ratingAsc('rating_asc', 'Rating (Low to High)');

  final String key;
  final String label;
  const MovieSortOption(this.key, this.label);
}

class MoviesScreen extends ConsumerStatefulWidget {
  const MoviesScreen({super.key});

  @override
  ConsumerState<MoviesScreen> createState() => _MoviesScreenState();
}

class _MoviesScreenState extends ConsumerState<MoviesScreen> {
  static const _searchDebounce = Duration(milliseconds: 250);

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedCategoryId = 'all';
  MovieSortOption _sortOption = MovieSortOption.nameAsc;
  Timer? _debounceTimer;

  // Memoisation cache for the filtered/sorted movie list. `_cachedSource`
  // is compared by identity (not length) because CatalogState hands us a
  // brand-new List instance on every sync, even when its contents happen
  // to be the same size as before.
  List<MediaItem>? _cachedSource;
  String? _cachedQuery;
  String? _cachedCategoryId;
  MovieSortOption? _cachedSortOption;
  List<MediaItem>? _cachedResult;

  /// Number of times the filter/sort pass has actually recomputed (i.e.
  /// cache misses). Exposed for tests to verify that a burst of keystrokes
  /// produces a single recompute rather than one per keystroke.
  @visibleForTesting
  int filterPassCount = 0;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final text = _searchController.text;
    if (text == _searchQuery) return;

    _debounceTimer?.cancel();
    if (text.isEmpty) {
      // Clearing the search (via the clear button or deleting all text)
      // should feel instant, not wait out the debounce window.
      setState(() {
        _searchQuery = text;
      });
      return;
    }

    _debounceTimer = Timer(_searchDebounce, () {
      _debounceTimer = null;
      if (!mounted) return;
      setState(() {
        _searchQuery = text;
      });
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _resetFilters() {
    _debounceTimer?.cancel();
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _selectedCategoryId = 'all';
      _sortOption = MovieSortOption.nameAsc;
    });
  }

  void _openDetails(MediaItem item) {
    MediaDetailsModal.show(context, item, type: MediaType.movie);
  }

  /// Returns the filtered and sorted movie list, recomputing only when one
  /// of its inputs (source list identity, query, category, sort option)
  /// actually changed since the last call. Reused across unrelated
  /// rebuilds of this screen (e.g. sync-progress updates).
  List<MediaItem> _filteredAndSortedMovies(List<MediaItem> movies) {
    final query = _searchQuery.trim().toLowerCase();
    if (identical(_cachedSource, movies) &&
        _cachedQuery == query &&
        _cachedCategoryId == _selectedCategoryId &&
        _cachedSortOption == _sortOption) {
      return _cachedResult!;
    }

    final result = _computeFilteredMovies(movies, query);

    _cachedSource = movies;
    _cachedQuery = query;
    _cachedCategoryId = _selectedCategoryId;
    _cachedSortOption = _sortOption;
    _cachedResult = result;
    filterPassCount++;

    return result;
  }

  /// Computes the filtered + sorted movie list for a given lowercased
  /// [query]. This is the sole place that turns the full in-memory
  /// `movies` list into what the grid renders.
  ///
  /// SQL SWAP-POINT: when SQL-backed paging
  /// (`DatabaseService.searchMedia`/`countMedia`) is wired up, this is the
  /// method to replace with a query against the database — the debounce
  /// and memoisation around it can stay as-is.
  List<MediaItem> _computeFilteredMovies(List<MediaItem> movies, String query) {
    final hasSearch = query.isNotEmpty;
    final hasCategory = _selectedCategoryId != 'all';

    // Precompute each title's lowercase form once during the filter pass
    // so the sort comparator never re-lowercases a name (which would
    // otherwise run toLowerCase() O(n log n) times instead of O(n)).
    final entries = <({MediaItem item, String lowerName})>[];
    for (final m in movies) {
      if (hasCategory && m.categoryId != _selectedCategoryId) continue;
      final lowerName = m.name.toLowerCase();
      if (hasSearch && !lowerName.contains(query)) continue;
      entries.add((item: m, lowerName: lowerName));
    }

    entries.sort((a, b) {
      switch (_sortOption) {
        case MovieSortOption.nameAsc:
          return a.lowerName.compareTo(b.lowerName);
        case MovieSortOption.nameDesc:
          return b.lowerName.compareTo(a.lowerName);
        case MovieSortOption.ratingDesc:
          final diff = b.item.numericRating.compareTo(a.item.numericRating);
          if (diff != 0) return diff;
          return a.lowerName.compareTo(b.lowerName);
        case MovieSortOption.ratingAsc:
          final diff = a.item.numericRating.compareTo(b.item.numericRating);
          if (diff != 0) return diff;
          return a.lowerName.compareTo(b.lowerName);
      }
    });

    return entries.map((e) => e.item).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider);
    final movies = catalog.movies;
    final categories = catalog.vodCategories;

    // Count movies per category
    final Map<String, int> categoryCounts = {};
    for (final m in movies) {
      if (m.categoryId != null) {
        categoryCounts[m.categoryId!] = (categoryCounts[m.categoryId!] ?? 0) + 1;
      }
    }

    // Filter and Sort Movies (memoised — see _filteredAndSortedMovies)
    final query = _searchQuery.trim().toLowerCase();
    final hasSearch = query.isNotEmpty;
    final hasCategory = _selectedCategoryId != 'all';
    final isFiltered = hasSearch || hasCategory;

    final filteredMovies = _filteredAndSortedMovies(movies);

    final selectedCategoryObj = categories.firstWhere(
      (c) => c.categoryId == _selectedCategoryId,
      orElse: () => const CategoryItem(categoryId: 'all', categoryName: 'All Categories'),
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: Column(
              children: [
                // Top Filter Bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Responsive row / wrap of controls
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final isMobile = constraints.maxWidth < 750;

                            if (isMobile) {
                              return Column(
                                children: [
                                  // Search input
                                  _buildSearchField(),
                                  const SizedBox(height: 12),
                                  // Category, Sort, Count pill, Reset
                                  Row(
                                    children: [
                                      Expanded(child: _buildCategoryDropdown(categories, movies.length, categoryCounts)),
                                      const SizedBox(width: 8),
                                      Expanded(child: _buildSortDropdown()),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      _buildCountPill(isFiltered, filteredMovies.length, movies.length),
                                      if (isFiltered) _buildResetButton(),
                                    ],
                                  ),
                                ],
                              );
                            }

                            return Row(
                              children: [
                                // Search input
                                Expanded(
                                  flex: 3,
                                  child: _buildSearchField(),
                                ),
                                const SizedBox(width: 12),

                                // Category Dropdown
                                SizedBox(
                                  width: 220,
                                  child: _buildCategoryDropdown(categories, movies.length, categoryCounts),
                                ),
                                const SizedBox(width: 12),

                                // Sort Dropdown
                                SizedBox(
                                  width: 180,
                                  child: _buildSortDropdown(),
                                ),
                                const SizedBox(width: 12),

                                // Count Pill
                                _buildCountPill(isFiltered, filteredMovies.length, movies.length),

                                // Reset Button
                                if (isFiltered) ...[
                                  const SizedBox(width: 10),
                                  _buildResetButton(),
                                ],
                              ],
                            );
                          },
                        ),

                        // Active Filters Indicator Row
                        if (isFiltered) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.only(top: 10),
                            decoration: const BoxDecoration(
                              border: Border(top: BorderSide(color: Color(0x3327272A))),
                            ),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.tune_rounded, size: 13, color: AppColors.primary),
                                    SizedBox(width: 4),
                                    Text(
                                      'Active filters:',
                                      style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                                    ),
                                  ],
                                ),
                                if (hasSearch)
                                  _buildFilterChip(
                                    label: 'Title: "$_searchQuery"',
                                    onDelete: () => _searchController.clear(),
                                  ),
                                if (hasCategory)
                                  _buildFilterChip(
                                    label: 'Category: ${selectedCategoryObj.categoryName}',
                                    onDelete: () => setState(() => _selectedCategoryId = 'all'),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // Grid of Movies
                Expanded(
                  child: CatalogGrid<MediaItem>(
                    items: filteredMovies,
                    isLoading: catalog.isLoading && movies.isEmpty,
                    emptyMessage: isFiltered
                        ? 'No movies match your current search or category filter.'
                        : 'No movies available in this catalog source.',
                    itemBuilder: (context, movie, index) {
                      return MediaCard(
                        item: movie,
                        type: MediaType.movie,
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
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Search movies by title...',
          hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
          prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMuted, size: 18),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppColors.textLight, size: 16),
                  onPressed: () => _searchController.clear(),
                )
              : null,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildCategoryDropdown(
    List<CategoryItem> categories,
    int totalMovies,
    Map<String, int> counts,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(10),
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
            DropdownMenuItem(
              value: 'all',
              child: Text(
                'All Categories ($totalMovies)',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ...categories.map((cat) {
              final count = counts[cat.categoryId];
              final suffix = count != null ? ' ($count)' : '';
              return DropdownMenuItem(
                value: cat.categoryId,
                child: Text(
                  '${cat.categoryName}$suffix',
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildSortDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<MovieSortOption>(
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
          items: MovieSortOption.values.map((opt) {
            return DropdownMenuItem(
              value: opt,
              child: Text(opt.label, overflow: TextOverflow.ellipsis),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildCountPill(bool isFiltered, int filteredCount, int totalCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.movie_outlined, size: 15, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(
            isFiltered
                ? 'Filtered: $filteredCount of $totalCount'
                : '$totalCount Movies',
            style: const TextStyle(
              color: AppColors.textLight,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResetButton() {
    return OutlinedButton.icon(
      onPressed: _resetFilters,
      icon: const Icon(Icons.restart_alt_rounded, size: 15, color: AppColors.textLight),
      label: const Text('Reset', style: TextStyle(color: AppColors.textLight, fontSize: 12)),
      style: OutlinedButton.styleFrom(
        backgroundColor: AppColors.surfaceLight,
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  Widget _buildFilterChip({required String label, required VoidCallback onDelete}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFFC7D2FE), fontSize: 11),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: onDelete,
            child: const Icon(Icons.close_rounded, size: 12, color: Color(0xFFC7D2FE)),
          ),
        ],
      ),
    );
  }
}
