import 'package:flutter/material.dart';

import '../../data/services.dart';
import '../../domain/rules.dart';
import '../../models/player.dart';
import '../widgets/player_avatar.dart';
import 'player_form_screen.dart';
import 'score_sheet_screen.dart';

/// Seats three to six players and starts a game.
///
/// The round structure, card counts and dealer rotation are all derived from
/// the table size, and shown here so the group knows what they are in for.
class NewGameScreen extends StatefulWidget {
  const NewGameScreen({super.key});

  @override
  State<NewGameScreen> createState() => _NewGameScreenState();
}

class _NewGameScreenState extends State<NewGameScreen> {
  Services? _services;
  List<Player>? _roster;

  /// Player ids in the order they were picked, which becomes seat order.
  final List<int> _seats = <int>[];
  bool _evenBidRule = false;
  bool _starting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = ServicesScope.of(context);
    if (identical(services, _services)) return;
    _services = services;
    _loadRoster();
  }

  Future<void> _loadRoster() async {
    final roster = await _services!.players.listActive();
    if (!mounted) return;
    setState(() {
      _roster = roster;
      // Drop anyone who is no longer selectable.
      _seats.removeWhere((id) => !roster.any((player) => player.id == id));
    });
  }

  void _toggle(Player player) {
    final id = player.id!;
    setState(() {
      if (_seats.contains(id)) {
        _seats.remove(id);
      } else if (_seats.length < maxPlayers) {
        _seats.add(id);
      }
    });
  }

  bool get _canStart =>
      _seats.length >= minPlayers && _seats.length <= maxPlayers && !_starting;

  Future<void> _start() async {
    setState(() => _starting = true);
    final services = _services!;
    final navigator = Navigator.of(context);

    final gameId = await services.games.startGame(
      playerIds: _seats,
      evenBidRule: _evenBidRule,
    );
    services.events.changed();

    if (!mounted) return;
    await navigator.pushReplacement<void, void>(
      MaterialPageRoute<void>(builder: (_) => ScoreSheetScreen(gameId: gameId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final roster = _roster;

    return Scaffold(
      appBar: AppBar(title: const Text('New game')),
      body: roster == null
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(roster),
    );
  }

  Widget _buildBody(List<Player> roster) {
    final playerCount = _seats.length;
    final enoughPlayers = playerCount >= minPlayers;

    return Column(
      children: <Widget>[
        Expanded(
          child: roster.isEmpty
              ? _NoPlayers(onAdded: _loadRoster)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  children: <Widget>[
                    _Summary(seats: _seats.length),
                    const SizedBox(height: 16),
                    for (final player in roster)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _SeatTile(
                          player: player,
                          seat: _seats.indexOf(player.id!) + 1,
                          onTap: () => _toggle(player),
                        ),
                      ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      value: _evenBidRule,
                      onChanged: (value) =>
                          setState(() => _evenBidRule = value),
                      title: const Text('Last bidder cannot even the bids'),
                      subtitle: Text(
                        'Optional house rule: the total of all bids may not equal '
                        'the tricks available. Off by default, because the '
                        'official rules allow an even split.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: <Widget>[
                if (!enoughPlayers)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      'Pick at least $minPlayers players '
                      '($minPlayers-$maxPlayers allowed)',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _canStart ? _start : null,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(
                      enoughPlayers
                          ? 'Start game · $playerCount players · '
                                '${roundsForPlayers(playerCount)} rounds'
                          : 'Start game',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Shows the derived shape of the game for the current selection.
class _Summary extends StatelessWidget {
  const _Summary({required this.seats});

  final int seats;

  @override
  Widget build(BuildContext context) {
    if (seats < minPlayers) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              const Icon(Icons.info_outline),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Tap players in seating order. The first tap deals first.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final rounds = roundsForPlayers(seats);
    final cards = maxCardsPerPlayer(seats);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '$seats players · $rounds rounds',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
            const SizedBox(height: 6),
            Text(
              'Rounds count up from 1 card to $cards cards each, and the '
              'final round deals the whole deck.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A selectable player, showing its seat number once picked.
class _SeatTile extends StatelessWidget {
  const _SeatTile({
    required this.player,
    required this.seat,
    required this.onTap,
  });

  final Player player;

  /// 1-based seat, or 0 when not picked.
  final int seat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final picked = seat > 0;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: <Widget>[
              PlayerAvatar(player: player, size: 44),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  player.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              if (picked)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Seat $seat',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                )
              else
                Icon(
                  Icons.add_circle_outline,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown when the roster is empty and a game cannot be started yet.
class _NoPlayers extends StatelessWidget {
  const _NoPlayers({required this.onAdded});

  final Future<void> Function() onAdded;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.person_add_alt, size: 72, color: Colors.white24),
            const SizedBox(height: 16),
            const Text(
              'Add some players first',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () async {
                await Navigator.of(context).push<bool>(
                  MaterialPageRoute<bool>(
                    builder: (_) => const PlayerFormScreen(),
                  ),
                );
                await onAdded();
              },
              child: const Text('Add a player'),
            ),
          ],
        ),
      ),
    );
  }
}
