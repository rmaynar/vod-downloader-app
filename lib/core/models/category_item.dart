/// Represents a VOD or TV series category.
class CategoryItem {
  final String categoryId;
  final String categoryName;
  final String sourceId;
  final String type; // 'vod' or 'series'

  const CategoryItem({
    required this.categoryId,
    required this.categoryName,
    this.sourceId = '',
    this.type = 'vod',
  });

  /// Factory constructor to parse category from API response.
  factory CategoryItem.fromJson(
    Map<String, dynamic> json,
    String sourceId,
    String type,
  ) {
    final rawId = json['category_id'] ?? json['id'] ?? json['categoryId'];
    final name = json['category_name'] ?? json['name'] ?? json['categoryName'] ?? '';

    return CategoryItem(
      categoryId: rawId?.toString() ?? '',
      categoryName: name.toString(),
      sourceId: sourceId,
      type: type,
    );
  }

  /// Maps the object to a SQLite row format.
  Map<String, dynamic> toMap() {
    return {
      'category_id': categoryId,
      'category_name': categoryName,
      'sourceId': sourceId,
    };
  }

  /// Deserializes a CategoryItem from a SQLite database row.
  factory CategoryItem.fromMap(Map<String, dynamic> map, [String? type]) {
    final catId = (map['category_id'] ?? map['categoryId'] ?? map['id'])?.toString() ?? '';
    final name = (map['category_name'] ?? map['categoryName'] ?? map['name'])?.toString() ?? '';
    final sourceId = map['sourceId']?.toString() ?? '';
    final resolvedType = type ?? (map['type']?.toString() ?? 'vod');

    return CategoryItem(
      categoryId: catId,
      categoryName: name,
      sourceId: sourceId,
      type: resolvedType,
    );
  }

  /// Serializes the CategoryItem to a JSON-compatible Map.
  Map<String, dynamic> toJson() {
    return {
      'category_id': categoryId,
      'category_name': categoryName,
      'sourceId': sourceId,
      'type': type,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CategoryItem &&
          runtimeType == other.runtimeType &&
          categoryId == other.categoryId &&
          sourceId == other.sourceId &&
          type == other.type;

  @override
  int get hashCode => categoryId.hashCode ^ sourceId.hashCode ^ type.hashCode;
}
