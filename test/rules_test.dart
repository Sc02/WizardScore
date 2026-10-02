import 'package:flutter_test/flutter_test.dart';
import 'package:wizard_score/domain/rules.dart';

void main() {
  group('table size and rounds', () {
    test('round counts match the official rules', () {
      // U.S. Games / Board Game Arena: play until the 60 card deck is exhausted.
      expect(roundsForPlayers(2), 30);
      expect(roundsForPlayers(3), 20);
      expect(roundsForPlayers(4), 15);
      expect(roundsForPlayers(5), 12);
      expect(roundsForPlayers(6), 10);
    });

    test('max cards per player divides the deck evenly', () {
      expect(maxCardsPerPlayer(3), 20);
      expect(maxCardsPerPlayer(4), 15);
      expect(maxCardsPerPlayer(5), 12);
      expect(maxCardsPerPlayer(6), 10);
    });

    test('unsupported table sizes are rejected', () {
      expect(() => roundsForPlayers(1), throwsArgumentError);
      expect(() => roundsForPlayers(7), throwsArgumentError);
      expect(() => roundsForPlayers(0), throwsArgumentError);
    });

    test('cards dealt in a round equals the round number', () {
      expect(cardsForRound(1), 1);
      expect(cardsForRound(7), 7);
      expect(() => cardsForRound(0), throwsArgumentError);
    });

    test('a game counts up only, never back down', () {
      expect(cardSequence(4), List<int>.generate(15, (i) => i + 1));
      expect(cardSequence(6).first, 1);
      expect(cardSequence(6).last, 10);
      final seq = cardSequence(5);
      for (var i = 1; i < seq.length; i++) {
        expect(seq[i], greaterThan(seq[i - 1]));
      }
    });

    test('the last round deals the whole deck', () {
      expect(roundsForPlayers(3), 20);
      expect(maxCardsPerPlayer(3), 20);
      expect(roundsForPlayers(6), 10);
      expect(roundsForPlayers(4), 15);
    });
  });

  group('dealer rotation', () {
    test('the deal moves one seat left each round and wraps', () {
      expect(dealerSeatForRound(1, 4), 0);
      expect(dealerSeatForRound(2, 4), 1);
      expect(dealerSeatForRound(3, 4), 2);
      expect(dealerSeatForRound(4, 4), 3);
      expect(dealerSeatForRound(5, 4), 0);
      expect(dealerSeatForRound(13, 3), 0);
    });

    test('bad round numbers are rejected', () {
      expect(() => dealerSeatForRound(0, 4), throwsArgumentError);
    });
  });

  group('scoring', () {
    test('an exact bid scores 20 plus 10 per trick', () {
      expect(scoreRound(0, 0), 20);
      expect(scoreRound(1, 1), 30);
      expect(scoreRound(2, 2), 40);
      expect(scoreRound(5, 5), 70);
    });

    test('a missed bid loses 10 per trick over or under', () {
      expect(scoreRound(1, 0), -10);
      expect(scoreRound(2, 1), -10);
      expect(scoreRound(0, 1), -10);
      expect(scoreRound(0, 3), -30);
      expect(scoreRound(3, 5), -20);
      expect(scoreRound(4, 0), -40);
    });

    test('matches the worked example from the official rulebook', () {
      // Round one: Paul bid 0 and made it, Thomas bid 1 and broke,
      // Marie bid 1 and made it.
      expect(scoreRound(0, 0), 20);
      expect(scoreRound(1, 0), -10);
      expect(scoreRound(1, 1), 30);
      // Round two: Paul bid 2 and took 1, Thomas bid 0 and made it,
      // Marie bid 0 and took 1.
      expect(scoreRound(2, 1), -10);
      expect(scoreRound(0, 0), 20);
      expect(scoreRound(0, 1), -10);
    });

    test('negative inputs are rejected', () {
      expect(() => scoreRound(-1, 0), throwsArgumentError);
      expect(() => scoreRound(0, -1), throwsArgumentError);
    });
  });

  group('round validation', () {
    test('bids must fit in the hand', () {
      expect(bidIsLegal(0, 1), isTrue);
      expect(bidIsLegal(1, 1), isTrue);
      expect(bidIsLegal(2, 1), isFalse);
      expect(bidIsLegal(-1, 3), isFalse);
    });

    test('tricks must fit in the hand', () {
      expect(tricksIsLegal(0, 5), isTrue);
      expect(tricksIsLegal(5, 5), isTrue);
      expect(tricksIsLegal(6, 5), isFalse);
    });

    test('tricks won must total the cards dealt', () {
      // One trick is played per card dealt, however many seats are filled:
      // round 1 is always a single trick.
      expect(totalTricksAvailable(5), 5);
      expect(totalTricksAvailable(1), 1);
      expect(tricksTotalIsValid(<int>[1, 0, 0], 1), isTrue);
      expect(tricksTotalIsValid(<int>[1, 0], 1), isTrue);
      expect(tricksTotalIsValid(<int>[0, 0, 0], 1), isFalse);
      expect(tricksTotalIsValid(<int>[1, 1, 1], 1), isFalse);
      // One seat's whole hand is a legal split of the tricks.
      expect(tricksTotalIsValid(<int>[5, 0, 0], 5), isTrue);
      expect(tricksTotalIsValid(<int>[3, 2, 0], 5), isTrue);
      expect(tricksTotalIsValid(<int>[5, 5, 5], 5), isFalse);
      expect(tricksTotalIsValid(<int>[0, 8, 7], 5), isFalse);
      expect(tricksTotalIsValid(<int>[3, 0], 3), isTrue);
      expect(tricksTotalIsValid(<int>[3, 3], 3), isFalse);
    });

    test('the even-bid house rule is opt-in and detects an even split', () {
      expect(bidSumBreaksEvenRule(<int>[1, 0, 0], 1), isTrue);
      expect(bidSumBreaksEvenRule(<int>[1, 1, 1], 1), isFalse);
      expect(bidSumBreaksEvenRule(<int>[2, 2, 1], 5), isTrue);
      expect(bidSumBreaksEvenRule(<int>[5, 5, 5], 5), isFalse);
    });
  });

  group('totals and winners', () {
    test('running totals accumulate across rounds', () {
      expect(runningTotals(<int>[20, -10, 30]), <int>[20, 10, 40]);
      expect(runningTotals(const <int>[]), isEmpty);
      expect(totalScore(<int>[20, -10, 30]), 40);
      expect(totalScore(const <int>[]), 0);
    });

    test('the highest score wins', () {
      expect(winnerSeats(<int>[10, 50, 20]), <int>[1]);
      expect(winnerSeats(<int>[0, -50, -20]), <int>[0]);
    });

    test('a tie for first reports every co-winner', () {
      expect(winnerSeats(<int>[30, 30, 10]), <int>[0, 1]);
      expect(winnerSeats(<int>[5, 5, 5]), <int>[0, 1, 2]);
      expect(winnerSeats(const <int>[]), isEmpty);
    });
  });

  group('rewind (time travel)', () {
    test('erases every round after the target', () {
      expect(
        roundsErasedByRewind(targetRound: 6, lastResolvedRound: 10),
        <int>[7, 8, 9, 10],
      );
    });

    test('rewinding to the last played round erases nothing', () {
      expect(
        roundsErasedByRewind(targetRound: 10, lastResolvedRound: 10),
        isEmpty,
      );
    });

    test('rewinding to round zero wipes the whole game', () {
      expect(
        roundsErasedByRewind(targetRound: 0, lastResolvedRound: 3),
        <int>[1, 2, 3],
      );
    });

    test('cannot rewind before the start of the game', () {
      expect(
        () => roundsErasedByRewind(targetRound: -1, lastResolvedRound: 3),
        throwsArgumentError,
      );
    });

    test('undo last round is just a rewind of one round', () {
      // Round 8 is current with 7 played, so undo rewinds to round 6.
      expect(
        roundsErasedByRewind(targetRound: 6, lastResolvedRound: 7),
        <int>[7],
      );
    });

    test('totals after a rewind ignore the erased rounds', () {
      const playerCount = 4;
      final bids = <List<int>>[
        <int>[1, 0, 0, 0],
        <int>[0, 2, 1, 1],
        <int>[1, 1, 1, 1],
        <int>[0, 3, 1, 2],
        <int>[2, 2, 3, 3],
      ];
      final tricks = <List<int>>[
        <int>[1, 0, 0, 0],
        <int>[1, 1, 1, 1],
        <int>[1, 1, 1, 1],
        <int>[0, 3, 2, 3],
        <int>[2, 2, 3, 3],
      ];

      // Totals for the untouched five round game.
      final full = <int>[0, 0, 0, 0];
      for (var round = 0; round < bids.length; round++) {
        for (var seat = 0; seat < playerCount; seat++) {
          full[seat] += scoreRound(bids[round][seat], tricks[round][seat]);
        }
      }

      // Rewind to round 2: rounds 3, 4 and 5 must disappear.
      const targetRound = 2;
      final survivors =
          <int>{1, 2, 3, 4, 5}.difference(
        roundsErasedByRewind(targetRound: targetRound, lastResolvedRound: 5)
            .toSet(),
      );
      expect(survivors, <int>{1, 2});

      final rebuilt = <int>[0, 0, 0, 0];
      for (final round in survivors) {
        for (var seat = 0; seat < playerCount; seat++) {
          rebuilt[seat] += scoreRound(bids[round - 1][seat], tricks[round - 1][seat]);
        }
      }

      // Rebuilt equals a fresh two round game.
      for (var seat = 0; seat < playerCount; seat++) {
        final fresh = <int>[
          scoreRound(bids[0][seat], tricks[0][seat]),
          scoreRound(bids[1][seat], tricks[1][seat]),
        ];
        expect(rebuilt[seat], totalScore(fresh));
      }

      // And the rewind demonstrably changed the standings.
      expect(full, isNot(equals(rebuilt)));
    });
  });
}