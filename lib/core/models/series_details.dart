/// Represents an individual TV series episode item.
class EpisodeItem {
  final String id;
  final String episodeNum;
  final String title;
  final String? duration;
  final String? containerExtension;
  final String? seasonNum;
  final String? plot;
  final String? directSource;

  const EpisodeItem({
    required this.id,
    required this.episodeNum,
    required this.title,
    this.duration,
    this.containerExtension,
    this.seasonNum,
    this.plot,
    this.directSource,
  });

  factory EpisodeItem.fromJson(
    Map<String, dynamic> json, {
    String? seasonNum,
  }) {
    final rawId = json['id'] ?? json['episode_id'] ?? '';
    final rawEpNum = json['episode_num'] ?? json['episodeNum'] ?? '';
    final rawTitle = json['title'] ?? json['name'] ?? 'Episode $rawEpNum';
    final rawSeason = seasonNum ?? (json['season'] ?? json['season_num'])?.toString();

    // Duration can be at root or nested under info
    String? duration = json['duration']?.toString();
    String? plot = json['plot']?.toString();
    if (json['info'] is Map<String, dynamic>) {
      final info = json['info'] as Map<String, dynamic>;
      duration ??= info['duration']?.toString();
      plot ??= info['plot']?.toString();
    }

    final containerExtension =
        (json['container_extension'] ?? json['containerExtension'])?.toString();
    final directSource = json['direct_source']?.toString();

    return EpisodeItem(
      id: rawId.toString(),
      episodeNum: rawEpNum.toString(),
      title: rawTitle.toString(),
      duration: duration,
      containerExtension: containerExtension,
      seasonNum: rawSeason,
      plot: plot,
      directSource: directSource,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'episode_num': episodeNum,
      'title': title,
      'duration': duration,
      'container_extension': containerExtension,
      'season': seasonNum,
      'plot': plot,
      'direct_source': directSource,
    };
  }
}

/// Represents full details for a TV series, including season episodes and metadata info.
class SeriesDetails {
  final Map<String, List<EpisodeItem>> seasons;
  final Map<String, dynamic> info;

  const SeriesDetails({
    required this.seasons,
    required this.info,
  });

  /// Factory constructor parsing Xtream series_info response format.
  /// Handles `episodes` whether it is a Map of season arrays or an empty List.
  factory SeriesDetails.fromJson(Map<String, dynamic> json) {
    final rawInfo = json['info'] is Map<String, dynamic>
        ? json['info'] as Map<String, dynamic>
        : <String, dynamic>{};

    final rawEpisodes = json['episodes'];
    final seasonsMap = <String, List<EpisodeItem>>{};

    if (rawEpisodes is Map) {
      rawEpisodes.forEach((seasonKey, epList) {
        if (epList is List) {
          final episodes = epList
              .whereType<Map<String, dynamic>>()
              .map((ep) => EpisodeItem.fromJson(ep, seasonNum: seasonKey.toString()))
              .toList();
          // Sort episodes by episode number ascending
          episodes.sort((a, b) {
            final numA = int.tryParse(a.episodeNum) ?? 0;
            final numB = int.tryParse(b.episodeNum) ?? 0;
            return numA.compareTo(numB);
          });
          seasonsMap[seasonKey.toString()] = episodes;
        }
      });
    } else if (rawEpisodes is List) {
      for (final ep in rawEpisodes) {
        if (ep is Map<String, dynamic>) {
          final seasonKey =
              (ep['season'] ?? ep['season_num'] ?? '1').toString();
          final item = EpisodeItem.fromJson(ep, seasonNum: seasonKey);
          seasonsMap.putIfAbsent(seasonKey, () => []).add(item);
        }
      }
      seasonsMap.forEach((_, list) {
        list.sort((a, b) {
          final numA = int.tryParse(a.episodeNum) ?? 0;
          final numB = int.tryParse(b.episodeNum) ?? 0;
          return numA.compareTo(numB);
        });
      });
    }

    return SeriesDetails(
      seasons: seasonsMap,
      info: rawInfo,
    );
  }

  /// Season numbers sorted numerically.
  List<String> get seasonNumbers {
    final list = seasons.keys.toList();
    list.sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
    return list;
  }

  /// Helper to get episodes for a given season.
  List<EpisodeItem> getEpisodes(String seasonNum) {
    return seasons[seasonNum] ?? const [];
  }

  /// Total count of all episodes across all seasons.
  int get totalEpisodes {
    return seasons.values.fold(0, (sum, list) => sum + list.length);
  }

  String? get name => info['name']?.toString();
  String? get plot => info['plot']?.toString();
  String? get cover => (info['cover'] ?? info['stream_icon'])?.toString();
  String? get releaseDate =>
      (info['releaseDate'] ?? info['release_date'])?.toString();
  String? get rating => info['rating']?.toString();
  String? get genre => info['genre']?.toString();
  String? get cast => info['cast']?.toString();
  String? get director => info['director']?.toString();
}
