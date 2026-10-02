import 'player.dart';

/// A game's lifecycle.
enum GameStatus {
  inProgress,
  finished;

  static GameStatus fromDb(String value) =>
      value == 'finished' ? GameStatus.finished : GameStatus.inProgress;

  String get dbValue =>
      this == GameStatus.finished ? 'finished' : 'in_progress';
}

/// One seated player's standing within a game, joined from `game_players`.
class Standing {
  const Standing({
    required this.player,
    required this.seat,
    required this.totalScore,
    this.finalRank,
  });

  final Player player;

  /// 0-based turn order around the table; also the dealer rotation order.
  final int seat;

  /// Sum of this player's round points up to the current round.
  final int totalScore;

  /// 1-based finishing position, only meaningful once the game is finished.
  final int? finalRank;

  Standing copyWith({int? totalScore, int? finalRank}) => Standing(
    player: player,
    seat: seat,
    totalScore: totalScore ?? this.totalScore,
    finalRank: finalRank ?? this.finalRank,
  );
}

/// A game at a table. Win counts on the leaderboard are *derived* from this
/// table rather than cached on players, so a rewind can never leave a stale win
/// credited.
class Game {
  const Game({
    this.id,
    required this.startedAt,
    required this.playerCount,
    this.endedAt,
    this.status = GameStatus.inProgress,
    this.currentRound = 1,
    this.winsCounted = false,
    this.evenBidRule = false,
    this.winnerPlayerIds = const <int>[],
  });

  final int? id;
  final DateTime startedAt;
  final int playerCount;
  final DateTime? endedAt;
  final GameStatus status;

  /// The round that is up next, 1-based.
  final int currentRound;

  /// Whether this game's win(s) have been finalised onto the leaderboard.
  /// A rewind sets this back to `false`, which removes the win automatically
  /// because the leaderboard is derived rather than cached.
  final bool winsCounted;

  /// Optional house rule: the total of all bids may not equal the tricks
  /// available. Off by default because it is not an official rule.
  final bool evenBidRule;

  /// Everyone who tied for first. Empty while the game is in progress; more
  /// than one entry when the game ended in a tie.
  final List<int> winnerPlayerIds;

  bool get isFinished => status == GameStatus.finished;

  bool get isTie => winnerPlayerIds.length > 1;

  Game copyWith({
    int? id,
    DateTime? endedAt,
    bool clearEndedAt = false,
    GameStatus? status,
    int? currentRound,
    bool? winsCounted,
    bool? evenBidRule,
    List<int>? winnerPlayerIds,
  }) => Game(
    id: id ?? this.id,
    startedAt: startedAt,
    playerCount: playerCount,
    endedAt: clearEndedAt ? null : (endedAt ?? this.endedAt),
    status: status ?? this.status,
    currentRound: currentRound ?? this.currentRound,
    winsCounted: winsCounted ?? this.winsCounted,
    evenBidRule: evenBidRule ?? this.evenBidRule,
    winnerPlayerIds: winnerPlayerIds ?? this.winnerPlayerIds,
  );

  Map<String, Object?> toMap() => <String, Object?>{
    if (id != null) 'id': id,
    'started_at': startedAt.millisecondsSinceEpoch,
    'ended_at': endedAt?.millisecondsSinceEpoch,
    'status': status.dbValue,
    'player_count': playerCount,
    'current_round': currentRound,
    'wins_counted': winsCounted ? 1 : 0,
    'even_bid_rule': evenBidRule ? 1 : 0,
  };

  factory Game.fromMap(
    Map<String, Object?> map, {
    List<int> winnerPlayerIds = const <int>[],
  }) => Game(
    id: map['id'] as int?,
    startedAt: DateTime.fromMillisecondsSinceEpoch(map['started_at'] as int),
    endedAt: map['ended_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(map['ended_at'] as int),
    status: GameStatus.fromDb(map['status'] as String? ?? 'in_progress'),
    playerCount: map['player_count'] as int,
    currentRound: (map['current_round'] as int?) ?? 1,
    winsCounted: (map['wins_counted'] as int? ?? 0) == 1,
    evenBidRule: (map['even_bid_rule'] as int? ?? 0) == 1,
    winnerPlayerIds: winnerPlayerIds,
  );
}

/// A row of the leaderboard. Computed from finished games, never stored.
class LeaderboardRow {
  const LeaderboardRow({
    required this.player,
    required this.wins,
    required this.gamesPlayed,
  });

  final Player player;
  final int wins;
  final int gamesPlayed;

  /// 0.0 - 1.0. Zero when the player has never finished a game.
  double get winRate => gamesPlayed == 0 ? 0 : wins / gamesPlayed;

  String get winRateLabel =>
      gamesPlayed == 0 ? '—' : '${(winRate * 100).toStringAsFixed(0)}%';

  /// Sorts by wins, then win rate, then name for a stable, readable order.
  static int compare(LeaderboardRow a, LeaderboardRow b) {
    final byWins = b.wins.compareTo(a.wins);
    if (byWins != 0) return byWins;
    final byRate = b.winRate.compareTo(a.winRate);
    if (byRate != 0) return byRate;
    return a.player.name.toLowerCase().compareTo(b.player.name.toLowerCase());
  }
}

/// A finished (or abandoned) game, compact enough to list in History.
class GameSummary {
  const GameSummary({
    required this.id,
    required this.startedAt,
    required this.status,
    required this.standings,
    this.endedAt,
    this.winnerPlayerIds = const <int>[],
    this.winsCounted = false,
  });

  final int id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final GameStatus status;

  /// Seats in table order.
  final List<Standing> standings;

  /// Everyone who tied for first.
  final List<int> winnerPlayerIds;

  /// Whether this game's win currently counts towards the leaderboard.
  final bool winsCounted;

  bool get isFinished => status == GameStatus.finished;

  bool get isTie => winnerPlayerIds.length > 1;

  /// Standings ordered by finishing rank, falling back to score then seat.
  List<Standing> get podium {
    final sorted = List<Standing>.of(standings)
      ..sort((a, b) {
        final rankA = a.finalRank ?? 1 << 30;
        final rankB = b.finalRank ?? 1 << 30;
        final byRank = rankA.compareTo(rankB);
        if (byRank != 0) return byRank;
        final byScore = b.totalScore.compareTo(a.totalScore);
        return byScore != 0 ? byScore : a.seat.compareTo(b.seat);
      });
    return sorted;
  }

  /// The winning seats, resolved from player ids.
  List<Standing> get winners => <Standing>[
    for (final standing in standings)
      if (standing.player.id != null &&
          winnerPlayerIds.contains(standing.player.id))
        standing,
  ];

  String get winnerNames =>
      winners.map((standing) => standing.player.name).join(' & ');
}
