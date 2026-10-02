import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wizard_score/app.dart';
import 'package:wizard_score/data/db.dart';
import 'package:wizard_score/data/services.dart';
import 'package:wizard_score/ui/screens/history_screen.dart';
import 'package:wizard_score/ui/screens/round_screen.dart';
import 'package:wizard_score/ui/screens/score_sheet_screen.dart';
import 'package:wizard_score/ui/screens/winner_screen.dart';
import 'package:wizard_score/ui/widgets/empty_states.dart';
import 'package:wizard_score/ui/widgets/game_cards.dart';
import 'package:wizard_score/ui/widgets/score_sheet_widgets.dart';

/// End-to-end checks over the real widget tree.
///
/// These pump the actual app against an in-memory SQLite database, so they
/// catch what the rules and repository tests cannot: a screen that fails to
/// build, a button wired to nothing, or an entry flow a human cannot finish.
void main() {
  setUpAll(sqfliteFfiInit);

  late Services services;

  setUp(() async {
    final db = await WizardDatabase.open(
      factory: databaseFactoryFfi,
      inMemory: true,
    );
    services = Services.from(db);
  });

  tearDown(() => services.db.close());

  /// Seeds [count] players and returns their ids in seat order.
  ///
  /// Database work runs inside [WidgetTester.runAsync]: the test body itself
  /// runs in the fake-async zone, where a real SQLite future would never land.
  Future<List<int>> seedPlayers(WidgetTester tester, int count) async {
    final ids = <int>[];
    await tester.runAsync(() async {
      for (var i = 0; i < count; i++) {
        final player = await services.players.create(
          name: 'Player $i',
          colorIndex: i,
        );
        ids.add(player.id!);
      }
    });
    return ids;
  }

  Future<int> startGame(WidgetTester tester, List<int> playerIds) async {
    final gameId = await tester.runAsync(
      () => services.games.startGame(playerIds: playerIds),
    );
    return gameId ?? 0;
  }

  /// Plays rounds [from]..[to] straight through the repository.
  ///
  /// Seat 0 bids the whole hand and wins every trick; the others bid zero and
  /// make it. The tricks always add up to the cards dealt.
  Future<void> playRounds(
    WidgetTester tester,
    int gameId, {
    required int from,
    required int to,
  }) {
    return tester.runAsync(() async {
      for (var roundNumber = from; roundNumber <= to; roundNumber++) {
        final state = (await services.games.loadGame(gameId))!;
        final round = state.nextRound!;
        final cards = round.cardsDealt;
        final bids = <int, int>{};
        final tricks = <int, int>{};
        var first = true;
        for (final standing in state.standings) {
          bids[standing.player.id!] = first ? cards : 0;
          tricks[standing.player.id!] = first ? cards : 0;
          first = false;
        }

        await services.games.saveBids(round.id!, bids);
        await services.games.lockBids(round.id!);
        await services.games.completeRound(
          gameId: gameId,
          roundId: round.id!,
          roundNumber: roundNumber,
          cardsDealt: cards,
          tricksWon: tricks,
          totalRounds: state.roundsPerPlayer,
        );
      }
    });
  }

  /// Lets the asynchronous database land, then draws the frames it triggered.
  ///
  /// The real delay gives SQLite time to finish; the pump advances the fake
  /// clock far enough for route transitions to run out.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
      await tester.pump(const Duration(milliseconds: 80));
    }
  }

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 1900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(WizardApp(services: services));
    await settle(tester);
  }

  /// Taps a label inside the bottom navigation bar. IndexedStack builds every
  /// tab offstage, so screen titles would otherwise collide with the labels.
  Future<void> tapTab(WidgetTester tester, String label) async {
    final tab = find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text(label),
    );
    await tester.tap(tab, warnIfMissed: false);
    await settle(tester);
  }

  /// Taps the plus button of one [RoundCounter]. Rows are laid out as
  /// bid, tricks, bid, tricks... for each player.
  Future<void> tapPlus(WidgetTester tester, int row) async {
    final plus = find.descendant(
      of: find.byType(RoundCounter).at(row),
      matching: find.byIcon(Icons.add),
    );
    await tester.tap(plus, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 40));
  }

  group('shell', () {
    testWidgets('boots onto Play with all four tabs', (tester) async {
      await pumpApp(tester);

      expect(find.text('WizardScore'), findsOneWidget);
      expect(find.byType(NoGamePrompt), findsOneWidget);
      expect(find.text('Start a new game'), findsOneWidget);

      for (final label in <String>[
        'Play',
        'Players',
        'Leaderboard',
        'History',
      ]) {
        expect(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(label),
          ),
          findsOneWidget,
        );
      }
    });

    testWidgets('Players starts empty and lists people once added',
        (tester) async {
      await pumpApp(tester);
      await tapTab(tester, 'Players');
      expect(find.byType(EmptyRoster), findsOneWidget);

      await seedPlayers(tester, 2);
      services.events.changed();
      await settle(tester);

      expect(find.byType(EmptyRoster), findsNothing);
      expect(find.text('Player 0'), findsOneWidget);
      expect(find.text('Player 1'), findsOneWidget);
    });

    testWidgets('History starts empty', (tester) async {
      await pumpApp(tester);
      await tapTab(tester, 'History');
      expect(find.byType(EmptyHistory), findsOneWidget);
    });
  });

  group('round entry', () {
    testWidgets('a whole round can be entered by tapping through',
        (tester) async {
      final ids = await seedPlayers(tester, 3);
      await startGame(tester, ids);

      await pumpApp(tester);
      expect(find.byType(LiveGameCard), findsOneWidget);

      await tester.tap(find.text('Open score sheet'));
      await settle(tester);
      expect(find.byType(ScoreSheetScreen), findsOneWidget);
      expect(find.byType(SheetHeader), findsOneWidget);

      await tester.tap(find.textContaining('Start round 1'));
      await settle(tester);
      expect(find.byType(RoundScreen), findsOneWidget);

      // Round 1 is a single trick for the whole table: the plus buttons
      // hand out one trick to seat 0, leaving the others on zero.
      expect(find.text('Lock bids'), findsOneWidget);
      await tapPlus(tester, 0);
      expect(find.textContaining('Bids total 1 of 1 trick'), findsOneWidget);

      await tester.tap(find.text('Lock bids'));
      await settle(tester);

      // The tricks column only unlocks after the lock.
      await tapPlus(tester, 1);
      expect(find.textContaining('Ready: 1 of 1 trick'), findsOneWidget);

      await tester.tap(find.text('Round done'));
      await settle(tester);

      // Back on the sheet: seat 0 made 1 for 30, the others made 0 for 20.
      expect(find.byType(RoundScreen), findsNothing);
      expect(find.byType(ScoreSheetScreen), findsOneWidget);
      expect(
        find.descendant(of: find.byType(TotalsBar), matching: find.text('30')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byType(TotalsBar), matching: find.text('20')),
        findsNWidgets(2),
      );
    });

    testWidgets('tricks that do not add up are rejected', (tester) async {
      final ids = await seedPlayers(tester, 3);
      await startGame(tester, ids);

      await pumpApp(tester);
      await tester.tap(find.text('Open score sheet'));
      await settle(tester);
      await tester.tap(find.textContaining('Start round 1'));
      await settle(tester);

      for (final row in <int>[0, 2, 4]) {
        await tapPlus(tester, row);
      }
      await tester.tap(find.text('Lock bids'));
      await settle(tester);

      // Every bid claims the only trick: 3 of 1, so Round done is disabled.
      final done = find.widgetWithText(FilledButton, 'Round done');
      expect(tester.widget<FilledButton>(done).onPressed, isNull);
    });
  });

  group('skipping a round', () {
    testWidgets('the sheet can pass on a round without scoring it',
        (tester) async {
      final ids = await seedPlayers(tester, 3);
      await startGame(tester, ids);

      await pumpApp(tester);
      await tester.tap(find.text('Open score sheet'));
      await settle(tester);

      expect(find.text('Skip round 1'), findsOneWidget);
      await tester.tap(find.text('Skip round 1'));
      await settle(tester);

      expect(find.text('Skip round 1?'), findsOneWidget);
      await tester.tap(find.text('Skip it'));
      await settle(tester);

      expect(find.text('Round 1 skipped.'), findsOneWidget);
      expect(find.textContaining('Start round 2'), findsOneWidget);
      expect(
        find.text('0/20 rounds played · 1 skipped'),
        findsOneWidget,
      );
      expect(find.text('Skip round 2'), findsOneWidget);
    });

    testWidgets('the round screen can bail out through its app bar',
        (tester) async {
      final ids = await seedPlayers(tester, 3);
      await startGame(tester, ids);

      await pumpApp(tester);
      await tester.tap(find.text('Open score sheet'));
      await settle(tester);
      await tester.tap(find.textContaining('Start round 1'));
      await settle(tester);
      expect(find.byType(RoundScreen), findsOneWidget);

      await tester.tap(find.byTooltip('Skip round'));
      await settle(tester);
      expect(find.text('Skip round 1?'), findsOneWidget);
      await tester.tap(find.text('Skip it'));
      await settle(tester);

      expect(find.byType(RoundScreen), findsNothing);
      expect(find.byType(ScoreSheetScreen), findsOneWidget);
      expect(find.textContaining('Start round 2'), findsOneWidget);
      expect(
        find.text('0/20 rounds played · 1 skipped'),
        findsOneWidget,
      );
    });
  });

  group('finishing early', () {
    testWidgets('Finish game stays disabled until a round is scored',
        (tester) async {
      final ids = await seedPlayers(tester, 3);
      await startGame(tester, ids);

      await pumpApp(tester);
      await tester.tap(find.text('Open score sheet'));
      await settle(tester);

      final finish = find.widgetWithText(OutlinedButton, 'Finish game');
      expect(finish, findsOneWidget);
      expect(tester.widget<OutlinedButton>(finish).onPressed, isNull);
      expect(
        find.textContaining('unlocks once at least one round'),
        findsOneWidget,
      );
    });

    testWidgets('Finish game ends a half-played game and credits the leaders',
        (tester) async {
      final ids = await seedPlayers(tester, 3);
      final gameId = await startGame(tester, ids);
      await playRounds(tester, gameId, from: 1, to: 3);

      await pumpApp(tester);
      await tapTab(tester, 'History');
      await tester.tap(find.text('In progress'));
      await settle(tester);
      expect(find.byType(ScoreSheetScreen), findsOneWidget);

      final finish = find.widgetWithText(OutlinedButton, 'Finish game');
      expect(tester.widget<OutlinedButton>(finish).onPressed, isNotNull);
      expect(find.textContaining('unlocks once'), findsNothing);

      await tester.tap(finish);
      await settle(tester);

      // The dialog shows the standings before anything is written.
      expect(find.text('Finish the game?'), findsOneWidget);
      expect(find.textContaining('Player 0 · 120'), findsOneWidget);
      expect(find.textContaining('share the win'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Finish game'));
      await settle(tester);

      expect(find.byType(WinnerScreen), findsOneWidget);
      expect(find.text('WINNERS'), findsOneWidget);
      // The win was already credited, so the button reads Done.
      expect(find.text('Done'), findsOneWidget);

      await tester.tap(find.text('Done'));
      await settle(tester);
      expect(find.byType(HomeShell), findsOneWidget);

      await tapTab(tester, 'Leaderboard');
      expect(find.text('Player 0'), findsOneWidget);
      expect(find.text('win'), findsNWidgets(3));
    });
  });

  group('the crown', () {
    testWidgets('shows the winners and credits them on End game',
        (tester) async {
      final ids = await seedPlayers(tester, 3);
      final gameId = await startGame(tester, ids);
      await playRounds(tester, gameId, from: 1, to: 20);

      await pumpApp(tester);
      await tapTab(tester, 'History');
      // Every round is played, but nobody has ended the game yet.
      expect(find.text('In progress'), findsOneWidget);

      await tester.tap(find.text('In progress'));
      await settle(tester);
      expect(find.byType(ScoreSheetScreen), findsOneWidget);

      await tester.tap(find.text('See the winner'));
      await settle(tester);
      expect(find.byType(WinnerScreen), findsOneWidget);
      // Every player bid and took an equal share, so the crown is shared.
      expect(find.text('WINNERS'), findsOneWidget);
      expect(find.byType(CrownIcon), findsOneWidget);

      await tester.tap(find.text('End game'));
      await settle(tester);

      // Back at the shell, with the result now on the leaderboard.
      expect(find.byType(WinnerScreen), findsNothing);
      expect(find.byType(HomeShell), findsOneWidget);

      await tapTab(tester, 'Leaderboard');
      expect(find.text('Player 0'), findsOneWidget);
      // One win each, so the tiles say "win" rather than "wins".
      expect(find.text('win'), findsNWidgets(3));

      await tapTab(tester, 'History');
      expect(find.text('Player 0 & Player 1 & Player 2'), findsOneWidget);
      expect(find.text('In progress'), findsNothing);
    });

    testWidgets('opening a live game resumes it rather than crowning it',
        (tester) async {
      final ids = await seedPlayers(tester, 3);
      await startGame(tester, ids);

      await pumpApp(tester);
      await tapTab(tester, 'History');
      expect(find.text('In progress'), findsOneWidget);

      await tester.tap(find.text('In progress'));
      await settle(tester);
      expect(find.byType(ScoreSheetScreen), findsOneWidget);
      expect(find.byType(WinnerScreen), findsNothing);
    });
  });
}
