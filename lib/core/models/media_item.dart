import 'dart:convert';

/// Media type enumeration for movies and TV series.
enum MediaType {
  movie,
  series,
}

/// Represents a movie (VOD) or TV series media item.
class MediaItem {
  final String streamId; // stream_id for movies, series_id for series
  final String name;
  final String? categoryId;
  final String? categoryName;
  final String? streamIcon;
  final String? cover;
  final String? rating;
  final String? rating5Based;
  final String? year;
  final String? releaseDate;
  final String? plot;
  final String? duration;
  final String? genre;
  final String? director;
  final String? cast;
  final String? containerExtension;
  final String sourceId;
  final bool isSeries;

  const MediaItem({
    required this.streamId,
    required this.name,
    this.categoryId,
    this.categoryName,
    this.streamIcon,
    this.cover,
    this.rating,
    this.rating5Based,
    this.year,
    this.releaseDate,
    this.plot,
    this.duration,
    this.genre,
    this.director,
    this.cast,
    this.containerExtension,
    required this.sourceId,
    this.isSeries = false,
  });

  /// Factory constructor to parse media item from API response.
  factory MediaItem.fromJson(
    Map<String, dynamic> json,
    String sourceId, {
    bool isSeries = false,
  }) {
    final resolvedIsSeries = isSeries ||
        json['isSeries'] == true ||
        (json['series_id'] != null && json['stream_id'] == null);

    final rawId = resolvedIsSeries
        ? (json['series_id'] ?? json['id'] ?? json['stream_id'])
        : (json['stream_id'] ?? json['id'] ?? json['series_id']);
    final streamId = rawId?.toString() ?? '';

    final name = (json['name'] ?? json['title'])?.toString() ?? '';
    final categoryId = json['category_id']?.toString();
    final categoryName =
        (json['category_name'] ?? json['categoryName'])?.toString();
    final streamIcon =
        (json['stream_icon'] ?? json['streamIcon'])?.toString();
    final cover = json['cover']?.toString();
    final rating = json['rating']?.toString();
    final rating5Based =
        (json['rating_5based'] ?? json['rating5Based'])?.toString();
    final year = json['year']?.toString();
    final releaseDate =
        (json['release_date'] ?? json['releaseDate'])?.toString();
    final plot = json['plot']?.toString();
    final duration = json['duration']?.toString();
    final genre = json['genre']?.toString();
    final director = json['director']?.toString();
    final cast = json['cast']?.toString();
    final containerExtension =
        (json['container_extension'] ?? json['containerExtension'])?.toString();

    return MediaItem(
      streamId: streamId,
      name: name,
      categoryId: categoryId,
      categoryName: categoryName,
      streamIcon: streamIcon,
      cover: cover,
      rating: rating,
      rating5Based: rating5Based,
      year: year,
      releaseDate: releaseDate,
      plot: plot,
      duration: duration,
      genre: genre,
      director: director,
      cast: cast,
      containerExtension: containerExtension,
      sourceId: sourceId,
      isSeries: resolvedIsSeries,
    );
  }

  /// Convenience factory for movie payloads
  factory MediaItem.fromMovieJson(Map<String, dynamic> json, [String sourceId = '']) =>
      MediaItem.fromJson(json, sourceId, isSeries: false);

  /// Convenience factory for series payloads
  factory MediaItem.fromSeriesJson(Map<String, dynamic> json, [String sourceId = '']) =>
      MediaItem.fromJson(json, sourceId, isSeries: true);

  /// Alias for streamId
  String get id => streamId;

  /// Alias for isSeries as enum
  MediaType get type => isSeries ? MediaType.series : MediaType.movie;

  /// Alias for displayYear
  String? get extractedYear => displayYear;

  /// Maps the object to a SQLite row format.
  /// Stores key search attributes as explicit columns and full JSON in [data].
  Map<String, dynamic> toMap() {
    return {
      if (isSeries) 'series_id': streamId else 'stream_id': streamId,
      'category_id': categoryId,
      'name': name,
      'sourceId': sourceId,
      'data': jsonEncode(toJson()),
    };
  }

