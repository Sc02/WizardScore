import 'package:flutter/material.dart';

import '../../data/game_repository.dart';
import '../../data/services.dart';
import '../../domain/game_state.dart';
import '../../domain/rules.dart';
import '../../models/round.dart';
import '../../models/player.dart';
import '../../theme/palette.dart';
import '../widgets/player_avatar.dart';
import 'winner_screen.dart';

/// Entering a round: bids first, then a lock, then the tricks that were won.
///
/// Debts to the physical game: the bids column is frozen before the tricks
/// column unlocks, and "Round done" refuses a set of tricks that does not add
/// up to the cards dealt.
class RoundScreen extends StatefulWidget {
  const RoundScreen({required this.gameId, required this.roundId, super.key});

  final int gameId;
  final int roundId;

  @override
  State<RoundScreen> createState() => _RoundScreenState();
}

class _RoundScreenState extends State<RoundScreen> {
  Services? _services;
  GameState? _state;
  Round? _round;

  /// `null` means "not entered yet", which is what keeps the lock honest.
  final Map<int, int?> _bids = <int, int?>{};
  final Map<int, int?> _tricks = <int, int?>{};

  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _services ??= ServicesScope.of(context);
    if (_state == null) _load();
  }

  Future<void> _load() async {
    final services = _services!;
    final state = await services.games.loadGame(widget.gameId);
    if (!mounted || state == null) return;

    final round = state.rounds.firstWhere((r) => r.id == widget.roundId);
    final entries = state.entriesFor(round);

    setState(() {
      _state = state;
      _round = round;
      _bids.clear();
      _tricks.clear();
      for (final entry in entries) {
        final id = entry.playerId;
        _bids[id] = entry.bid;
        _tricks[id] = entry.tricksWon;
      }
    });
  }

  bool get _bidsLocked => _round?.status != RoundStatus.pending;

  /// Untouched rows count as zero, so a bid/trick of 0 never needs a tap.
  /// Missing rows only block the buttons when there are no rows at all.
  bool get _bidsReady => _bids.isNotEmpty;

  int get _bidTotal =>
      _bids.values.fold<int>(0, (sum, bid) => sum + (bid ?? 0));

  int get _trickTotal =>
      _tricks.values.fold<int>(0, (sum, tricks) => sum + (tricks ?? 0));

  int get _availableTricks => totalTricksAvailable(_round!.cardsDealt);

  bool get _tricksAddUp =>
      _tricks.isNotEmpty && _trickTotal == _availableTricks;

  /// Whether the optional "bids may not add up" house rule bites this round.
  ///
  /// Round one deals a single card, so the only legal bids are 0 and 1 and the
  /// table can reach the trick count by accident. The rule therefore starts at
  /// round two, where there is room to deliberately break even or not.
  bool get _evenBidRuleApplies =>
      _state?.game.evenBidRule == true && _round!.roundNumber > 1;

  /// True when the bids would tie the tricks available, which the house rule
  /// (when it applies) forbids the last bidder from causing.
  bool get _bidsBreakEvenRule =>
      _evenBidRuleApplies && _bidTotal == _availableTricks;

  Future<void> _lockBids() async {
    if (!_bidsReady || _bidsBreakEvenRule || _busy) return;
    setState(() => _busy = true);
    final services = _services!;

    await services.games.saveBids(widget.roundId, <int, int>{
      for (final e in _bids.entries) e.key: e.value ?? 0,
    });
    await services.games.lockBids(widget.roundId);
    await _load();

    if (mounted) setState(() => _busy = false);
  }

  Future<void> _roundDone() async {
    if (!_tricksAddUp || _busy) return;
    setState(() => _busy = true);

    final services = _services!;
    final state = _state!;
    final round = _round!;
    final navigator = Navigator.of(context);

    try {
      await services.games.completeRound(
        gameId: widget.gameId,
        roundId: widget.roundId,
        roundNumber: round.roundNumber,
        cardsDealt: round.cardsDealt,
        tricksWon: <int, int>{
          for (final entry in _tricks.entries) entry.key: entry.value ?? 0,
        },
        totalRounds: state.roundsPerPlayer,
      );
      services.events.changed();

      if (!mounted) return;

      final isLastRound = round.roundNumber == state.roundsPerPlayer;
      if (isLastRound) {
        // Last round played: straight to the crown.
        await navigator.pushReplacement<void, void>(
          MaterialPageRoute<void>(
            builder: (_) => WinnerScreen(gameId: widget.gameId),
          ),
        );
      } else {
        navigator.pop();
      }
    } on RoundValidationException catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  /// Gives up on this round: no bids, no tricks, no points. The round stays on
  /// the score sheet as a gap and the game moves past it.
  Future<void> _skipRound() async {
    final round = _round;
    if (round == null || _busy) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Skip round ${round.roundNumber}?'),
        content: Text(
          'Round ${round.roundNumber} is dealt ${round.cardsDealt} card'
          '${round.cardsDealt == 1 ? '' : 's'} each. Skipping it scores '
          'nobody anything${_bidsLocked ? ', and the bids already locked are '
                    'thrown away' : ''}.',
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
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final services = _services!;
    final navigator = Navigator.of(context);

    await services.games.skipRound(roundId: widget.roundId);
    services.events.changed();

    if (!mounted) return;
    final refreshed = await services.games.loadGame(widget.gameId);
    if (!mounted) return;

    if (refreshed?.isGameOver ?? false) {
      // Skipping was the last thing left to do, so the game is decided.
      await navigator.pushReplacement<void, void>(
        MaterialPageRoute<void>(
          builder: (_) => WinnerScreen(gameId: widget.gameId),
        ),
      );
    } else {
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final round = _round;
    if (state == null || round == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Round')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final isFinalRound = round.roundNumber == state.roundsPerPlayer;

    return Scaffold(
      appBar: AppBar(
        title: Text('Round ${round.roundNumber}'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Skip round',
            onPressed: _busy ? null : _skipRound,
            icon: const Icon(Icons.skip_next),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${round.cardsDealt} card${round.cardsDealt == 1 ? '' : 's'} each'
              ' · $_availableTricks tricks'
              ' · seat ${round.dealerSeat + 1} deals',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: <Widget>[
          _bidSummary(),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                  child: Row(
                    children: <Widget>[
                      const Expanded(flex: 3, child: SizedBox()),
                      Expanded(
                        flex: 2,
                        child: Text(
                          'Bids',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: _bidsLocked
                                ? Colors.white38
                                : WizardColors.goldMid,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          'Tricks won',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: _bidsLocked
                                ? WizardColors.goldMid
                                : Colors.white38,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                for (final standing in state.standings)
                  RoundEntryRow(
                    player: standing.player,
                    cardsDealt: round.cardsDealt,
                    bid: _bids[standing.player.id!],
                    tricks: _tricks[standing.player.id!],
                    bidsLocked: _bidsLocked,
                    onBidChanged: (value) =>
                        setState(() => _bids[standing.player.id!] = value),
                    onTricksChanged: (value) =>
                        setState(() => _tricks[standing.player.id!] = value),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          SafeArea(child: _bottomActions(isFinalRound)),
        ],
      ),
    );
  }

  /// Lock the bids, then finish the round. Only one of the two is ever shown.
  Widget _bottomActions(bool isFinalRound) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: _bidsLocked
          ? Column(
              children: <Widget>[
                Text(
                  _tricksAddUp
                      ? 'Ready: $_trickTotal of $_availableTricks tricks '
                            'accounted for.'
                      : 'Tricks must add up to $_availableTricks. '
                            'So far: $_trickTotal.',
                  style: TextStyle(
                    color: _tricksAddUp
                        ? const Color(0xFF9CE5B4)
                        : Colors.white70,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _tricksAddUp && !_busy ? _roundDone : null,
                    icon: const Icon(Icons.check),
                    label: Text(
                      isFinalRound
                          ? 'Round done · see the winner'
                          : 'Round done',
                    ),
                  ),
                ),
              ],
            )
          : Column(
              children: <Widget>[
                Text(
                  _bidsBreakEvenRule
                      ? 'House rule: change a bid so the total is not '
                            '$_availableTricks.'
                      : _bidsReady
                      ? 'Bids total $_bidTotal of $_availableTricks tricks.'
                      : 'Enter every bid, then lock them.',
                  style: TextStyle(
                    fontSize: 13,
                    color: _bidsBreakEvenRule
                        ? WizardColors.goldMid
                        : Colors.white70,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _bidsReady && !_bidsBreakEvenRule && !_busy
                        ? _lockBids
                        : null,
                    icon: const Icon(Icons.lock_outline),
                    label: const Text('Lock bids'),
                  ),
                ),
              ],
            ),
    );
  }

  /// Nags when the optional even-bid house rule is about to be broken.
  Widget _bidSummary() {
    if (!_bidsBreakEvenRule) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: WizardColors.goldMid.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'House rule on: the bids add up to exactly $_availableTricks, so the '
        'last bidder must change theirs.',
        style: const TextStyle(fontSize: 13),
      ),
    );
  }
}

/// One player's row in a round: name, bid stepper, tricks stepper.
///
/// The bids column is disabled once locked; the tricks column is disabled until
/// then, which is what makes the lock meaningful.
class RoundEntryRow extends StatelessWidget {
  const RoundEntryRow({
    required this.player,
    required this.cardsDealt,
    required this.bid,
    required this.tricks,
    required this.bidsLocked,
    required this.onBidChanged,
    required this.onTricksChanged,
    super.key,
  });

  final Player player;
  final int cardsDealt;
  final int? bid;
  final int? tricks;
  final bool bidsLocked;
  final ValueChanged<int> onBidChanged;
  final ValueChanged<int> onTricksChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 3,
            child: Row(
              children: <Widget>[
                PlayerAvatar(player: player, size: 34),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    player.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: RoundCounter(
              value: bid,
              max: cardsDealt,
              enabled: !bidsLocked,
              onChanged: onBidChanged,
            ),
          ),
          Expanded(
            flex: 2,
            child: RoundCounter(
              value: tricks,
              max: cardsDealt,
              enabled: bidsLocked,
              onChanged: onTricksChanged,
            ),
          ),
        ],
      ),
    );
  }
}

/// A compact minus / value / plus counter.
///
/// Starts unset: minus sets it to zero, plus to one, so a bid of zero needs a
/// single tap rather than a detour.
class RoundCounter extends StatelessWidget {
  const RoundCounter({
    required this.value,
    required this.max,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final int? value;
  final int max;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final current = value;
    final canDecrease = enabled && (current == null || current > 0);
    final canIncrease = enabled && (current == null || current < max);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        _CounterButton(
          icon: Icons.remove,
          enabled: canDecrease,
          onPressed: () => onChanged(current == null ? 0 : current - 1),
        ),
        SizedBox(
          width: 32,
          child: Text(
            current?.toString() ?? '–',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: enabled
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.35),
            ),
          ),
        ),
        _CounterButton(
          icon: Icons.add,
          enabled: canIncrease,
          onPressed: () => onChanged(current == null ? 1 : current + 1),
        ),
      ],
    );
  }
}

class _CounterButton extends StatelessWidget {
  const _CounterButton({
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 20,
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon),
        style: IconButton.styleFrom(
          backgroundColor: Colors.white.withValues(
            alpha: enabled ? 0.10 : 0.03,
          ),
        ),
      ),
    );
  }
}
