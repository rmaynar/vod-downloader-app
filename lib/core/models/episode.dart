import 'package:flutter/foundation.dart';

@immutable
class Episode {
  final String id;
  final int episodeNum;
  final String title;
  final String? duration;
  final String? containerExtension;
  final String? plot;
  final String? seasonNum;
  final Map<String, dynamic>? rawData;

  const Episode({
    required this.id,
    required this.episodeNum,
    required this.title,
    this.duration,
    this.containerExtension,
    this.plot,
    this.seasonNum,
    this.rawData,
  });

  factory Episode.fromJson(Map<String, dynamic> json, {String? seasonNum}) {
    final info = json['info'] as Map<String, dynamic>?;
    final epNumRaw = json['episode_num'];
    final epNum = epNumRaw is int
        ? epNumRaw
        : int.tryParse(epNumRaw?.toString() ?? '1') ?? 1;

    return Episode(
      id: (json['id'] ?? json['episode_id'] ?? '').toString(),
      episodeNum: epNum,
      title: (json['title'] ?? 'Episode $epNum').toString(),
      duration: (json['duration'] ?? info?['duration'] ?? info?['duration_secs']?.toString()),
      containerExtension: (json['container_extension'] ?? 'mp4').toString(),
      plot: (info?['plot'] ?? info?['description'] ?? json['plot'])?.toString(),
      seasonNum: seasonNum ?? json['season']?.toString(),
      rawData: json,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'episode_num': episodeNum,
      'title': title,
      'duration': duration,
      'container_extension': containerExtension,
      'plot': plot,
      'season': seasonNum,
    };
  }
}
