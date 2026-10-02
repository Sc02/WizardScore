import 'package:flutter/material.dart';

import '../../data/services.dart';
import '../../domain/game_state.dart';
import '../../domain/rules.dart';
import '../../models/round.dart';
import '../../theme/palette.dart';
import '../widgets/score_sheet_widgets.dart';
import 'round_screen.dart';
import 'winner_screen.dart';

/// What the player chose in the "Finish the game?" dialog.
enum FinishChoice { cancel, finish, discard }

/// The score sheet: rounds down the side, players across the top.
///
/// The round that is up next is highlighted, and the Start Round button opens
/// the bid/trick entry screen for it. The ⏱ button rewinds the game.
class ScoreSheetScreen extends StatefulWidget {
  const ScoreSheetScreen({required this.gameId, super.key});

  final int gameId;

  @override
  State<ScoreSheetScreen> createState() => _ScoreSheetScreenState();
}

class _ScoreSheetScreenState extends State<ScoreSheetScreen> {
  /// Width of the pinned round-number column.
  static const double _roundColWidth = 58;

  /// Width of each player column.
  static const double _playerColWidth = 104;

  Services? _services;
  GameState? _state;
  bool _loading = true;

  final ScrollController _bodyHorizontal = ScrollController();
  final ScrollController _headerHorizontal = ScrollController();
  final ScrollController _totalsHorizontal = ScrollController();
  final ScrollController _vertical = ScrollController();

