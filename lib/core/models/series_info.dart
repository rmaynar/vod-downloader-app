import 'package:flutter/foundation.dart';
import 'episode.dart';
import 'media_item.dart';

@immutable
class SeriesInfo {
  final MediaItem? info;
  final Map<String, List<Episode>> episodes;

  const SeriesInfo({
    this.info,
    required this.episodes,
  });

  String get name => info?.name ?? '';

  int get totalEpisodes =>
      episodes.values.fold(0, (acc, list) => acc + list.length);

  List<Episode> getEpisodes(String season) => episodes[season] ?? [];

  List<String> get seasons {
    final list = episodes.keys.toList();
    list.sort((a, b) {
      final intA = int.tryParse(a) ?? 0;
      final intB = int.tryParse(b) ?? 0;
      return intA.compareTo(intB);
    });
    return list;
  }

  factory SeriesInfo.fromJson(Map<String, dynamic> json) {
    MediaItem? info;
    if (json['info'] is Map<String, dynamic>) {
      info = MediaItem.fromSeriesJson(json['info'] as Map<String, dynamic>);
    }

    final episodesMap = <String, List<Episode>>{};
    final rawEpisodes = json['episodes'];

    if (rawEpisodes is Map<String, dynamic>) {
      rawEpisodes.forEach((seasonKey, epList) {
        if (epList is List) {
          final eps = <Episode>[];
          for (final item in epList) {
            if (item is Map<String, dynamic>) {
              eps.add(Episode.fromJson(item, seasonNum: seasonKey));
            }
          }
          eps.sort((a, b) => a.episodeNum.compareTo(b.episodeNum));
          episodesMap[seasonKey] = eps;
        }
      });
    }

    return SeriesInfo(
      info: info,
      episodes: episodesMap,
    );
  }
}
