/// A person who can be seated at a table. Stored in the `players` table.
///
/// Players are never hard deleted once they have played a game — they are
/// archived — so that game history keeps resolving to a real name.
class Player {
  const Player({
    this.id,
    required this.name,
    this.colorIndex = 0,
    this.isArchived = false,
  });

  /// `null` until the row has been inserted.
  final int? id;

  /// Display name. Unique across non-archived players, compared
  /// case-insensitively (enforced by a UNIQUE COLLATE NOCASE index).
  final String name;

  /// Index into `playerPalette`, not a raw colour value.
  final int colorIndex;

  final bool isArchived;

  bool get isPersisted => id != null;

  /// Two letters for the avatar disc, e.g. "Suchit Rao" -> "SR".
  String get initials {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final single = parts.first;
      final clipped = single.length <= 2 ? single : single.substring(0, 2);
      return clipped.toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  Player copyWith({int? id, String? name, int? colorIndex, bool? isArchived}) =>
      Player(
        id: id ?? this.id,
        name: name ?? this.name,
        colorIndex: colorIndex ?? this.colorIndex,
        isArchived: isArchived ?? this.isArchived,
      );

  Map<String, Object?> toMap() => <String, Object?>{
    if (id != null) 'id': id,
    'name': name,
    'color_index': colorIndex,
    'is_archived': isArchived ? 1 : 0,
  };

  factory Player.fromMap(Map<String, Object?> map) => Player(
    id: map['id'] as int?,
    name: map['name'] as String,
    colorIndex: (map['color_index'] as int?) ?? 0,
    isArchived: (map['is_archived'] as int? ?? 0) == 1,
  );

  @override
  String toString() => 'Player($id, $name, color=$colorIndex)';
}
