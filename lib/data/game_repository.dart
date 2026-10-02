import 'package:sqflite/sqflite.dart';

import '../data/db.dart';
import '../domain/game_state.dart';
import '../domain/rules.dart';
import '../models/game.dart';
import '../models/player.dart';
import '../models/round.dart';

/// Thrown when a round is scored with an impossible set of tricks.
class RoundValidationException implements Exception {
  const RoundValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// All reads and writes for games, rounds and the derived leaderboard.
class GameRepository {
  GameRepository(this._db);

  final WizardDatabase _db;

  /// Creates a game, seats the players and pre-creates every round row.
  ///
  /// Round structure is generated up front from the table size, so the score
  /// sheet has its full grid from the first moment.
  Future<int> startGame({
    required List<int> playerIds,
    bool evenBidRule = false,
    DateTime? startedAt,
  }) async {
    validatePlayerCount(playerIds.length);
    if (playerIds.toSet().length != playerIds.length) {
      throw ArgumentError('A player cannot be seated twice at the same table');
    }

    final playerCount = playerIds.length;
    final roundCount = roundsForPlayers(playerCount);
    final start = startedAt ?? DateTime.now();

    return _db.db.transaction<int>((txn) async {
      final gameId = await txn.insert('games', <String, Object?>{
        'started_at': start.millisecondsSinceEpoch,
        'status': GameStatus.inProgress.dbValue,
        'player_count': playerCount,
        'current_round': 1,
        'wins_counted': 0,
        'even_bid_rule': evenBidRule ? 1 : 0,
      });

      for (var seat = 0; seat < playerCount; seat++) {
        await txn.insert('game_players', <String, Object?>{
          'game_id': gameId,
          'player_id': playerIds[seat],
          'seat': seat,
          'total_score': 0,
        });
      }

      for (var roundNumber = 1; roundNumber <= roundCount; roundNumber++) {
        await txn.insert('rounds', <String, Object?>{
          'game_id': gameId,
          'round_number': roundNumber,
          'cards_dealt': cardsForRound(roundNumber),
          'dealer_seat': dealerSeatForRound(roundNumber, playerCount),
          'status': RoundStatus.pending.dbValue,
          // `trump_type` / `trump_suit` are left at their defaults: the app no
          // longer tracks trump, and the columns are kept only so schema
          // version 1 stays valid without a migration.
        });
      }

      return gameId;
    });
  }

  /// Loads a full game read model, or `null` if it does not exist.
  Future<GameState?> loadGame(int gameId) async {
    final db = _db.db;

    final gameRows = await db.query(
      'games',
      where: 'id = ?',
      whereArgs: <Object?>[gameId],
      limit: 1,
    );
    if (gameRows.isEmpty) return null;

    final winnerRows = await db.query(
      'game_winners',
      columns: <String>['player_id'],
      where: 'game_id = ?',
      whereArgs: <Object?>[gameId],
    );
    final game = Game.fromMap(
      gameRows.first,
      winnerPlayerIds: winnerRows
          .map((row) => row['player_id'] as int)
          .toList(growable: false),
    );

    final gpRows = await db.rawQuery(
      '''
      SELECT gp.seat           AS seat,
             gp.total_score    AS total_score,
             gp.final_rank     AS final_rank,
             p.id              AS pid,
             p.name            AS pname,
             p.color_index     AS pcolor,
             p.is_archived     AS parchived
      FROM game_players gp
      JOIN players p ON p.id = gp.player_id
      WHERE gp.game_id = ?
      ORDER BY gp.seat ASC
    ''',
      <Object?>[gameId],
    );

    final standings = gpRows
        .map(
          (row) => Standing(
            player: Player(
              id: row['pid'] as int,
              name: row['pname'] as String,
              colorIndex: (row['pcolor'] as int?) ?? 0,
              isArchived: (row['parchived'] as int? ?? 0) == 1,
            ),
            seat: row['seat'] as int,
            totalScore: row['total_score'] as int,
            finalRank: row['final_rank'] as int?,
          ),
        )
        .toList(growable: false);

    final roundRows = await db.query(
      'rounds',
      where: 'game_id = ?',
      whereArgs: <Object?>[gameId],
      orderBy: 'round_number ASC',
    );
    final rounds = roundRows.map(Round.fromMap).toList(growable: false);

    final entryRows = await db.rawQuery(
      '''
      SELECT e.round_id   AS round_id,
             e.player_id  AS player_id,
             e.bid        AS bid,
             e.bid_locked AS bid_locked,
             e.tricks_won AS tricks_won,
             e.points     AS points
      FROM round_entries e
      JOIN rounds r ON r.id = e.round_id
      WHERE r.game_id = ?
      ORDER BY r.round_number ASC
    ''',
      <Object?>[gameId],
    );

    final entriesByRound = <int, List<RoundEntry>>{};
    for (final row in entryRows) {
      final entry = RoundEntry.fromMap(row);
      entriesByRound
          .putIfAbsent(entry.roundId, () => <RoundEntry>[])
          .add(entry);
    }

    return GameState(
      game: game,
      standings: standings,
      rounds: rounds,
      roundsPerPlayer: roundsForPlayers(game.playerCount),
      entriesByRound: entriesByRound,
    );
  }

