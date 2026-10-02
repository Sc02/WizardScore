import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/services.dart';
import '../../models/game.dart';
import '../../theme/palette.dart';
import 'score_sheet_screen.dart';

/// Every game the app knows about, newest first.
///
/// Nothing here is cached: a rewind, a finish or a delete fires [AppEvents], so
/// this screen simply re-asks the repository and cannot drift from the database.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  Services? _services;
  Future<List<GameSummary>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // InheritedWidget lookups are only legal from here (or build), not initState.
    final services = ServicesScope.of(context);
    if (identical(services, _services)) return;
    _services?.events.removeListener(_onChanged);
    _services = services;
    services.events.addListener(_onChanged);
    _future = services.games.history();
  }

  void _onChanged() {
    final services = _services;
    if (!mounted || services == null) return;
    // Start the read outside setState: a setState callback must be synchronous
    // and must not return a value.
    final future = services.games.history();
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
      appBar: AppBar(title: const Text('History')),
      body: FutureBuilder<List<GameSummary>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final summaries = snapshot.data!;
          if (summaries.isEmpty) return const EmptyHistory();
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            itemCount: summaries.length,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: HistoryTile(summary: summaries[index]),
            ),
          );
        },
      ),
    );
  }
}

/// The card shown for one game. Tapping it opens that game's score sheet.
class HistoryTile extends StatelessWidget {
  const HistoryTile({required this.summary, super.key});

  final GameSummary summary;

  static final DateFormat _dateFormat = DateFormat('d MMM yyyy, HH:mm');

  @override
  Widget build(BuildContext context) {
    final finished = summary.isFinished;
    final players = summary.standings.length;
    final topScore = summary.podium.isEmpty
        ? 0
        : summary.podium.first.totalScore;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ScoreSheetScreen(gameId: summary.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: finished
                      ? WizardColors.goldMid.withValues(alpha: 0.22)
                      : Colors.white.withValues(alpha: 0.08),
                ),
                child: Icon(
                  finished ? Icons.emoji_events : Icons.hourglass_bottom,
                  color: finished
                      ? WizardColors.goldMid
                      : Colors.white.withValues(alpha: 0.55),
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      finished ? summary.winnerNames : 'In progress',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _subtitle(players, topScore),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 13,
                      ),
                    ),
                    if (finished && !summary.winsCounted)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'Win not counted yet',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Colors.white.withValues(alpha: 0.35),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitle(int players, int topScore) {
    final parts = <String>[
      _dateFormat.format(summary.startedAt),
      '$players player${players == 1 ? '' : 's'}',
    ];
    if (summary.isFinished) {
      parts.add('top score $topScore');
      if (summary.isTie) parts.add('tie');
    }
    return parts.join(' · ');
  }
}

/// Shown when no game has been played yet.
class EmptyHistory extends StatelessWidget {
  const EmptyHistory({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              Icons.history,
              size: 72,
              color: Colors.white.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            const Text(
              'No games yet',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Finished games land here with their winner, so you can look back '
              'at any score sheet at any time.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
          ],
        ),
      ),
    );
  }
}
