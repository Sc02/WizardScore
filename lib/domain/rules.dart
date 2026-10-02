/// Pure Wizard (Ken Fisher, 1984) game rules.
///
/// This file must stay free of Flutter, plugin and database imports so that it
/// can be unit tested in isolation. Everything here is deterministic and
/// side-effect free.
///
/// Official rules (U.S. Games Systems / Board Game Arena):
///  * 60 card deck: suits 1-13 in 4 colours, 4 Wizards, 4 Jesters.
///  * Rounds are dealt *counting up only*: round N deals N cards per player.
///  * Play continues until every card is dealt, so the round count is
///    `60 / playerCount` (3p -> 20, 4p -> 15, 5p -> 12, 6p -> 10).
///  * Exact bid  -> 20 points + 10 per trick taken.
///  * Missed bid -> -10 points per trick over or under.
library;

import 'dart:math' as math;

/// Total number of cards in a Wizard deck.
const int deckSize = 60;

/// Smallest supported table. 2 players => 30 rounds, which the deck divides into.
const int minPlayers = 2;

/// Largest supported table (60 / 7 does not divide evenly).
const int maxPlayers = 6;

/// Throws if [playerCount] is not a table size the deck supports.
void validatePlayerCount(int playerCount) {
  if (playerCount < minPlayers || playerCount > maxPlayers) {
    throw ArgumentError.value(
      playerCount,
      'playerCount',
      'Wizard supports $minPlayers-$maxPlayers players',
    );
  }
  if (deckSize % playerCount != 0) {
    throw ArgumentError.value(
      playerCount,
      'playerCount',
      'A $playerCount player game does not divide the $deckSize card deck evenly',
    );
  }
}

/// Cards dealt to each player in the final round, and therefore the maximum
/// any player can hold in any round.
int maxCardsPerPlayer(int playerCount) {
  validatePlayerCount(playerCount);
  return deckSize ~/ playerCount;
}

/// Total rounds in a game: count up 1..[maxCardsPerPlayer] until the deck is
/// exhausted.
int roundsForPlayers(int playerCount) => maxCardsPerPlayer(playerCount);

/// Cards dealt to every player in [roundNumber] (1-based).
int cardsForRound(int roundNumber) {
  if (roundNumber < 1) {
    throw ArgumentError.value(roundNumber, 'roundNumber', 'Rounds are 1-based');
  }
  return roundNumber;
}

/// Whose turn it is to deal, as a 0-based seat index. The deal rotates one seat
/// to the left each round, and round 1 starts at seat 0.
int dealerSeatForRound(int roundNumber, int playerCount) {
  validatePlayerCount(playerCount);
  if (roundNumber < 1) {
    throw ArgumentError.value(roundNumber, 'roundNumber', 'Rounds are 1-based');
  }
  return (roundNumber - 1) % playerCount;
}

/// Sequence of card counts for a whole game, e.g. `[1, 2, 3, ...]`.
List<int> cardSequence(int playerCount) => List<int>.generate(
  roundsForPlayers(playerCount),
  (i) => cardsForRound(i + 1),
);

/// Points for one player's round.
///
/// Exact bid: `20 + 10 * tricks`. Missed bid: `-10` per trick over or under.
/// Bidding zero and taking zero therefore scores 20.
int scoreRound(int bid, int tricksWon) {
  if (bid < 0) throw ArgumentError.value(bid, 'bid', 'Bid cannot be negative');
  if (tricksWon < 0) {
    throw ArgumentError.value(
      tricksWon,
      'tricksWon',
      'Tricks cannot be negative',
    );
  }
  final difference = tricksWon - bid;
  if (difference == 0) return 20 + (10 * tricksWon);
  return -10 * difference.abs();
}

/// Whether [bid] is legal when [cardsDealt] cards are in every hand.
bool bidIsLegal(int bid, int cardsDealt) => bid >= 0 && bid <= cardsDealt;

/// Whether [tricksWon] is legal when [cardsDealt] cards are in every hand.
bool tricksIsLegal(int tricksWon, int cardsDealt) =>
    tricksWon >= 0 && tricksWon <= cardsDealt;

/// Total tricks up for grabs in a round: one trick per card dealt.
///
/// Each trick takes one card from every hand, so a round where everyone holds
/// [cardsDealt] cards produces exactly [cardsDealt] tricks, no matter how many
/// seats are at the table. Round 1 is therefore always a single trick.
int totalTricksAvailable(int cardsDealt) => cardsDealt;

/// Every card dealt in a round is won by somebody, so the tricks won must add
/// up to exactly the total number of tricks available.
///
/// [cardsDealt] is both the cards in each hand and the tricks on the table.
bool tricksTotalIsValid(Iterable<int> tricksWon, int cardsDealt) {
  return tricksWon.fold<int>(0, (sum, tricks) => sum + tricks) ==
      totalTricksAvailable(cardsDealt);
}

/// The optional "plus/minus 1" house rule: the last player to bid may not make
/// the total of all bids equal the number of tricks available.
///
/// This is *not* part of the official rules, so it is opt-in per game.
bool bidSumBreaksEvenRule(Iterable<int> bids, int cardsDealt) {
  return bids.fold<int>(0, (sum, bid) => sum + bid) ==
      totalTricksAvailable(cardsDealt);
}

/// Sum of a player's points across rounds.
int totalScore(Iterable<int> pointsPerRound) =>
    pointsPerRound.fold<int>(0, (sum, points) => sum + points);

/// Running totals after every round, for score sheet display.
List<int> runningTotals(Iterable<int> pointsPerRound) {
  final totals = <int>[];
  var running = 0;
  for (final points in pointsPerRound) {
    running += points;
    totals.add(running);
  }
  return totals;
}

/// Seats (0-based) sharing the highest score. A length greater than one means a
/// tie for first, which this app treats as co-winners.
List<int> winnerSeats(Iterable<int> finalScores) {
  final scores = finalScores.toList(growable: false);
  if (scores.isEmpty) return const <int>[];
  final best = scores.reduce(math.max);
  return <int>[
    for (var seat = 0; seat < scores.length; seat++)
      if (scores[seat] == best) seat,
  ];
}

/// Rounds that a rewind to [targetRound] resets: everything after it.
///
/// [lastResolvedRound] is the highest round that is either scored or skipped,
/// so skipped rounds are covered as well as played ones. Rewinding to the last
/// resolved round is the same operation as "undo last round", so both features
/// share this helper.
List<int> roundsErasedByRewind({
  required int targetRound,
  required int lastResolvedRound,
}) {
  if (targetRound < 0) {
    throw ArgumentError.value(
      targetRound,
      'targetRound',
      'Cannot rewind before the start of the game',
    );
  }
  if (targetRound >= lastResolvedRound) return const <int>[];
  return <int>[
    for (var round = targetRound + 1; round <= lastResolvedRound; round++)
      round,
  ];
}
