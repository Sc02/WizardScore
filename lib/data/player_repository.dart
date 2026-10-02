import 'package:sqflite/sqflite.dart';

import '../data/db.dart';
import '../models/player.dart';

/// Raised when a player name collides with an existing player.
///
/// Carries the name that clashed so the UI can say exactly which one.
class DuplicatePlayerNameException implements Exception {
  const DuplicatePlayerNameException(this.name);

  final String name;

  @override
  String toString() => "A player named '$name' already exists";
}

/// Raised when an operation references a player that is no longer there.
class PlayerNotFoundException implements Exception {
  const PlayerNotFoundException(this.id);

  final int id;

  @override
  String toString() => 'No player with id $id';
}

/// Reads and writes players, and derives the leaderboard.
///
/// All leaderboard numbers are computed from game history rather than cached on
/// the player row, so a time-travel rewind can never leave a stale win counted.
class PlayerRepository {
  PlayerRepository(this._db);

  final WizardDatabase _db;

  /// Collapses runs of whitespace and trims, so "Suchit  Rao " and "Suchit Rao"
  /// are treated as the same name.
  static String normalizeName(String raw) =>
      raw.trim().replaceAll(RegExp(r'\s+'), ' ');

  /// Checks a name without touching the database path used by [create].
  static String? validateName(String raw) {
    final name = normalizeName(raw);
    if (name.isEmpty) return 'Enter a name';
    if (name.length < 2) return 'Names need at least 2 characters';
    if (name.length > 24) return 'Names can be at most 24 characters';
    return null;
  }

  /// Active (non-archived) players, alphabetical.
  Future<List<Player>> listActive() async {
    final rows = await _db.db.query(
      'players',
      where: 'is_archived = 0',
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(Player.fromMap).toList(growable: false);
  }

  Future<Player?> findById(int id) async {
    final rows = await _db.db.query(
      'players',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Player.fromMap(rows.first);
  }

  /// Case-insensitive lookup used for the duplicate-name check.
  Future<Player?> findByName(String raw) async {
    final name = normalizeName(raw);
    final rows = await _db.db.query(
      'players',
      where: 'name = ? COLLATE NOCASE',
      whereArgs: <Object?>[name],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Player.fromMap(rows.first);
  }

  /// Convenience for the add-player form: returns a user-facing message when
  /// the name is invalid or already taken, or `null` when it is fine.
  Future<String?> nameProblem(String raw, {int? ignoreId}) async {
    final formatProblem = validateName(raw);
    if (formatProblem != null) return formatProblem;
    final existing = await findByName(raw);
    if (existing != null && existing.id != ignoreId) {
      return "A player named '${existing.name}' already exists";
    }
    return null;
  }

  /// Inserts a player, rejecting duplicate names.
  ///
  /// Throws [DuplicatePlayerNameException] so the form can show an error under
  /// the field instead of crashing on a raw constraint violation.
  Future<Player> create({required String name, int colorIndex = 0}) async {
    final normalized = normalizeName(name);
    final formatProblem = validateName(normalized);
    if (formatProblem != null) throw ArgumentError(formatProblem);

    if (await findByName(normalized) != null) {
      throw DuplicatePlayerNameException(normalized);
    }

    try {
      final id = await _db.db.insert('players', <String, Object?>{
        'name': normalized,
        'color_index': colorIndex,
        'is_archived': 0,
      });
      return Player(id: id, name: normalized, colorIndex: colorIndex);
    } on DatabaseException catch (error) {
      // The UNIQUE COLLATE NOCASE index is the real guard; two rapid taps or a
      // race could still reach it.
      if (error.isUniqueConstraintError()) {
        throw DuplicatePlayerNameException(normalized);
      }
      rethrow;
    }
  }

  /// Renames and/or recolours a player, keeping the uniqueness guarantee.
  Future<Player> update(Player player) async {
    final id = player.id;
    if (id == null) throw ArgumentError('Cannot update an unsaved player');
    final normalized = normalizeName(player.name);
    final formatProblem = validateName(normalized);
    if (formatProblem != null) throw ArgumentError(formatProblem);

    final clash = await findByName(normalized);
    if (clash != null && clash.id != id) {
      throw DuplicatePlayerNameException(normalized);
    }

    try {
      await _db.db.update(
        'players',
        <String, Object?>{'name': normalized, 'color_index': player.colorIndex},
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError()) {
        throw DuplicatePlayerNameException(normalized);
      }
      rethrow;
    }
    return player.copyWith(name: normalized);
  }

  /// Hides a player from the roster without deleting them, so finished games
  /// keep resolving to a real name.
  Future<void> archive(int playerId) async {
    await _db.db.update(
      'players',
      <String, Object?>{'is_archived': 1},
      where: 'id = ?',
      whereArgs: <Object?>[playerId],
    );
  }

  Future<void> unarchive(int playerId) async {
    await _db.db.update(
      'players',
      <String, Object?>{'is_archived': 0},
      where: 'id = ?',
      whereArgs: <Object?>[playerId],
    );
  }

  /// True when the player has appeared in at least one game.
  Future<bool> hasPlayed(int playerId) async {
    final rows = await _db.db.query(
      'game_players',
      columns: <String>['game_id'],
      where: 'player_id = ?',
      whereArgs: <Object?>[playerId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }
}
