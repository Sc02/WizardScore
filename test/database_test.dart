import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wizard_score/data/db.dart';
import 'package:wizard_score/data/game_repository.dart';
import 'package:wizard_score/data/player_repository.dart';
import 'package:wizard_score/domain/rules.dart';
import 'package:wizard_score/models/game.dart';
import 'package:wizard_score/models/round.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late WizardDatabase db;
  late PlayerRepository players;
  late GameRepository games;

  setUp(() async {
    // A fresh in-memory database per test, so tests cannot leak into each other.
    db = await WizardDatabase.open(factory: databaseFactoryFfi, inMemory: true);
    players = PlayerRepository(db);
    games = GameRepository(db);
  });

  tearDown(() => db.close());

  /// Seeds [count] players and returns their ids in seat order.
  ///
  /// [tag] keeps names unique when a single test seeds more than one table.
  Future<List<int>> seedPlayers(int count, {String tag = ''}) async {
    final ids = <int>[];
    for (var i = 0; i < count; i++) {
      final player = await players.create(name: 'Player$tag $i', colorIndex: i);
      ids.add(player.id!);
    }
    return ids;
  }

  /// Plays one round: saves and locks bids, then scores the tricks.
  Future<void> playRound(
    int gameId, {
    required List<int> bids,
    required List<int> tricks,
  }) async {
    final state = (await games.loadGame(gameId))!;
    final round = state.nextRound!;
    final ids = state.standings
        .map((standing) => standing.player.id!)
        .toList(growable: false);

    await games.saveBids(round.id!, <int, int>{
      for (var i = 0; i < ids.length; i++) ids[i]: bids[i],
    });
    await games.lockBids(round.id!);
    await games.completeRound(
      gameId: gameId,
      roundId: round.id!,
      roundNumber: round.roundNumber,
      cardsDealt: round.cardsDealt,
      tricksWon: <int, int>{
        for (var i = 0; i < ids.length; i++) ids[i]: tricks[i],
      },
      totalRounds: state.roundsPerPlayer,
    );
  }

  group('players', () {
    test('creates a player and reads them back', () async {
      final created = await players.create(name: 'Suchit', colorIndex: 3);
      expect(created.id, isNotNull);

      final all = await players.listActive();
      expect(all, hasLength(1));
      expect(all.single.name, 'Suchit');
      expect(all.single.colorIndex, 3);
    });

    test('rejects a duplicate name exactly', () async {
      await players.create(name: 'Suchit');
      expect(
        () => players.create(name: 'Suchit'),
        throwsA(isA<DuplicatePlayerNameException>()),
      );
    });

    test('rejects a duplicate name ignoring case', () async {
      await players.create(name: 'Suchit');
      expect(
        () => players.create(name: 'SUCHIT'),
        throwsA(isA<DuplicatePlayerNameException>()),
      );
    });

    test('rejects a duplicate name ignoring extra whitespace', () async {
      await players.create(name: 'Suchit Rao');
      expect(
        () => players.create(name: '  Suchit   Rao  '),
        throwsA(isA<DuplicatePlayerNameException>()),
      );
    });

    test('nameProblem gives the message the form will show', () async {
      await players.create(name: 'Marie');
      expect(await players.nameProblem('Marie'),
          "A player named 'Marie' already exists");
      expect(await players.nameProblem('  marie '),
          "A player named 'Marie' already exists");
      expect(await players.nameProblem('Paul'), isNull);
      expect(await players.nameProblem('   '), 'Enter a name');
      expect(await players.nameProblem('A'), 'Names need at least 2 characters');
    });

    test('renaming onto another player is blocked, keeping your own name is not',
        () async {
      final a = await players.create(name: 'Anna');
      await players.create(name: 'Bob');

      expect(
        () => players.update(a.copyWith(name: 'Bob')),
        throwsA(isA<DuplicatePlayerNameException>()),
      );

      final renamed = await players.update(a.copyWith(name: 'Anna B'));
      expect(renamed.name, 'Anna B');
    });

    test('archiving hides a player from the roster', () async {
      final player = await players.create(name: 'Temp');
      await players.archive(player.id!);
      expect(await players.listActive(), isEmpty);

      expect(await games.leaderboard(), isEmpty);
      final includingArchived = await games.leaderboard(includeArchived: true);
      expect(includingArchived, hasLength(1));
    });
  });

  group('starting a game', () {
    test('pre-creates every round with the right deal and dealer', () async {
      final ids = await seedPlayers(4);
      final gameId = await games.startGame(playerIds: ids);
      final state = (await games.loadGame(gameId))!;

      expect(state.rounds, hasLength(15));
      expect(state.roundsPerPlayer, 15);
      expect(state.rounds.first.cardsDealt, 1);
      expect(state.rounds.last.cardsDealt, 15);
      expect(state.game.currentRound, 1);
      expect(state.game.status, GameStatus.inProgress);
      expect(state.nextRound!.roundNumber, 1);

      // Dealer rotates one seat per round.
      expect(
        state.rounds.take(5).map((round) => round.dealerSeat).toList(),
        <int>[0, 1, 2, 3, 0],
      );

      // Nobody has a score or a bid yet.
      for (final standing in state.standings) {
        expect(standing.totalScore, 0);
      }
      expect(state.entriesFor(state.rounds.first), hasLength(4));
      expect(state.entriesFor(state.rounds.first).first.bid, isNull);
    });

    test('round counts follow the table size', () async {
      for (final size in <int>[3, 4, 5, 6]) {
        final ids = await seedPlayers(size, tag: 'S$size');
        final gameId = await games.startGame(playerIds: ids);
        final state = (await games.loadGame(gameId))!;
        expect(state.rounds, hasLength(roundsForPlayers(size)));
        expect(state.standings, hasLength(size));
      }
    });

    test('refuses an unsupported table size and duplicate seats', () async {
      final one = await seedPlayers(1, tag: 'one');
      expect(() => games.startGame(playerIds: one), throwsArgumentError);

      final seven = await seedPlayers(7, tag: 'seven');
      expect(() => games.startGame(playerIds: seven), throwsArgumentError);

      final ids = await seedPlayers(3, tag: 'dup');
      expect(
        () => games.startGame(playerIds: <int>[ids[0], ids[0], ids[1]]),
        throwsArgumentError,
      );
    });

    test('loadCurrentGame finds the live game', () async {
      final ids = await seedPlayers(3);
      final gameId = await games.startGame(playerIds: ids);
      final current = await games.loadCurrentGame();
      expect(current!.game.id, gameId);
    });
  });

  group('playing a whole game', () {
    test('scores every round and totals correctly', () async {
      final ids = await seedPlayers(4);
      final gameId = await games.startGame(playerIds: ids);

      // Seat 0 calls the whole hand and takes every trick; the others bid
      // zero and make it. Round `r` is therefore `r` played tricks in total.
      for (var round = 1; round <= 15; round++) {
        await playRound(
          gameId,
          bids: <int>[round, 0, 0, 0],
          tricks: <int>[round, 0, 0, 0],
        );
      }

      final state = (await games.loadGame(gameId))!;
      expect(state.isGameOver, isTrue);

      // Seat 0: 20 + 10r per round => 15*20 + 10*(1+2+...+15) = 300 + 1200.
      const seatZeroExpected = 15 * 20 + 10 * 120;
      expect(seatZeroExpected, 1500);
      expect(state.standings[0].totalScore, seatZeroExpected);
      for (var seat = 1; seat < 4; seat++) {
        // Bid 0 and took 0 every round => 20 per round, 300 over the game.
        expect(state.standings[seat].totalScore, 15 * 20);
      }

      // Winner is clear and unique.
      expect(state.winnerSeatsNow(), <int>[0]);
    });

    test('finishing records the winner and credits the leaderboard', () async {
      final ids = await seedPlayers(4, tag: 'finish');
      final gameId = await games.startGame(playerIds: ids);
      for (var round = 1; round <= 15; round++) {
        await playRound(
          gameId,
          bids: <int>[round, 0, 0, 0],
          tricks: <int>[round, 0, 0, 0],
        );
      }

      await games.finishGame(gameId: gameId);

      final finished = (await games.loadGame(gameId))!;
      expect(finished.game.status, GameStatus.finished);
      expect(finished.game.winsCounted, isTrue);
      expect(finished.game.winnerPlayerIds, <int>[ids[0]]);
      expect(finished.game.endedAt, isNotNull);

      // Ranks: winner 1st, the three way tie for last shares rank 2.
      expect(finished.standings[0].finalRank, 1);
      for (var seat = 1; seat < 4; seat++) {
        expect(finished.standings[seat].finalRank, 2);
      }

      final board = await games.leaderboard();
      final winner = board.firstWhere((row) => row.player.id == ids[0]);
      expect(winner.wins, 1);
      expect(winner.gamesPlayed, 1);

      final other = board.firstWhere((row) => row.player.id == ids[1]);
      expect(other.wins, 0);
      expect(other.gamesPlayed, 1);
    });

    test('finishing twice does not double count the win', () async {
      final ids = await seedPlayers(3, tag: 'twice');
      final gameId = await games.startGame(playerIds: ids);
      for (var round = 1; round <= 20; round++) {
        await playRound(
          gameId,
          bids: <int>[round, 0, 0],
          tricks: <int>[round, 0, 0],
        );
      }

      await games.finishGame(gameId: gameId);
      await games.finishGame(gameId: gameId);

      final board = await games.leaderboard();
      expect(board.firstWhere((row) => row.player.id == ids[0]).wins, 1);
      // No phantom co-winners from the second call.
      final finished = (await games.loadGame(gameId))!;
      expect(finished.game.winnerPlayerIds, <int>[ids[0]]);
    });
  });

  group('time travel', () {
    /// Seat 0 calls the whole hand and takes every trick; the others bid zero
    /// and make it. After `n` rounds seat 0 has `20n + 10*T(n)` and everyone
    /// else `20n`, where T(n) is the n-th triangular number.
    ///
    /// Takes an explicit round range so a replay after a rewind resumes at the
    /// right round instead of restarting the game.
    Future<void> playRounds(
      int gameId,
      int from,
      int to, {
      int players = 4,
    }) async {
      for (var round = from; round <= to; round++) {
        await playRound(
          gameId,
          bids: <int>[round, ...List<int>.filled(players - 1, 0)],
          tricks: <int>[round, ...List<int>.filled(players - 1, 0)],
        );
      }
    }

    int triangular(int n) => n * (n + 1) ~/ 2;

    test('rewinding erases later rounds and recalculates the totals', () async {
      final ids = await seedPlayers(4, tag: 'rw');
      final gameId = await games.startGame(playerIds: ids);
      await playRounds(gameId, 1, 5);

      final before = (await games.loadGame(gameId))!;
      expect(before.standings[0].totalScore, 5 * 20 + 10 * triangular(5));
      expect(before.standings[1].totalScore, 5 * 20);
      expect(before.lastPlayedRound, 5);

      await games.rewindTo(gameId: gameId, targetRound: 2);

      final after = (await games.loadGame(gameId))!;
      expect(after.standings[0].totalScore, 2 * 20 + 10 * triangular(2));
      expect(after.standings[1].totalScore, 2 * 20);

      // The erased rounds are unplayed and playable again.
      expect(after.lastPlayedRound, 2);
      expect(after.game.currentRound, 3);
      expect(after.nextRound!.roundNumber, 3);

      for (final round in after.rounds) {
        if (round.roundNumber <= 2) {
          expect(round.status, RoundStatus.complete);
        } else {
          expect(round.status, RoundStatus.pending);
          // Bids, tricks and points are gone; only the seat rows remain.
          for (final entry in after.entriesFor(round)) {
            expect(entry.bid, isNull);
            expect(entry.tricksWon, isNull);
            expect(entry.points, isNull);
          }
        }
      }

      // Replaying the erased rounds restores the original standings exactly.
      await playRounds(gameId, 3, 5);
      final replayed = (await games.loadGame(gameId))!;
      expect(replayed.standings[0].totalScore, before.standings[0].totalScore);
      expect(replayed.standings[1].totalScore, before.standings[1].totalScore);
    });

    test('undo last round is a rewind of exactly one round', () async {
      final ids = await seedPlayers(4, tag: 'undo');
      final gameId = await games.startGame(playerIds: ids);
      await playRounds(gameId, 1, 4);

      await games.rewindTo(gameId: gameId, targetRound: 3);

      final after = (await games.loadGame(gameId))!;
      expect(after.lastPlayedRound, 3);
      expect(after.game.currentRound, 4);
      expect(after.standings[0].totalScore, 3 * 20 + 10 * triangular(3));
    });

    test('rewinding to zero clears the whole game', () async {
      final ids = await seedPlayers(3, tag: 'zero');
      final gameId = await games.startGame(playerIds: ids);
      await playRounds(gameId, 1, 4, players: 3);

      await games.rewindTo(gameId: gameId, targetRound: 0);

      final after = (await games.loadGame(gameId))!;
      expect(after.lastPlayedRound, 0);
      expect(after.game.currentRound, 1);
      for (final standing in after.standings) {
        expect(standing.totalScore, 0);
      }
    });

    test('rewinding a finished game removes its win from the leaderboard',
        () async {
      final ids = await seedPlayers(4, tag: 'rwfin');
      final gameId = await games.startGame(playerIds: ids);
      await playRounds(gameId, 1, 15);
      await games.finishGame(gameId: gameId);

      var board = await games.leaderboard();
      expect(board.firstWhere((row) => row.player.id == ids[0]).wins, 1);

      // Travel back to before the last round.
      await games.rewindTo(gameId: gameId, targetRound: 14);

      final rewound = (await games.loadGame(gameId))!;
      expect(rewound.game.status, GameStatus.inProgress);
      expect(rewound.game.winsCounted, isFalse);
      expect(rewound.game.winnerPlayerIds, isEmpty);
      expect(rewound.game.endedAt, isNull);
      expect(rewound.standings[0].finalRank, isNull);

      // The win is no longer credited, and the game counts as unplayed.
      board = await games.leaderboard();
      final winner = board.firstWhere((row) => row.player.id == ids[0]);
      expect(winner.wins, 0);
      expect(winner.gamesPlayed, 0);

      // Replaying and finishing again credits exactly one win.
      await playRounds(gameId, 15, 15);
      await games.finishGame(gameId: gameId);
      board = await games.leaderboard();
      expect(board.firstWhere((row) => row.player.id == ids[0]).wins, 1);
    });

    test('cannot rewind before the start of the game', () async {
      final ids = await seedPlayers(3, tag: 'neg');
      final gameId = await games.startGame(playerIds: ids);
      expect(
        () => games.rewindTo(gameId: gameId, targetRound: -1),
        throwsArgumentError,
      );
    });
  });

  group('skipping a round', () {
    test('marks it skipped, drops its bids and moves the game on', () async {
      final ids = await seedPlayers(3, tag: 'skip');
      final gameId = await games.startGame(playerIds: ids);

      // Type bids into round 1 first: a skip has to throw them away.
      final before = (await games.loadGame(gameId))!;
      final round1 = before.nextRound!;
      await games.saveBids(round1.id!, <int, int>{for (final id in ids) id: 1});

      await games.skipRound(roundId: round1.id!);

      final after = (await games.loadGame(gameId))!;
      expect(after.roundByNumber(1)!.status, RoundStatus.skipped);
      expect(after.roundByNumber(1)!.isSkipped, isTrue);
      expect(after.roundByNumber(1)!.isResolved, isTrue);
      expect(after.roundByNumber(1)!.isComplete, isFalse);

      // The bids are gone; the round still has a row per seat to render.
      expect(after.entriesFor(after.roundByNumber(1)!), hasLength(3));
      expect(after.entriesFor(after.roundByNumber(1)!).first.bid, isNull);

      expect(after.nextRound!.roundNumber, 2);
      expect(after.game.currentRound, 2);
      expect(after.lastPlayedRound, 0);
      expect(after.skippedRoundNumbers, <int>[1]);
      expect(after.isGameOver, isFalse);

      for (final standing in after.standings) {
        expect(standing.totalScore, 0);
      }
    });

    test('skipping every round ends the game without scoring it', () async {
      final ids = await seedPlayers(2, tag: 'lastskip');
      final gameId = await games.startGame(playerIds: ids);

      final before = (await games.loadGame(gameId))!;
      for (final round in before.rounds) {
        await games.skipRound(roundId: round.id!);
      }

      final after = (await games.loadGame(gameId))!;
      expect(after.isGameOver, isTrue);
      expect(after.nextRound, isNull);
      expect(after.lastResolvedRound, before.rounds.length);
      expect(after.lastPlayedRound, 0);
      expect(after.skippedRoundCount, before.rounds.length);
    });

    test('a round that was already scored cannot be skipped', () async {
      final ids = await seedPlayers(3, tag: 'done');
      final gameId = await games.startGame(playerIds: ids);
      await playRound(
        gameId,
        bids: <int>[1, 0, 0],
        tricks: <int>[1, 0, 0],
      );

      final round1 = (await games.loadGame(gameId))!.roundByNumber(1)!;
      expect(() => games.skipRound(roundId: round1.id!), throwsStateError);
    });

    test('rewinding before a skipped round puts it back on the table',
        () async {
      final ids = await seedPlayers(3, tag: 'rew');
      final gameId = await games.startGame(playerIds: ids);
      await playRound(gameId, bids: <int>[1, 0, 0], tricks: <int>[1, 0, 0]);

      final s1 = (await games.loadGame(gameId))!;
      await games.skipRound(roundId: s1.nextRound!.id!); // round 2

      await playRound(gameId, bids: <int>[3, 0, 0], tricks: <int>[3, 0, 0]);

      final before = (await games.loadGame(gameId))!;
      expect(before.skippedRoundNumbers, <int>[2]);
      expect(before.lastResolvedRound, 3);
      expect(before.lastPlayedRound, 3);

      await games.rewindTo(gameId: gameId, targetRound: 1);

      final after = (await games.loadGame(gameId))!;
      expect(after.roundByNumber(2)!.status, RoundStatus.pending);
      expect(after.roundByNumber(3)!.status, RoundStatus.pending);
      expect(after.skippedRoundCount, 0);
      expect(after.nextRound!.roundNumber, 2);
      expect(after.lastPlayedRound, 1);
      expect(after.standings.first.totalScore, 30);
    });
  });

  group('finishing a game early', () {
    test('stops after one round and credits only the leader', () async {
      final ids = await seedPlayers(3, tag: 'early');
      final gameId = await games.startGame(playerIds: ids);
      await playRound(gameId, bids: <int>[1, 0, 0], tricks: <int>[1, 0, 0]);

      await games.finishGame(gameId: gameId);

      final finished = (await games.loadGame(gameId))!;
      expect(finished.game.status, GameStatus.finished);
      expect(finished.game.winsCounted, isTrue);
      expect(finished.game.winnerPlayerIds, <int>[ids[0]]);
      expect(finished.lastPlayedRound, 1);
      // Rounds nobody played stay untouched on the sheet.
      expect(finished.roundByNumber(10)!.status, RoundStatus.pending);
      expect(finished.standings[0].finalRank, 1);
      expect(finished.standings[1].finalRank, 2);

      final board = await games.leaderboard();
      expect(board.firstWhere((row) => row.player.id == ids[0]).wins, 1);
      expect(board.firstWhere((row) => row.player.id == ids[1]).wins, 0);
      expect(board.firstWhere((row) => row.player.id == ids[0]).gamesPlayed, 1);
    });

    test('credits the sole leader when the top score is unique', () async {
      final ids = await seedPlayers(3, tag: 'tie');
      final gameId = await games.startGame(playerIds: ids);
      await playRound(gameId, bids: <int>[1, 0, 0], tricks: <int>[1, 0, 0]);

      await games.finishGame(gameId: gameId);

      final finished = (await games.loadGame(gameId))!;
      // Seat 0 made its bid (30) while the others made theirs (20 each).
      expect(finished.game.winnerPlayerIds, <int>[ids[0]]);

      final board = await games.leaderboard();
      expect(board.firstWhere((row) => row.player.id == ids[0]).wins, 1);
      expect(board.firstWhere((row) => row.player.id == ids[1]).wins, 0);
    });

    test('finishing twice from a half-played game counts one win', () async {
      final ids = await seedPlayers(3, tag: 'twiceearly');
      final gameId = await games.startGame(playerIds: ids);
      await playRound(gameId, bids: <int>[1, 0, 0], tricks: <int>[1, 0, 0]);

      await games.finishGame(gameId: gameId);
      await games.finishGame(gameId: gameId);

      final board = await games.leaderboard();
      expect(board.firstWhere((row) => row.player.id == ids[0]).wins, 1);
      expect(
        (await games.loadGame(gameId))!.game.winnerPlayerIds,
        <int>[ids[0]],
      );
    });
  });

  group('round validation', () {
    test('rejects tricks that do not add up to the cards dealt', () async {
      final ids = await seedPlayers(4, tag: 'bad');
      final gameId = await games.startGame(playerIds: ids);
      final state = (await games.loadGame(gameId))!;
      final round = state.nextRound!;

      await games.saveBids(round.id!, <int, int>{for (final id in ids) id: 0});
      await games.lockBids(round.id!);

      // Round 1 is a single played trick; claiming two of them is a
      // data-entry error and is refused.
      expect(
        () => games.completeRound(
          gameId: gameId,
          roundId: round.id!,
          roundNumber: 1,
          cardsDealt: 1,
          tricksWon: <int, int>{
            ids[0]: 1,
            ids[1]: 1,
            ids[2]: 0,
            ids[3]: 0,
          },
          totalRounds: state.roundsPerPlayer,
        ),
        throwsA(isA<RoundValidationException>()),
      );

      // The failed attempt left the round untouched.
      final after = (await games.loadGame(gameId))!;
      expect(after.lastPlayedRound, 0);
      expect(after.rounds.first.status, isNot(RoundStatus.complete));
    });

    test('rejects scoring a round whose bids were never entered', () async {
      final ids = await seedPlayers(4, tag: 'nobid');
      final gameId = await games.startGame(playerIds: ids);
      final roundId = (await games.loadGame(gameId))!.nextRound!.id!;

      expect(
        () => games.completeRound(
          gameId: gameId,
          roundId: roundId,
          roundNumber: 1,
          cardsDealt: 1,
          tricksWon: <int, int>{
            ids[0]: 1,
            ids[1]: 0,
            ids[2]: 0,
            ids[3]: 0,
          },
          totalRounds: 15,
        ),
        throwsA(isA<RoundValidationException>()),
      );
    });

    test('rejects a trick count larger than the hand', () async {
      final ids = await seedPlayers(4, tag: 'huge');
      final gameId = await games.startGame(playerIds: ids);
      final round = (await games.loadGame(gameId))!.nextRound!;

      await games.saveBids(round.id!, <int, int>{for (final id in ids) id: 0});
      await games.lockBids(round.id!);

      expect(
        () => games.completeRound(
          gameId: gameId,
          roundId: round.id!,
          roundNumber: 1,
          cardsDealt: 1,
          // Adds to 2 so the table total check fails first, and seat 0 also
          // claims two tricks from a single card.
          tricksWon: <int, int>{ids[0]: 2, ids[1]: 0, ids[2]: 0, ids[3]: 0},
          totalRounds: 15,
        ),
        throwsA(isA<RoundValidationException>()),
      );
    });
  });
}