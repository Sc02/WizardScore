import 'package:flutter/material.dart';

import '../../data/services.dart';
import '../../models/game.dart';
import '../widgets/empty_states.dart';
import '../widgets/player_avatar.dart';

/// The trophy table: players ranked by games won.
///
/// Every number here is derived from finished games rather than a cached
/// counter, so a time-travel rewind is reflected immediately.
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  Services? _services;
  Future<List<LeaderboardRow>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // InheritedWidget lookups are only legal from here (or build), not initState.
    final services = ServicesScope.of(context);
    if (identical(services, _services)) return;
    _services?.events.removeListener(_onChanged);
    _services = services;
    services.events.addListener(_onChanged);
    _future = services.games.leaderboard();
  }

  /// Re-reads the table whenever another screen records a round, finishes a
  /// game or rewinds one: wins are derived, so a plain reload is enough.
  void _onChanged() {
    final services = _services;
    if (!mounted || services == null) return;
    // Start the read outside setState: a setState callback must be synchronous
    // and must not return a value.
    final future = services.games.leaderboard();
    setState(() {
      _future = future;
    });
  }

  @override
  void dispose() {
    _services?.events.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Leaderboard')),
      body: FutureBuilder<List<LeaderboardRow>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snapshot.data!;
          if (rows.isEmpty) return const EmptyRoster();
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            itemCount: rows.length,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: LeaderboardTile(row: rows[index], position: index + 1),
            ),
          );
        },
      ),
    );
  }
}

/// One ranked row. The top three get a medal instead of a number.
class LeaderboardTile extends StatelessWidget {
  const LeaderboardTile({required this.row, required this.position, super.key});

  final LeaderboardRow row;
  final int position;

  static const List<Color> _medals = <Color>[
    Color(0xFFD4AF37), // gold
    Color(0xFFBFC5CC), // silver
    Color(0xFFB1743A), // bronze
  ];

  @override
  Widget build(BuildContext context) {
    final medal = position <= 3 ? _medals[position - 1] : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 40,
              child: medal == null
                  ? Text(
                      '$position',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    )
                  : Icon(Icons.emoji_events, color: medal, size: 28),
            ),
            PlayerAvatar(player: row.player, size: 44),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    row.player.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    row.gamesPlayed == 0
                        ? 'No games yet'
                        : '${row.gamesPlayed} game'
                              '${row.gamesPlayed == 1 ? '' : 's'}'
                              ' · ${row.winRateLabel} win rate',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  '${row.wins}',
                  style: TextStyle(
                    color: medal ?? Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 26,
                    height: 1,
                  ),
                ),
                Text(
                  row.wins == 1 ? 'win' : 'wins',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