  /// The single game that is currently in progress, if any.
  ///
  /// Only one game can be live at a time; that is enforced by the UI flow and
  /// checked when starting a new game.
  Future<GameState?> loadCurrentGame() async {
    final rows = await _db.db.query(
      'games',
      columns: <String>['id'],
      where: 'status = ?',
      whereArgs: <Object?>[GameStatus.inProgress.dbValue],
      orderBy: 'started_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return loadGame(rows.first['id'] as int);
  }

  /// Recomputes every seat's total from the round entries.
  ///
  /// Summation is the single source of truth, so this heals any drift and is
  /// exactly what a rewind needs: delete the tail, then recompute.
  Future<void> _recomputeTotals(DatabaseExecutor txn, int gameId) async {
    await txn.rawUpdate(
      '''
      UPDATE game_players
      SET total_score = COALESCE((
        SELECT SUM(e.points)
        FROM round_entries e
        JOIN rounds r ON r.id = e.round_id
        WHERE r.game_id = game_players.game_id
          AND e.player_id = game_players.player_id
      ), 0)
      WHERE game_id = ?
    ''',
      <Object?>[gameId],
    );
  }

  /// Writes the bids for a round without locking them.
  ///
  /// Uses an upsert that only touches the bid column, so a save can never wipe
  /// tricks or points from a previously played round.
  Future<void> saveBids(int roundId, Map<int, int> bids) async {
    if (bids.isEmpty) return;
    await _db.db.transaction((txn) async {
      for (final entry in bids.entries) {
        await txn.rawInsert(
          '''
          INSERT INTO round_entries (round_id, player_id, bid, bid_locked)
          VALUES (?, ?, ?, 0)
          ON CONFLICT(round_id, player_id) DO UPDATE SET bid = excluded.bid
        ''',
          <Object?>[roundId, entry.key, entry.value],
        );
      }
    });
  }

  /// Freezes the bids for a round and moves it to the tricks-counting stage.
  Future<void> lockBids(int roundId) async {
    await _db.db.transaction((txn) async {
      await txn.update(
        'round_entries',
        <String, Object?>{'bid_locked': 1},
        where: 'round_id = ?',
        whereArgs: <Object?>[roundId],
      );
      await txn.update(
        'rounds',
        <String, Object?>{'status': RoundStatus.bidsLocked.dbValue},
        where: 'id = ?',
        whereArgs: <Object?>[roundId],
      );
    });
  }

  /// Scores a round: validates the tricks, stores each player's points, heals
  /// the running totals and moves the game on to the next round.
  ///
  /// Every card dealt is won by someone, so the tricks must add up to
  /// `cardsDealt * playerCount`; anything else is rejected rather than guessed.
  Future<void> completeRound({
    required int gameId,
    required int roundId,
    required int roundNumber,
    required int cardsDealt,
    required Map<int, int> tricksWon,
    required int totalRounds,
  }) async {
    final available = totalTricksAvailable(cardsDealt);
    final entered = totalScore(tricksWon.values);

    if (entered != available) {
      throw RoundValidationException(
        'Tricks won add up to $entered but this round has $available '
        '($cardsDealt played tricks)',
      );
    }

    await _db.db.transaction((txn) async {
      final bidRows = await txn.query(
        'round_entries',
        columns: <String>['player_id', 'bid', 'bid_locked'],
        where: 'round_id = ?',
        whereArgs: <Object?>[roundId],
      );
      final bids = <int, int>{
        for (final row in bidRows)
          if (row['bid'] != null) row['player_id'] as int: row['bid'] as int,
      };

      for (final entry in tricksWon.entries) {
        if (!tricksIsLegal(entry.value, cardsDealt)) {
          throw RoundValidationException(
            'A player cannot win more than $cardsDealt tricks',
          );
        }
        final bid = bids[entry.key];
        if (bid == null) {
          throw RoundValidationException(
            'Every player needs a locked bid before the round can be scored',
          );
        }
        await txn.update(
          'round_entries',
          <String, Object?>{
            'tricks_won': entry.value,
            'points': scoreRound(bid, entry.value),
          },
          where: 'round_id = ? AND player_id = ?',
          whereArgs: <Object?>[roundId, entry.key],
        );
      }

      await txn.update(
        'rounds',
        <String, Object?>{'status': RoundStatus.complete.dbValue},
        where: 'id = ?',
        whereArgs: <Object?>[roundId],
      );

      await _recomputeTotals(txn, gameId);

      await txn.update(
        'games',
        <String, Object?>{'current_round': roundNumber + 1},
        where: 'id = ?',
        whereArgs: <Object?>[gameId],
      );
    });
  }

  /// Marks a round as skipped: no bids, no tricks, no points.
  ///
  /// This is the in-play "we're not doing this round" escape hatch. The round
  /// stays on the score sheet as a gap, `games.current_round` moves past it,
  /// and any bids already typed for it are discarded. Skipped rounds never
  /// touch `game_players`, so totals and the leaderboard are unaffected.
  ///
  /// Skipping the last remaining round is allowed and simply ends the game.
  Future<void> skipRound({required int roundId}) async {
    await _db.db.transaction((txn) async {
      final rows = await txn.query(
        'rounds',
        columns: <String>['id', 'game_id', 'round_number', 'status'],
        where: 'id = ?',
        whereArgs: <Object?>[roundId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw ArgumentError.value(roundId, 'roundId', 'No such round');
      }

      final row = rows.first;
      final status = RoundStatus.fromDb(row['status'] as String? ?? 'pending');
      if (status == RoundStatus.complete || status == RoundStatus.skipped) {
        throw StateError('Round ${row['round_number']} cannot be skipped');
      }

      final gameId = row['game_id'] as int;

      // Drop anything already typed into this round; it is being passed over.
      await txn.delete(
        'round_entries',
        where: 'round_id = ?',
        whereArgs: <Object?>[roundId],
      );
      await txn.update(
        'rounds',
        <String, Object?>{'status': RoundStatus.skipped.dbValue},
        where: 'id = ?',
        whereArgs: <Object?>[roundId],
      );

      // Land the game on the first round that is neither scored nor skipped.
      final unresolved = await txn.query(
        'rounds',
        columns: <String>['round_number'],
        where: 'game_id = ? AND status NOT IN (?, ?)',
        whereArgs: <Object?>[
          gameId,
          RoundStatus.complete.dbValue,
          RoundStatus.skipped.dbValue,
        ],
        orderBy: 'round_number ASC',
        limit: 1,
      );
      final next = unresolved.isEmpty
          ? 0
          : unresolved.first['round_number'] as int;

      await txn.update(
        'games',
        <String, Object?>{'current_round': next},
        where: 'id = ?',
        whereArgs: <Object?>[gameId],
      );
    });
  }

  /// Time travel: rewinds a game to the end of [targetRound].
  ///
  /// Everything after [targetRound] is erased and the game becomes playable
  /// again from that point. Because scoring is memoryless (a round's points
  /// depend only on that round's bid and tricks), rewinding is a truncate plus
  /// a re-sum, not a replay.
  ///
  /// If the game had already been finalised, its win is un-counted, so the
  /// leaderboard immediately stops crediting it.
  ///
  /// Rewinding to the last played round is exactly "undo last round".
  Future<void> rewindTo({required int gameId, required int targetRound}) async {
    if (targetRound < 0) {
      throw ArgumentError.value(
        targetRound,
        'targetRound',
        'Cannot rewind before the start of the game',
      );
    }

    await _db.db.transaction((txn) async {
      // 1. Drop every entry after the target round.
      await txn.rawDelete(
        '''
        DELETE FROM round_entries
        WHERE round_id IN (
          SELECT id FROM rounds WHERE game_id = ? AND round_number > ?
        )
      ''',
        <Object?>[gameId, targetRound],
      );

      // 2. Those rounds go back to unplayed, skipping and all.
      await txn.update(
        'rounds',
        <String, Object?>{'status': RoundStatus.pending.dbValue},
        where: 'game_id = ? AND round_number > ?',
        whereArgs: <Object?>[gameId, targetRound],
      );

      // 3. Un-finalise the game: no winners, not counted, back in progress.
      await txn.delete(
        'game_winners',
        where: 'game_id = ?',
        whereArgs: <Object?>[gameId],
      );
      await txn.update(
        'game_players',
        <String, Object?>{'final_rank': null},
        where: 'game_id = ?',
        whereArgs: <Object?>[gameId],
      );
      await txn.update(
        'games',
        <String, Object?>{
          'status': GameStatus.inProgress.dbValue,
          'current_round': targetRound + 1,
          'ended_at': null,
          'wins_counted': 0,
        },
        where: 'id = ?',
        whereArgs: <Object?>[gameId],
      );

      // 4. Re-sum the survivors.
      await _recomputeTotals(txn, gameId);
    });
  }

  /// Finalises a game: ranks the table, records the winner(s) and flags the win
  /// as counted so the leaderboard picks it up.
  ///
  /// Safe to call twice: winners are replaced rather than appended, and the
  /// leaderboard counts win rows rather than incrementing a counter.
  Future<void> finishGame({required int gameId, DateTime? endedAt}) async {
    final ended = endedAt ?? DateTime.now();

    await _db.db.transaction((txn) async {
      final rows = await txn.query(
        'game_players',
        columns: <String>['player_id', 'seat', 'total_score'],
        where: 'game_id = ?',
        whereArgs: <Object?>[gameId],
        orderBy: 'seat ASC',
      );

      final scores = rows
          .map((row) => row['total_score'] as int)
          .toList(growable: false);
      final winners = winnerSeats(scores);

      // Standard competition ranking: equal scores share the lower rank.
      final order = List<int>.generate(rows.length, (i) => i)
        ..sort((a, b) => scores[b].compareTo(scores[a]));
      final ranks = List<int>.filled(rows.length, 0);
      var currentRank = 0;
      var previousScore = -1 << 40;
      for (var position = 0; position < order.length; position++) {
        final index = order[position];
        if (scores[index] != previousScore) {
          currentRank = position + 1;
          previousScore = scores[index];
        }
        ranks[index] = currentRank;
      }

      await txn.delete(
        'game_winners',
        where: 'game_id = ?',
        whereArgs: <Object?>[gameId],
      );
      for (final index in winners) {
        await txn.insert('game_winners', <String, Object?>{
          'game_id': gameId,
          'player_id': rows[index]['player_id'] as int,
        });
      }

      for (var index = 0; index < rows.length; index++) {
        await txn.update(
          'game_players',
          <String, Object?>{'final_rank': ranks[index]},
          where: 'game_id = ? AND player_id = ?',
          whereArgs: <Object?>[gameId, rows[index]['player_id']],
        );
      }

      await _recomputeTotals(txn, gameId);

      await txn.update(
        'games',
        <String, Object?>{
          'status': GameStatus.finished.dbValue,
          'ended_at': ended.millisecondsSinceEpoch,
          'wins_counted': 1,
        },
        where: 'id = ?',
        whereArgs: <Object?>[gameId],
      );
    });
  }

  /// Ends a game without crediting anybody: no winner rows, no ranks, and the
  /// win deliberately left uncounted so the leaderboard never sees it.
  ///
  /// The scores played stay on the sheet, so history still shows the game; this
  /// is for a table that stopped early and does not want it on the leaderboard.
  Future<void> discardGame({required int gameId, DateTime? endedAt}) async {
    final ended = endedAt ?? DateTime.now();

    await _db.db.transaction((txn) async {
      await txn.delete(
        'game_winners',
        where: 'game_id = ?',
        whereArgs: <Object?>[gameId],
      );
      await txn.update(
        'game_players',
        <String, Object?>{'final_rank': null},
        where: 'game_id = ?',
        whereArgs: <Object?>[gameId],
      );
      await txn.update(
        'games',
        <String, Object?>{
          'status': GameStatus.finished.dbValue,
          'ended_at': ended.millisecondsSinceEpoch,
          'wins_counted': 0,
        },
        where: 'id = ?',
        whereArgs: <Object?>[gameId],
      );
    });
  }

  /// The leaderboard, derived entirely from game history.
  ///
  /// `wins` counts win rows on games that are finished *and* flagged as counted,
  /// so rewinding a finished game instantly removes its win with no decrement
  /// logic anywhere. `gamesPlayed` counts finished games the player sat in.
  ///
  /// Archiving a player hides them but keeps their history intact.
  Future<List<LeaderboardRow>> leaderboard({
    bool includeArchived = false,
  }) async {
    final rows = await _db.db.rawQuery(
      '''
      SELECT p.id          AS pid,
             p.name        AS pname,
             p.color_index AS pcolor,
             p.is_archived AS parchived,
             (SELECT COUNT(*)
                FROM game_winners w
                JOIN games g ON g.id = w.game_id
               WHERE w.player_id = p.id
                 AND g.status = 'finished'
                 AND g.wins_counted = 1) AS wins,
             (SELECT COUNT(*)
                FROM game_players gp
                JOIN games g2 ON g2.id = gp.game_id
               WHERE gp.player_id = p.id
                 AND g2.status = 'finished') AS played
      FROM players p
      WHERE ? = 1 OR p.is_archived = 0
    ''',
      <Object?>[includeArchived ? 1 : 0],
    );

    final leaderboard =
        rows
            .map(
              (row) => LeaderboardRow(
                player: Player(
                  id: row['pid'] as int,
                  name: row['pname'] as String,
                  colorIndex: (row['pcolor'] as int?) ?? 0,
                  isArchived: (row['parchived'] as int? ?? 0) == 1,
                ),
                wins: row['wins'] as int,
                gamesPlayed: row['played'] as int,
              ),
            )
            .toList()
          ..sort(LeaderboardRow.compare);

    return leaderboard;
  }

  /// Finished and abandoned games, newest first.
  Future<List<GameSummary>> history({int limit = 50}) async {
    final gameRows = await _db.db.query(
      'games',
      orderBy: 'started_at DESC',
      limit: limit,
    );
    if (gameRows.isEmpty) return const <GameSummary>[];

    final ids = gameRows.map((row) => row['id'] as int).toList(growable: false);
    final placeholders = List<String>.filled(ids.length, '?').join(', ');

    final playerRows = await _db.db.rawQuery('''
      SELECT gp.game_id      AS game_id,
             gp.seat         AS seat,
             gp.total_score  AS total_score,
             gp.final_rank   AS final_rank,
             p.id            AS pid,
             p.name          AS pname,
             p.color_index   AS pcolor,
             p.is_archived   AS parchived
      FROM game_players gp
      JOIN players p ON p.id = gp.player_id
      WHERE gp.game_id IN ($placeholders)
      ORDER BY gp.seat ASC
    ''', ids);

    final winnerRows = await _db.db.rawQuery('''
      SELECT game_id, player_id FROM game_winners
      WHERE game_id IN ($placeholders)
    ''', ids);

    final standingsByGame = <int, List<Standing>>{};
    for (final row in playerRows) {
      final gameId = row['game_id'] as int;
      standingsByGame
          .putIfAbsent(gameId, () => <Standing>[])
          .add(
            Standing(
              player: Player(
                id: row['pid'] as int,
                name: row['pname'] as String,
                colorIndex: (row['pcolor'] as int?) ?? 0,
                isArchived: (row['parchived'] as int? ?? 0) == 1,
              ),
              seat: row['seat'] as int,
              totalScore: row['total_score'] as int,
              finalRank: row['final_rank'] as int?,
            ),
          );
    }

    final winnersByGame = <int, List<int>>{};
    for (final row in winnerRows) {
      winnersByGame
          .putIfAbsent(row['game_id'] as int, () => <int>[])
          .add(row['player_id'] as int);
    }

    return gameRows
        .map((row) {
          final id = row['id'] as int;
          final game = Game.fromMap(
            row,
            winnerPlayerIds: winnersByGame[id] ?? const <int>[],
          );
          return GameSummary(
            id: id,
            startedAt: game.startedAt,
            endedAt: game.endedAt,
            status: game.status,
            standings: standingsByGame[id] ?? const <Standing>[],
            winnerPlayerIds: game.winnerPlayerIds,
            winsCounted: game.winsCounted,
          );
        })
        .toList(growable: false);
  }

  /// Deletes a game and everything hanging off it. Used by the "discard game"
  /// escape hatch, never for a game that counts on the leaderboard.
  Future<void> deleteGame(int gameId) async {
    await _db.db.delete('games', where: 'id = ?', whereArgs: <Object?>[gameId]);
  }
}
