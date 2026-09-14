import 'package:flutter/foundation.dart';

@immutable
class CatalogSource {
  final dynamic id;
  final String name;
  final String? url;
  final String? username;
  final String? type;

  const CatalogSource({
    required this.id,
    required this.name,
    this.url,
    this.username,
    this.type,
  });

  factory CatalogSource.fromJson(Map<String, dynamic> json) {
    return CatalogSource(
      id: json['id'] ?? json['_id'],
      name: (json['name'] ?? json['username'] ?? 'Source ${json['id'] ?? ''}').toString(),
      url: json['url']?.toString(),
      username: json['username']?.toString(),
      type: json['type']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'username': username,
      'type': type,
    };
  }
}
