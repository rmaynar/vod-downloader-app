import 'dart:convert';

/// Represents a configured Xtream/IPTV source account.
class SourceAccount {
  final String id;
  final String sourceId;
  final String name;
  final String url;
  final String username;
  final String? password;
  final int lastUsedAt;

  const SourceAccount({
    required this.id,
    required this.sourceId,
    String? name,
    required this.url,
    required this.username,
    this.password,
    int? lastUsedAt,
  })  : name = name ?? '',
        lastUsedAt = lastUsedAt ?? 0;

  String get displayName => name.trim().isNotEmpty ? name.trim() : username;

  /// Factory constructor to parse source account from JSON.
  factory SourceAccount.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'] ?? json['sourceId'] ?? '';
    final rawSourceId = json['sourceId'] ?? json['id'] ?? '';
    final rawLastUsed = json['lastUsedAt'] ?? json['last_used_at'];
    int parsedLastUsed = DateTime.now().millisecondsSinceEpoch;
    if (rawLastUsed is num) {
      parsedLastUsed = rawLastUsed.toInt();
    } else if (rawLastUsed is String) {
      parsedLastUsed = int.tryParse(rawLastUsed) ?? parsedLastUsed;
    }

    return SourceAccount(
      id: rawId.toString(),
      sourceId: rawSourceId.toString(),
      name: json['name']?.toString() ?? json['username']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      password: json['password']?.toString(),
      lastUsedAt: parsedLastUsed,
    );
  }

  /// Maps the object to a SQLite row format.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'username': username,
      'data': jsonEncode(toJson()),
    };
  }

  /// Deserializes a SourceAccount from a SQLite database row.
  factory SourceAccount.fromMap(Map<String, dynamic> map) {
    if (map['data'] != null && map['data'] is String) {
      try {
        final decoded = jsonDecode(map['data'] as String) as Map<String, dynamic>;
        return SourceAccount.fromJson(decoded);
      } catch (_) {
        // Fall back to reading raw columns
      }
    }

    final rawId = map['id'] ?? map['sourceId'] ?? '';
    final rawSourceId = map['sourceId'] ?? map['id'] ?? '';
    final rawLastUsed = map['lastUsedAt'] ?? map['last_used_at'];
    int parsedLastUsed = DateTime.now().millisecondsSinceEpoch;
    if (rawLastUsed is num) {
      parsedLastUsed = rawLastUsed.toInt();
    } else if (rawLastUsed is String) {
      parsedLastUsed = int.tryParse(rawLastUsed) ?? parsedLastUsed;
    }

    return SourceAccount(
      id: rawId.toString(),
      sourceId: rawSourceId.toString(),
      name: map['name']?.toString() ?? '',
      url: map['url']?.toString() ?? '',
      username: map['username']?.toString() ?? '',
      password: map['password']?.toString(),
      lastUsedAt: parsedLastUsed,
    );
  }

  /// Serializes the SourceAccount to a JSON Map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sourceId': sourceId,
      'name': name,
      'url': url,
      'username': username,
      if (password != null) 'password': password,
      'lastUsedAt': lastUsedAt,
    };
  }

  SourceAccount copyWith({
    String? id,
    String? sourceId,
    String? name,
    String? url,
    String? username,
    String? password,
    int? lastUsedAt,
  }) {
    return SourceAccount(
      id: id ?? this.id,
      sourceId: sourceId ?? this.sourceId,
      name: name ?? this.name,
      url: url ?? this.url,
      username: username ?? this.username,
      password: password ?? this.password,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SourceAccount &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
