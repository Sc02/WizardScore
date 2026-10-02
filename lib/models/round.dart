/// Lifecycle of a single round row.
enum RoundStatus {
  /// Not started: no bids entered yet.
  pending,

  /// Bids are entered and locked; tricks are being counted.
  bidsLocked,

  /// Scored.
  complete,

  /// Deliberately not played this game: no bids, no tricks, no points.
  skipped;

  static RoundStatus fromDb(String value) => switch (value) {
    'bids_locked' => RoundStatus.bidsLocked,
    'complete' => RoundStatus.complete,
    'skipped' => RoundStatus.skipped,
    _ => RoundStatus.pending,
  };

  String get dbValue => switch (this) {
    RoundStatus.pending => 'pending',
    RoundStatus.bidsLocked => 'bids_locked',
    RoundStatus.complete => 'complete',
    RoundStatus.skipped => 'skipped',
  };
}

/// One round of a game. Structural fields (cards dealt, dealer) are derived
/// from [roundNumber] up front; results live in [entries].
class Round {
  const Round({
    this.id,
    required this.gameId,
    required this.roundNumber,
    required this.cardsDealt,
    required this.dealerSeat,
    this.status = RoundStatus.pending,
  });

  final int? id;
  final int gameId;

  /// 1-based.
  final int roundNumber;

  /// Cards dealt to every player this round.
  final int cardsDealt;

  /// 0-based seat of the dealer.
  final int dealerSeat;

  final RoundStatus status;

  /// True once the round has been scored.
  bool get isComplete => status == RoundStatus.complete;

  /// True when the table chose not to play this round.
  bool get isSkipped => status == RoundStatus.skipped;

  /// True when the round will never be played again as it stands, whether it
  /// was scored or skipped. This is what gates "is the game over?" and what
  /// [GameState.nextRound] jumps over.
  bool get isResolved =>
      status == RoundStatus.complete || status == RoundStatus.skipped;

  Round copyWith({int? id, RoundStatus? status}) => Round(
    id: id ?? this.id,
    gameId: gameId,
    roundNumber: roundNumber,
    cardsDealt: cardsDealt,
    dealerSeat: dealerSeat,
    status: status ?? this.status,
  );

  Map<String, Object?> toMap() => <String, Object?>{
    if (id != null) 'id': id,
    'game_id': gameId,
    'round_number': roundNumber,
    'cards_dealt': cardsDealt,
    'dealer_seat': dealerSeat,
    'status': status.dbValue,
  };

  factory Round.fromMap(Map<String, Object?> map) => Round(
    id: map['id'] as int?,
    gameId: map['game_id'] as int,
    roundNumber: map['round_number'] as int,
    cardsDealt: map['cards_dealt'] as int,
    dealerSeat: map['dealer_seat'] as int,
    status: RoundStatus.fromDb(map['status'] as String? ?? 'pending'),
  );
}

/// One player's row inside a round: their bid and how many tricks they took.
class RoundEntry {
  const RoundEntry({
    required this.roundId,
    required this.playerId,
    this.bid,
    this.bidLocked = false,
    this.tricksWon,
    this.points,
  });

  final int roundId;
  final int playerId;

  /// `null` until the bid is entered.
  final int? bid;

  final bool bidLocked;

  /// `null` until tricks are counted.
  final int? tricksWon;

  /// Cached result of [scoreRound]; `null` until the round is scored.
  final int? points;

  bool get isScored => points != null;

  /// True when this player made their bid exactly.
  bool get madeBid => bid != null && tricksWon != null && bid == tricksWon;

  RoundEntry copyWith({
    int? bid,
    bool? bidLocked,
    int? tricksWon,
    int? points,
  }) => RoundEntry(
    roundId: roundId,
    playerId: playerId,
    bid: bid ?? this.bid,
    bidLocked: bidLocked ?? this.bidLocked,
    tricksWon: tricksWon ?? this.tricksWon,
    points: points ?? this.points,
  );

  Map<String, Object?> toMap() => <String, Object?>{
    'round_id': roundId,
    'player_id': playerId,
    'bid': bid,
    'bid_locked': bidLocked ? 1 : 0,
    'tricks_won': tricksWon,
    'points': points,
  };

  factory RoundEntry.fromMap(Map<String, Object?> map) => RoundEntry(
    roundId: map['round_id'] as int,
    playerId: map['player_id'] as int,
    bid: map['bid'] as int?,
    bidLocked: (map['bid_locked'] as int? ?? 0) == 1,
    tricksWon: map['tricks_won'] as int?,
    points: map['points'] as int?,
  );
}
