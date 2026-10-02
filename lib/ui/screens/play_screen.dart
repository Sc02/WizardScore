import 'package:flutter/material.dart';

import '../../data/services.dart';
import '../../domain/game_state.dart';
import '../../theme/palette.dart';
import '../widgets/game_cards.dart';
import '../widgets/rules_sheet.dart';
import 'new_game_screen.dart';
import 'score_sheet_screen.dart';

/// The Play tab: resume a game in progress, or start a new one.
class PlayScreen extends StatefulWidget {
  const PlayScreen({super.key});

  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends State<PlayScreen> {
  Services? _services;
  Future<GameState?>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = ServicesScope.of(context);
    if (identical(services, _services)) return;
    _services?.events.removeListener(_onChanged);
    _services = services;
    services.events.addListener(_onChanged);
    _future = services.games.loadCurrentGame();
  }

  void _onChanged() {
    final services = _services;
    if (!mounted || services == null) return;
    // Start the read outside setState: a setState callback must be synchronous
    // and must not return a value.
    final future = services.games.loadCurrentGame();
    setState(() {
      _future = future;
    });
  }

  @override
  void dispose() {
    _services?.events.removeListener(_onChanged);
    super.dispose();
  }

  Future<void> _openGame(GameState state) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ScoreSheetScreen(gameId: state.game.id!),
      ),
    );
    if (mounted) _onChanged();
  }

  Future<void> _newGame() async {
    final started = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const NewGameScreen()),
    );
    if (started ?? false) _onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WizardScore'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Rules',
            onPressed: () => showRulesSheet(context),
            icon: const Icon(
              Icons.menu_book_outlined,
              color: WizardColors.goldMid,
            ),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: FutureBuilder<GameState?>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final state = snapshot.data;
                if (state == null) return NoGamePrompt(onStart: _newGame);
                return LiveGameCard(
                  state: state,
                  onResume: () => _openGame(state),
                );
              },
            ),
          ),
          const _Credit(),
        ],
      ),
    );
  }
}

/// The small sign-off pinned under the Play tab.
class _Credit extends StatelessWidget {
  const _Credit();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        'Made by Chesu',
        style: TextStyle(
          fontSize: 11,
          color: Colors.white.withValues(alpha: 0.35),
        ),
      ),
    );
  }
}
