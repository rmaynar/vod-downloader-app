/// Model representing catalog statistics in local SQLite cache.
class CatalogStats {
  final int totalMovies;
  final int totalSeries;
  final int totalCategories;
  final DateTime? lastSyncTime;

  const CatalogStats({
    this.totalMovies = 0,
    this.totalSeries = 0,
    this.totalCategories = 0,
    this.lastSyncTime,
  });

  CatalogStats copyWith({
    int? totalMovies,
    int? totalSeries,
    int? totalCategories,
    DateTime? lastSyncTime,
  }) {
    return CatalogStats(
      totalMovies: totalMovies ?? this.totalMovies,
      totalSeries: totalSeries ?? this.totalSeries,
      totalCategories: totalCategories ?? this.totalCategories,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
    );
  }
}
