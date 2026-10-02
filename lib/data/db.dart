import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Owns the SQLite connection and schema for WizardScore.
///
/// Everything the app stores lives here on the device: there is no backend and
/// no network code. The database is opened through an injectable
/// [DatabaseFactory] so tests can run the whole schema in memory.
class WizardDatabase {
  WizardDatabase._(this.db);

  /// The live connection. Prefer the repositories over touching this directly.
  final Database db;

  /// Bump this and add an `onUpgrade` branch whenever the schema changes.
  static const int schemaVersion = 1;

  /// File name used on device. Kept here so backup tooling can find it.
  static const String fileName = 'wizard_score.db';

  /// Opens (creating if needed) the on-device database.
  ///
  /// Pass [factory] and [inMemory] from tests to get an isolated database.
  static Future<WizardDatabase> open({
    DatabaseFactory? factory,
    String? path,
    bool inMemory = false,
  }) async {
    final resolvedFactory = factory ?? databaseFactory;
    final resolvedPath = inMemory
        ? inMemoryDatabasePath
        : (path ?? p.join(await resolvedFactory.getDatabasesPath(), fileName));

    final db = await resolvedFactory.openDatabase(
      resolvedPath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) async {
          // Required for the ON DELETE CASCADE rules below to mean anything.
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) => _createV1(db),
        onUpgrade: (db, oldVersion, newVersion) => _upgrade(db, oldVersion),
      ),
    );
    return WizardDatabase._(db);
  }

  Future<void> close() => db.close();

  static Future<void> _createV1(Database db) async {
    await db.execute('''
      CREATE TABLE players (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        name        TEXT    NOT NULL,
        color_index INTEGER NOT NULL DEFAULT 0,
        is_archived INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // Case-insensitive uniqueness. This is the real guard against duplicate
    // names ("Suchit" vs "suchit"); repositories also pre-check so the UI can
    // show a friendly message instead of surfacing a constraint error.
    await db.execute(
      'CREATE UNIQUE INDEX idx_players_name_nocase ON players (name COLLATE NOCASE)',
    );

    await db.execute('''
      CREATE TABLE games (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        started_at    INTEGER NOT NULL,
        ended_at      INTEGER,
        status        TEXT    NOT NULL DEFAULT 'in_progress',
        player_count  INTEGER NOT NULL,
        current_round INTEGER NOT NULL DEFAULT 1,
        wins_counted  INTEGER NOT NULL DEFAULT 0,
        even_bid_rule INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE game_players (
        game_id     INTEGER NOT NULL REFERENCES games(id) ON DELETE CASCADE,
        player_id   INTEGER NOT NULL REFERENCES players(id),
        seat        INTEGER NOT NULL,
        total_score INTEGER NOT NULL DEFAULT 0,
        final_rank  INTEGER,
        PRIMARY KEY (game_id, player_id)
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX idx_game_players_seat ON game_players (game_id, seat)',
    );

    await db.execute('''
      CREATE TABLE rounds (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        game_id      INTEGER NOT NULL REFERENCES games(id) ON DELETE CASCADE,
        round_number INTEGER NOT NULL,
        cards_dealt  INTEGER NOT NULL,
        dealer_seat  INTEGER NOT NULL,
        -- Vestigial: trump is no longer tracked. The columns stay so schema
        -- version 1 remains valid without a migration.
        trump_type   TEXT    NOT NULL DEFAULT 'none',
        trump_suit   TEXT,
        status       TEXT    NOT NULL DEFAULT 'pending'
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX idx_rounds_game_number ON rounds (game_id, round_number)',
    );

    await db.execute('''
      CREATE TABLE round_entries (
        round_id   INTEGER NOT NULL REFERENCES rounds(id) ON DELETE CASCADE,
        player_id  INTEGER NOT NULL REFERENCES players(id),
        bid        INTEGER,
        bid_locked INTEGER NOT NULL DEFAULT 0,
        tricks_won INTEGER,
        points     INTEGER,
        PRIMARY KEY (round_id, player_id)
      )
    ''');

    // Co-winners for a tie are rows here rather than a column, so the
    // leaderboard can count wins with a plain join.
    await db.execute('''
      CREATE TABLE game_winners (
        game_id   INTEGER NOT NULL REFERENCES games(id) ON DELETE CASCADE,
        player_id INTEGER NOT NULL REFERENCES players(id),
        PRIMARY KEY (game_id, player_id)
      )
    ''');

    // A game can only be in progress once at a time; indexed because the home
    // screen looks this up on every launch.
    await db.execute('CREATE INDEX idx_games_status ON games (status)');
    await db.execute(
      'CREATE INDEX idx_game_winners_player ON game_winners (player_id)',
    );
  }

  static Future<void> _upgrade(Database db, int oldVersion) async {
    // Only one version so far; future migrations slot in here.
  }
}
