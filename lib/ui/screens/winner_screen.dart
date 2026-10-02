import 'package:flutter/material.dart';

import '../../data/services.dart';
import '../../domain/game_state.dart';
import '../../domain/rules.dart';
import '../../models/game.dart';
import '../../theme/palette.dart';
import '../../theme/theme.dart';
import '../widgets/player_avatar.dart';

/// The crown moment: winner avatar disc, name, and WINNER in gold.
///
/// The game is only finalised — and the win only credited on the leaderboard —
/// when End game is pressed. Backing out leaves the game in progress, so a
/// mistaken tap cannot award a win.
class WinnerScreen extends StatefulWidget {
  const WinnerScreen({required this.gameId, super.key});

  final int gameId;

  @override
  State<WinnerScreen> createState() => _WinnerScreenState();
}

class _WinnerScreenState extends State<WinnerScreen> {
  Services? _services;
  GameState? _state;
  bool _ending = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _services ??= ServicesScope.of(context);
    if (_state == null) _load();
  }

  Future<void> _load() async {
    final state = await _services!.games.loadGame(widget.gameId);
    if (!mounted) return;
    setState(() => _state = state);
  }

  /// Everyone tied for first. While the game is unfinished this is a preview of
  /// who would win; once finished it is the recorded result.
  List<Standing> get _winners {
    final state = _state!;
    if (state.game.winnerPlayerIds.isNotEmpty) {
      return <Standing>[
        for (final standing in state.standings)
          if (standing.player.id != null &&
              state.game.winnerPlayerIds.contains(standing.player.id))
            standing,
      ];
    }
    final seats = winnerSeats(
      state.standings.map((standing) => standing.totalScore),
    );
    return <Standing>[for (final seat in seats) state.standings[seat]];
  }

  List<Standing> get _runnersUp {
    final state = _state!;
    final winnerIds = _winners.map((standing) => standing.player.id).toSet();
    return state.standings
        .where((standing) => !winnerIds.contains(standing.player.id))
        .toList()
      ..sort((a, b) => b.totalScore.compareTo(a.totalScore));
  }

  Future<void> _endGame() async {
    final state = _state;
    final services = _services;
    if (state == null || services == null || _ending) return;

    setState(() => _ending = true);
    // Idempotent: winners are replaced rather than appended, and the
    // leaderboard counts win rows instead of incrementing a counter, so a
    // second press cannot double count.
    await services.games.finishGame(gameId: widget.gameId);
    services.events.changed();

    if (!mounted) return;
    // Back to the Play tab, which now offers a fresh game.
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    if (state == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final winners = _winners;
    final alreadyCounted = state.game.winsCounted;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[WizardColors.felt, WizardColors.feltDark],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: <Widget>[
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                  child: Column(
                    children: <Widget>[
                      TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 0.6, end: 1),
                        duration: const Duration(milliseconds: 700),
                        curve: Curves.elasticOut,
                        builder: (context, scale, child) =>
                            Transform.scale(scale: scale, child: child),
                        child: const CrownIcon(size: 120),
                      ),
                      const SizedBox(height: 8),
                      for (final winner in winners)
                        WinnerBlock(standing: winner),
                      const SizedBox(height: 20),
                      GoldGradientText(
                        winners.length > 1 ? 'WINNERS' : 'WINNER',
                        fontSize: 40,
                        letterSpacing: 6,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        winners.length > 1
                            ? 'A dead heat: '
                                  '${winners.map((w) => w.player.name).join(' & ')} '
                                  'share the crown.'
                            : '${winners.first.player.name} wins in '
                                  '${state.lastPlayedRound} rounds',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (_runnersUp.isNotEmpty) ...<Widget>[
                        const Divider(),
                        const SizedBox(height: 12),
                        for (final entry in _runnersUp.asMap().entries)
                          RunnerUpRow(
                            standing: entry.value,
                            position: winners.length + entry.key + 1,
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: <Widget>[
                    Text(
                      alreadyCounted
                          ? 'This win is already on the leaderboard.'
                          : 'Ending the game adds this win to the leaderboard.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _ending ? null : _endGame,
                        icon: const Icon(Icons.emoji_events),
                        label: Text(alreadyCounted ? 'Done' : 'End game'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The big avatar and name for a winner.
class WinnerBlock extends StatelessWidget {
  const WinnerBlock({required this.standing, super.key});

  final Standing standing;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        PlayerAvatar(player: standing.player, size: 132, showBorder: true),
        const SizedBox(height: 14),
        Text(
          standing.player.name,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${standing.totalScore} points',
          style: TextStyle(
            fontSize: 15,
            color: Colors.white.withValues(alpha: 0.65),
          ),
        ),
      ],
    );
  }
}

/// One line of the losing standings under the winner.
class RunnerUpRow extends StatelessWidget {
  const RunnerUpRow({
    required this.standing,
    required this.position,
    super.key,
  });

  final Standing standing;
  final int position;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 32,
            child: Text(
              '$position',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          PlayerAvatar(player: standing.player, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              standing.player.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            '${standing.totalScore}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// A three-point crown in the app's gold, drawn in code so the winner screen
/// needs no image asset and stays crisp at any size.
class CrownIcon extends StatelessWidget {
  const CrownIcon({this.size = 96, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size(size, size * 0.72),
        painter: _CrownPainter(),
      ),
    );
  }
}

class _CrownPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width * 0.035
      ..strokeJoin = StrokeJoin.round
      ..color = WizardColors.goldDark;

    final gold = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          WizardColors.goldLight,
          WizardColors.goldMid,
          WizardColors.goldDark,
        ],
      ).createShader(Offset.zero & size);

    // Five-point crown: three peaks, two valleys, sitting on a base band.
    final path = Path()
      ..moveTo(width * 0.06, height * 0.34)
      ..lineTo(width * 0.24, height * 0.72)
      ..lineTo(width * 0.50, height * 0.16)
      ..lineTo(width * 0.76, height * 0.72)
      ..lineTo(width * 0.94, height * 0.34)
      ..lineTo(width * 0.88, height * 0.86)
      ..lineTo(width * 0.12, height * 0.86)
      ..close();

    canvas.drawPath(path, gold);
    canvas.drawPath(path, stroke);

    // Jewel on each peak.
    final dot = Paint()..color = WizardColors.goldLight;
    for (final point in <Offset>[
      Offset(width * 0.50, height * 0.10),
      Offset(width * 0.06, height * 0.26),
      Offset(width * 0.94, height * 0.26),
    ]) {
      canvas.drawCircle(point, width * 0.045, dot);
    }
  }

  @override
  bool shouldRepaint(_CrownPainter oldDelegate) => false;
}
