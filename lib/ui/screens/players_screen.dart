import 'package:flutter/material.dart';

import '../../data/services.dart';
import '../../models/game.dart';
import '../widgets/empty_states.dart';
import '../widgets/player_avatar.dart';
import 'player_form_screen.dart';

/// The roster: create players, recolour them, rename them, archive them.
class PlayersScreen extends StatefulWidget {
  const PlayersScreen({super.key});

  @override
  State<PlayersScreen> createState() => _PlayersScreenState();
}

class _PlayersScreenState extends State<PlayersScreen> {
  Services? _services;
  Future<List<LeaderboardRow>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = ServicesScope.of(context);
    if (identical(services, _services)) return;
    _services?.events.removeListener(_onChanged);
    _services = services;
    services.events.addListener(_onChanged);
    _future = services.games.leaderboard();
  }

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

  void _reload() {
    final services = _services;
    if (services == null) return;
    final future = services.games.leaderboard();
    setState(() {
      _future = future;
    });
  }

  Future<void> _openForm({LeaderboardRow? existing}) async {
    final services = _services!;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => PlayerFormScreen(existing: existing?.player),
      ),
    );
    if (saved ?? false) {
      services.events.changed();
      _reload();
    }
  }

  Future<void> _archive(LeaderboardRow row) async {
    final services = _services!;
    final id = row.player.id!;

    // A player who has already played is archived rather than deleted, so old
    // games keep resolving to their name.
    final hasPlayed = await services.players.hasPlayed(id);
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Archive ${row.player.name}?'),
        content: Text(
          hasPlayed
              ? 'They will disappear from the roster and from the new game '
                    'picker, but the ${row.gamesPlayed} game'
                    '${row.gamesPlayed == 1 ? '' : 's'} they played keep their '
                    'name and history.'
              : 'They will disappear from the roster.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await services.players.archive(id);
    services.events.changed();
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Players')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.person_add),
        label: const Text('Add player'),
      ),
      body: FutureBuilder<List<LeaderboardRow>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snapshot.data!;
          if (rows.isEmpty) return const EmptyRoster();
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final row = rows[index];
              return Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: PlayerAvatar(player: row.player, size: 48),
                  title: Text(
                    row.player.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                    ),
                  ),
                  subtitle: Text(
                    _subtitleFor(row),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') {
                        _openForm(existing: row);
                      } else if (value == 'archive') {
                        _archive(row);
                      }
                    },
                    itemBuilder: (context) => const <PopupMenuEntry<String>>[
                      PopupMenuItem<String>(
                        value: 'edit',
                        child: ListTile(
                          leading: Icon(Icons.edit),
                          title: Text('Edit name / colour'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      PopupMenuItem<String>(
                        value: 'archive',
                        child: ListTile(
                          leading: Icon(Icons.archive_outlined),
                          title: Text('Archive'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _subtitleFor(LeaderboardRow row) {
    if (row.gamesPlayed == 0) return 'No games yet';
    final wins = '${row.wins} win${row.wins == 1 ? '' : 's'}';
    final played = '${row.gamesPlayed} game${row.gamesPlayed == 1 ? '' : 's'}';
    return '$wins · $played · ${row.winRateLabel}';
  }
}
