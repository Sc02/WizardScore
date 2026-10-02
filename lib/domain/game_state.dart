import 'rules.dart';
import '../models/game.dart';
import '../models/round.dart';

/// Everything needed to render a game: the game row, its seats, its rounds and
/// every bid/trick entry, plus the derived totals.
///
/// This is a read model. Nothing here writes to the database; the repositories
/// produce it and the UI consumes it.
class GameState {
  const GameState({
    required this.game,
    required this.standings,
    required this.rounds,
    required this.roundsPerPlayer,
    this.entriesByRound = const <int, List<RoundEntry>>{},
  });

  final Game game;

  /// Seats in table order (0-based seat ascending wins shows first).
  final List<Standing> standings;

  /// Every round for this game, ordered by [Round.roundNumber].
  final List<Round> rounds;

  /// Total rounds in the game, from the table size.
  final int roundsPerPlayer;

  /// Round id -> that round's entries.
  final Map<int, List<RoundEntry>> entriesByRound;

  List<Standing> get standingsByScore {
    final sorted = List<Standing>.of(standings)
      ..sort((a, b) {
        final byScore = b.totalScore.compareTo(a.totalScore);
        return byScore != 0 ? byScore : a.seat.compareTo(b.seat);
      });
    return sorted;
  }

  Standing get leader => standingsByScore.first;

  /// The round that is up next, or `null` when the game is over.
  ///
  /// Skipped rounds are jumped over, so the counter lands on the first round
  /// that is neither scored nor deliberately passed on.
  Round? get nextRound {
    for (final round in rounds) {
      if (round.roundNumber == game.currentRound && !round.isResolved) {
        return round;
      }
    }
    for (final round in rounds) {
      if (!round.isResolved) return round;
    }
    return null;
  }

  /// Highest round number that has been scored, or 0 if none.
  int get lastPlayedRound {
    var last = 0;
    for (final round in rounds) {
      if (round.isComplete && round.roundNumber > last) {
        last = round.roundNumber;
      }
    }
    return last;
  }

  /// Rounds the table chose not to play, in ascending order.
  List<int> get skippedRoundNumbers => <int>[
    for (final round in rounds)
      if (round.isSkipped) round.roundNumber,
  ];

  int get skippedRoundCount => skippedRoundNumbers.length;

  /// Highest round number that is either scored or skipped, or 0 if none.
  ///
  /// This is what a rewind has to undo through: a skipped round counts here
  /// even though it contributes no points, because rewinding past it should
  /// put it back on the table.
  int get lastResolvedRound {
    var last = 0;
    for (final round in rounds) {
      if (round.isResolved && round.roundNumber > last) {
        last = round.roundNumber;
      }
    }
    return last;
  }

  /// True once at least one round has been scored. Finishing a game before
  /// this would leave every seat on zero and credit the win to the whole table.
  bool get hasPlayedRounds => rounds.any((round) => round.isComplete);

  bool get isGameOver =>
      rounds.isNotEmpty && rounds.every((round) => round.isResolved);

  bool get isFinished => game.isFinished;

  /// A round is "in flight" once bids have been written but before it is
  /// scored. Rewinding across one of these needs extra confirmation.
  bool get hasRoundInFlight =>
      rounds.any((round) => round.status == RoundStatus.bidsLocked);

  Round? roundByNumber(int roundNumber) {
    for (final round in rounds) {
      if (round.roundNumber == roundNumber) return round;
    }
    return null;
  }

  /// Entries for a round, ordered to match [standings] seat order.
  List<RoundEntry> entriesFor(Round round) {
    final entries = round.id == null
        ? const <RoundEntry>[]
        : (entriesByRound[round.id!] ?? const <RoundEntry>[]);
    final byPlayer = <int, RoundEntry>{
      for (final entry in entries) entry.playerId: entry,
    };
    return <RoundEntry>[
      for (final standing in standings)
        if (standing.player.id != null)
          byPlayer[standing.player.id!] ??
              RoundEntry(roundId: round.id ?? 0, playerId: standing.player.id!),
    ];
  }

  /// Points each player scored in [round], in seat order. Nulls become 0 so the
  /// score sheet can add up a partially played game.
  List<int> pointsFor(Round round) =>
      entriesFor(round)
          .map((entry) => entry.points ?? 0)
          .toList(growable: false);

  /// Total score contributed by [round] across the table, for the rewind
  /// preview sheet.
  int roundPointsDelta(Round round) => totalScore(pointsFor(round));

  /// Points each player scored across rounds 1..[upToRound], in seat order.
  List<int> totalsUpTo(int upToRound) {
    final totals = List<int>.filled(standings.length, 0);
    for (final round in rounds) {
      if (round.roundNumber > upToRound || !round.isComplete) continue;
      final points = pointsFor(round);
      for (var i = 0; i < totals.length && i < points.length; i++) {
        totals[i] += points[i];
      }
    }
    return totals;
  }

  /// Winner seats for the current totals, using the same tie rule as the app.
  List<int> winnerSeatsNow() =>
      winnerSeats(standings.map((standing) => standing.totalScore));
}