  /// Deserializes a MediaItem from a SQLite database row.
  factory MediaItem.fromMap(Map<String, dynamic> map) {
    if (map['data'] != null && map['data'] is String) {
      try {
        final decoded = jsonDecode(map['data'] as String) as Map<String, dynamic>;
        final isSeries = map.containsKey('series_id') || decoded['isSeries'] == true;
        final sourceId = map['sourceId']?.toString() ??
            decoded['sourceId']?.toString() ??
            '';
        return MediaItem.fromJson(decoded, sourceId, isSeries: isSeries);
      } catch (_) {
        // Fall back to direct column mapping if JSON decode fails
      }
    }

    final isSeries = map.containsKey('series_id');
    final streamId = (map['stream_id'] ?? map['series_id'] ?? map['id'])?.toString() ?? '';

    return MediaItem(
      streamId: streamId,
      name: map['name']?.toString() ?? '',
      categoryId: map['category_id']?.toString(),
      categoryName: (map['category_name'] ?? map['categoryName'])?.toString(),
      streamIcon: (map['stream_icon'] ?? map['streamIcon'])?.toString(),
      cover: map['cover']?.toString(),
      rating: map['rating']?.toString(),
      rating5Based: (map['rating_5based'] ?? map['rating5Based'])?.toString(),
      year: map['year']?.toString(),
      releaseDate: (map['release_date'] ?? map['releaseDate'])?.toString(),
      plot: map['plot']?.toString(),
      duration: map['duration']?.toString(),
      genre: map['genre']?.toString(),
      director: map['director']?.toString(),
      cast: map['cast']?.toString(),
      containerExtension: (map['container_extension'] ?? map['containerExtension'])?.toString(),
      sourceId: map['sourceId']?.toString() ?? '',
      isSeries: isSeries,
    );
  }

  /// Serializes the MediaItem to a JSON-compatible Map.
  Map<String, dynamic> toJson() {
    return {
      if (isSeries) 'series_id': streamId else 'stream_id': streamId,
      'id': streamId,
      'name': name,
      'category_id': categoryId,
      'category_name': categoryName,
      'stream_icon': streamIcon,
      'cover': cover,
      'rating': rating,
      'rating_5based': rating5Based,
      'year': year,
      'release_date': releaseDate,
      'plot': plot,
      'duration': duration,
      'genre': genre,
      'director': director,
      'cast': cast,
      'container_extension': containerExtension,
      'sourceId': sourceId,
      'isSeries': isSeries,
    };
  }

  /// Formatted rating (e.g. "8.5") or null if unrated.
  String? get formattedRating {
    double? numVal;
    if (rating != null && rating!.trim().isNotEmpty) {
      numVal = double.tryParse(rating!.trim());
    }
    if ((numVal == null || numVal <= 0) &&
        rating5Based != null &&
        rating5Based!.trim().isNotEmpty) {
      final val5 = double.tryParse(rating5Based!.trim());
      if (val5 != null && val5 > 0) {
        numVal = val5 <= 5 ? val5 * 2 : val5;
      }
    }
    if (numVal != null && numVal > 0) {
      return numVal.toStringAsFixed(1);
    }
    return null;
  }

  /// Numeric rating for sorting comparisons.
  double get numericRating {
    final fr = formattedRating;
    if (fr != null) {
      return double.tryParse(fr) ?? 0.0;
    }
    return 0.0;
  }

  /// Extracts 4-digit release year from [year] or [releaseDate].
  String? get displayYear {
    if (year != null && year!.trim().isNotEmpty) {
      final match = RegExp(r'\b(19\d\d|20\d\d)\b').firstMatch(year!);
      if (match != null) return match.group(1);
      return year!.trim();
    }
    if (releaseDate != null && releaseDate!.trim().isNotEmpty) {
      final match = RegExp(r'\b(19\d\d|20\d\d)\b').firstMatch(releaseDate!);
      if (match != null) return match.group(1);
    }
    return null;
  }

  /// Preferred poster or cover URL.
  String? get posterUrl {
    if (streamIcon != null && streamIcon!.trim().isNotEmpty) {
      return streamIcon!.trim();
    }
    if (cover != null && cover!.trim().isNotEmpty) {
      return cover!.trim();
    }
    return null;
  }

  MediaItem copyWith({
    String? streamId,
    String? name,
    String? categoryId,
    String? categoryName,
    String? streamIcon,
    String? cover,
    String? rating,
    String? rating5Based,
    String? year,
    String? releaseDate,
    String? plot,
    String? duration,
    String? genre,
    String? director,
    String? cast,
    String? containerExtension,
    String? sourceId,
    bool? isSeries,
  }) {
    return MediaItem(
      streamId: streamId ?? this.streamId,
      name: name ?? this.name,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      streamIcon: streamIcon ?? this.streamIcon,
      cover: cover ?? this.cover,
      rating: rating ?? this.rating,
      rating5Based: rating5Based ?? this.rating5Based,
      year: year ?? this.year,
      releaseDate: releaseDate ?? this.releaseDate,
      plot: plot ?? this.plot,
      duration: duration ?? this.duration,
      genre: genre ?? this.genre,
      director: director ?? this.director,
      cast: cast ?? this.cast,
      containerExtension: containerExtension ?? this.containerExtension,
      sourceId: sourceId ?? this.sourceId,
      isSeries: isSeries ?? this.isSeries,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaItem &&
          runtimeType == other.runtimeType &&
          streamId == other.streamId &&
          sourceId == other.sourceId &&
          isSeries == other.isSeries;

  @override
  int get hashCode =>
      streamId.hashCode ^ sourceId.hashCode ^ isSeries.hashCode;
}
