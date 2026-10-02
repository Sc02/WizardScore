import 'package:flutter/material.dart';

import '../../domain/game_state.dart';
import 'player_avatar.dart';

/// Shown on the Play tab when there is no game in progress.
class NoGamePrompt extends StatelessWidget {
  const NoGamePrompt({required this.onStart, super.key});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.auto_awesome, size: 80, color: Colors.white24),
            const SizedBox(height: 20),
            const Text(
              'Ready to play?',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              'Seat three to six players and the app keeps the score: bids, '
              'tricks, the running table and the winner.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.65)),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start a new game'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A game left mid-flight: offer to carry on where it stopped.
class LiveGameCard extends StatelessWidget {
  const LiveGameCard({required this.state, required this.onResume, super.key});

  final GameState state;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    final next = state.nextRound;
    final leader = state.standingsByScore.first;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(Icons.play_circle, color: Colors.white),
                    const SizedBox(width: 10),
                    const Text(
                      'Game in progress',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${state.lastPlayedRound}/${state.roundsPerPlayer} rounds',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 14,
                  runSpacing: 12,
                  children: <Widget>[
                    for (final standing in state.standings)
                      Column(
                        children: <Widget>[
                          PlayerAvatar(player: standing.player, size: 44),
                          const SizedBox(height: 6),
                          Text(
                            standing.player.name,
                            style: const TextStyle(fontSize: 12),
                          ),
                          Text(
                            '${standing.totalScore}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                const Divider(height: 32),
                Text(
                  next == null
                      ? 'Every round is played. Finish the game to crown a winner.'
                      : 'Up next: round ${next.roundNumber} '
                            '(${next.cardsDealt} card'
                            '${next.cardsDealt == 1 ? '' : 's'} each)',
                  style: const TextStyle(fontSize: 15),
                ),
                const SizedBox(height: 6),
                Text(
                  'Leading: ${leader.player.name} with ${leader.totalScore}',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.65)),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onResume,
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Open score sheet'),
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