  @override
  void initState() {
    super.initState();
    // Keep the pinned header and the totals bar in step with the body's
    // horizontal scrolling. A ScrollController can only drive one view, so the
    // other two are slaved to this one.
    _bodyHorizontal.addListener(() {
      final offset = _bodyHorizontal.offset;
      for (final follower in <ScrollController>[
        _headerHorizontal,
        _totalsHorizontal,
      ]) {
        if (follower.hasClients && follower.offset != offset) {
          follower.jumpTo(offset);
        }
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _services ??= ServicesScope.of(context);
    if (_loading && _state == null) _reload();
  }

  @override
  void dispose() {
    _bodyHorizontal.dispose();
    _headerHorizontal.dispose();
    _totalsHorizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final services = _services!;
    final state = await services.games.loadGame(widget.gameId);
    if (!mounted) return;
    setState(() {
      _state = state;
      _loading = false;
    });
    _scrollToNextRound();
  }

  /// Brings the highlighted "up next" row into view.
  void _scrollToNextRound() {
    final state = _state;
    if (state == null || !_vertical.hasClients) return;
    final next = state.nextRound;
    if (next == null) return;
    final rowHeight = 52.0;
    final target = ((next.roundNumber - 1) * rowHeight) - rowHeight;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_vertical.hasClients) return;
      _vertical.animateTo(
        target.clamp(0, _vertical.position.maxScrollExtent),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _startRound() async {
    final state = _state;
    if (state == null) return;
    final round = state.nextRound;
    if (round == null) {
      await _openWinner();
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => RoundScreen(gameId: widget.gameId, roundId: round.id!),
      ),
    );
    _services!.events.changed();
    await _reload();
  }

  Future<void> _openWinner() async {
    final state = _state;
    if (state == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => WinnerScreen(gameId: widget.gameId),
      ),
    );
    _services!.events.changed();
    await _reload();
  }

  /// Passes the round the sheet is pointing at: no bids, no tricks, no points.
  Future<void> _skipRound() async {
    final state = _state;
    final services = _services;
    if (state == null || services == null) return;
    final round = state.nextRound;
    if (round == null) return;

    final confirmed = await _confirmSkip(round);
    if (confirmed != true || !mounted) return;

    await services.games.skipRound(roundId: round.id!);
    services.events.changed();
    await _reload();
    if (!mounted) return;

    if (_state?.isGameOver ?? false) {
      // Skipping was the last thing left to do, so the game is decided.
      await _openWinner();
      return;
    }
    _toast('Round ${round.roundNumber} skipped.');
  }

  Future<bool?> _confirmSkip(Round round) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Skip round ${round.roundNumber}?'),
        content: Text(
          'Round ${round.roundNumber} is dealt ${round.cardsDealt} card'
          '${round.cardsDealt == 1 ? '' : 's'} each. Skipping it scores '
          'nobody anything; it stays on the score sheet as a gap and the '
          'game moves on to round ${round.roundNumber + 1}.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Skip it'),
          ),
        ],
      ),
    );
  }

  /// Ends the game early from the sheet and credits the current leaders.
  Future<void> _finishGame() async {
    final state = _state;
    final services = _services;
    if (state == null || services == null) return;
    if (state.isFinished || !state.hasPlayedRounds) return;

    final choice = await _confirmFinish(state);
    if (choice == FinishChoice.cancel || !mounted) return;

    if (choice == FinishChoice.discard) {
      await _discardGame();
      return;
    }

    await services.games.finishGame(gameId: widget.gameId);
    services.events.changed();
    if (!mounted) return;

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => WinnerScreen(gameId: widget.gameId),
      ),
    );
    services.events.changed();
    await _reload();
  }

  /// Ends the game but credits nobody: the scores stay on the sheet, the win
  /// never reaches the leaderboard, and we stay here rather than see a crown.
  Future<void> _discardGame() async {
    final services = _services;
    if (services == null) return;

    await services.games.discardGame(gameId: widget.gameId);
    services.events.changed();
    if (!mounted) return;
    await _reload();
    _toast('Game closed. Nobody was credited with a win.');
  }

  Future<FinishChoice?> _confirmFinish(GameState state) {
    final byScore = state.standingsByScore;
    final top = byScore.first.totalScore;
    final leaders = byScore.where((s) => s.totalScore == top);

    return showDialog<FinishChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Finish the game?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'The game stops after round ${state.lastPlayedRound} of '
              '${state.roundsPerPlayer}'
              '${state.skippedRoundCount == 0 ? '' : ', with ${state.skippedRoundCount} skipped'}.',
            ),
            const SizedBox(height: 12),
            for (final standing in byScore)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '${standing.player.name} · ${standing.totalScore}'
                  '${standing.totalScore == top ? '  ★' : ''}',
                  style: TextStyle(
                    fontWeight: standing.totalScore == top
                        ? FontWeight.w700
                        : FontWeight.w400,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Text(
              leaders.length == 1
                  ? '${leaders.first.player.name} takes the win.'
                  : '${leaders.map((s) => s.player.name).join(' & ')} share '
                        'the win.',
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(FinishChoice.cancel),
            child: const Text('Keep playing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(FinishChoice.discard),
            child: const Text('Finish without saving'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(FinishChoice.finish),
            child: const Text('Finish game'),
          ),
        ],
      ),
    );
  }

  Future<void> _timeTravel() async {
    final state = _state;
    final services = _services;
    if (state == null || services == null) return;

    final lastPlayed = state.lastPlayedRound;
    if (lastPlayed == 0) {
      _toast('No rounds have been played yet, so there is nothing to rewind.');
      return;
    }

    final target = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (_) => RewindSheet(state: state),
    );
    if (target == null || !mounted) return;

    // Escalated warning when the game is already on the leaderboard.
    final erased = roundsErasedByRewind(
      targetRound: target,
      lastResolvedRound: state.lastResolvedRound,
    );
    if (erased.isEmpty) return;

    final confirmed = await _confirmRewind(
      state: state,
      targetRound: target,
      erased: erased,
    );
    if (confirmed != true) return;

    await services.games.rewindTo(gameId: widget.gameId, targetRound: target);
    services.events.changed();
    await _reload();
    if (mounted) {
      _toast(
        'Rewound to round $target. Rounds ${erased.first}-${erased.last} are '
        'ready to play again.',
      );
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool?> _confirmRewind({
    required GameState state,
    required int targetRound,
    required List<int> erased,
  }) {
    final wasFinished = state.isFinished;
    final winners = state.game.winnerPlayerIds
        .map(
          (id) => state.standings
              .firstWhere((standing) => standing.player.id == id)
              .player
              .name,
        )
        .join(' & ');

    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Rewind to before round ${targetRound + 1}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Round${erased.length == 1 ? '' : 's'} '
              '${erased.first}-${erased.last} will be reset to unplayed.',
            ),
            const SizedBox(height: 12),
            Text('Scores will be recalculated from round $targetRound.'),
            if (wasFinished) ...<Widget>[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: WizardColors.bidMissed.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  "This game's win for $winners is already counted on the "
                  'leaderboard. Rewinding removes it.',
                ),
              ),
            ],
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Rewind'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    if (state == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Score sheet')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final standings = state.standings;
    final playerAreaWidth = standings.length * _playerColWidth;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Score sheet'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Time travel',
            onPressed: _timeTravel,
            icon: const Icon(Icons.history_toggle_off),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          StatusBar(state: state),
          SheetHeader(
            standings: standings,
            headerController: _headerHorizontal,
            playerAreaWidth: playerAreaWidth,
            roundColWidth: _roundColWidth,
            playerColWidth: _playerColWidth,
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              controller: _vertical,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // Pinned round-number column.
                  SizedBox(
                    width: _roundColWidth,
                    child: Column(
                      children: <Widget>[
                        for (final round in state.rounds)
                          RoundNumberCell(
                            round: round,
                            isNext:
                                state.nextRound?.roundNumber ==
                                round.roundNumber,
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _bodyHorizontal,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: playerAreaWidth,
                        child: Column(
                          children: <Widget>[
                            for (final round in state.rounds)
                              ScoreRow(
                                state: state,
                                round: round,
                                isNext:
                                    state.nextRound?.roundNumber ==
                                    round.roundNumber,
                                columnWidth: _playerColWidth,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          TotalsBar(
            state: state,
            roundColWidth: _roundColWidth,
            playerColWidth: _playerColWidth,
            horizontalController: _totalsHorizontal,
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  FilledButton.icon(
                    onPressed: _startRound,
                    icon: Icon(
                      state.nextRound == null
                          ? Icons.emoji_events
                          : Icons.play_arrow,
                    ),
                    label: Text(
                      state.nextRound == null
                          ? 'See the winner'
                          : 'Start round ${state.nextRound!.roundNumber} · '
                                '${state.nextRound!.cardsDealt} card'
                                '${state.nextRound!.cardsDealt == 1 ? '' : 's'} '
                                'each',
                    ),
                  ),
                  if (!state.isFinished && state.nextRound != null) ...<Widget>[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _skipRound,
                      icon: const Icon(Icons.skip_next),
                      label: Text('Skip round ${state.nextRound!.roundNumber}'),
                    ),
                  ],
                  if (!state.isFinished) ...<Widget>[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: state.hasPlayedRounds ? _finishGame : null,
                      icon: const Icon(Icons.flag_outlined),
                      label: const Text('Finish game'),
                    ),
                    if (!state.hasPlayedRounds)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          'Finish game unlocks once at least one round has '
                          'been scored.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Colors.white54),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
