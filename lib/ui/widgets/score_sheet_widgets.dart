import 'package:flutter/material.dart';

import '../../domain/game_state.dart';
import '../../models/game.dart';
import '../../models/round.dart';
import '../../theme/palette.dart';
import 'player_avatar.dart';

/// Consistent row height so the pinned round column, the score rows and the
/// totals bar always line up.
const double kSheetRowHeight = 52;

/// Header strip above the sheet: round progress and who is leading.
class StatusBar extends StatelessWidget {
  const StatusBar({required this.state, super.key});

  final GameState state;

  @override
  Widget build(BuildContext context) {
    final leader = state.standingsByScore.first;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      color: WizardColors.felt.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                '${state.lastPlayedRound}/${state.roundsPerPlayer} rounds '
                'played'
                '${state.skippedRoundCount == 0 ? '' : ' · ${state.skippedRoundCount} skipped'}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              PlayerAvatar(player: leader.player, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${leader.player.name} leads with ${leader.totalScore}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The pinned column of round numbers down the left of the sheet.
class RoundNumberCell extends StatelessWidget {
  const RoundNumberCell({required this.round, required this.isNext, super.key});

  final Round round;
  final bool isNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kSheetRowHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isNext ? WizardColors.nextRound.withValues(alpha: 0.22) : null,
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
          right: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            '${round.roundNumber}',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: round.isSkipped
                  ? Colors.white38
                  : (isNext ? WizardColors.nextRound : Colors.white),
            ),
          ),
          Text(
            round.isSkipped ? 'skip' : '${round.cardsDealt}c',
            style: TextStyle(
              fontSize: 10,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// One round's row of scores, one cell per player in seat order.
class ScoreRow extends StatelessWidget {
  const ScoreRow({
    required this.state,
    required this.round,
    required this.isNext,
    required this.columnWidth,
    super.key,
  });

  final GameState state;
  final Round round;
  final bool isNext;
  final double columnWidth;

  @override
  Widget build(BuildContext context) {
    final entries = state.entriesFor(round);
    final skipped = round.isSkipped;
    return Container(
      height: kSheetRowHeight,
      decoration: BoxDecoration(
        color: skipped
            ? Colors.white.withValues(alpha: 0.04)
            : (isNext ? WizardColors.nextRound.withValues(alpha: 0.12) : null),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        children: <Widget>[
          for (final entry in entries)
            ScoreCell(entry: entry, width: columnWidth),
        ],
      ),
    );
  }
}

/// A single bid/trick/points cell.
///
/// Green means the bid was made, red means it was missed. Player colours are
/// deliberately not used here so the signals stay unambiguous.
class ScoreCell extends StatelessWidget {
  const ScoreCell({required this.entry, required this.width, super.key});

  final RoundEntry entry;
  final double width;

  @override
  Widget build(BuildContext context) {
    final points = entry.points;
    final scored = points != null;
    final made = entry.madeBid;

    final Color? background = !scored
        ? null
        : (made ? WizardColors.bidMade : WizardColors.bidMissed).withValues(
            alpha: 0.22,
          );

    return Container(
      width: width,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        border: Border(
          right: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: !scored
          ? Text(
              '—',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.25)),
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  '${entry.bid} / ${entry.tricksWon}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                ),
                Text(
                  points >= 0 ? '+$points' : '$points',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: made
                        ? const Color(0xFF9CE5B4)
                        : const Color(0xFFFFB4AB),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Header row of player avatars and names, kept in step with the body's
/// horizontal scroll so the two always line up.
class SheetHeader extends StatelessWidget {
  const SheetHeader({
    required this.standings,
    required this.headerController,
    required this.playerAreaWidth,
    required this.roundColWidth,
    required this.playerColWidth,
    super.key,
  });

  final List<Standing> standings;
  final ScrollController headerController;
  final double playerAreaWidth;
  final double roundColWidth;
  final double playerColWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: WizardColors.felt,
      child: Row(
        children: <Widget>[
          SizedBox(
            width: roundColWidth,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'Rd',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: headerController,
              scrollDirection: Axis.horizontal,
              // Driven by the body's controller, never by the user.
              physics: const NeverScrollableScrollPhysics(),
              child: SizedBox(
                width: playerAreaWidth,
                child: Row(
                  children: <Widget>[
                    for (final standing in standings)
                      SizedBox(
                        width: playerColWidth,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 6,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              PlayerAvatar(player: standing.player, size: 30),
                              const SizedBox(height: 4),
                              Text(
                                standing.player.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sticky row of running totals, horizontally in step with the sheet body.
class TotalsBar extends StatelessWidget {
  const TotalsBar({
    required this.state,
    required this.roundColWidth,
    required this.playerColWidth,
    required this.horizontalController,
    super.key,
  });

  final GameState state;
  final double roundColWidth;
  final double playerColWidth;
  final ScrollController horizontalController;

  @override
  Widget build(BuildContext context) {
    final seats = state.standings;
    // Column order must match the body, so this stays in seat order; the
    // leading score is simply marked.
    final best = seats.isEmpty
        ? 0
        : seats
              .map((standing) => standing.totalScore)
              .reduce((a, b) => a > b ? a : b);

    return Container(
      color: WizardColors.felt,
      child: Row(
        children: <Widget>[
          SizedBox(
            width: roundColWidth,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14, horizontal: 4),
              child: Text(
                'Total',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: Colors.white70,
                ),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: horizontalController,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: SizedBox(
                width: seats.length * playerColWidth,
                child: Row(
                  children: <Widget>[
                    for (final standing in seats)
                      SizedBox(
                        width: playerColWidth,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            '${standing.totalScore}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                              color: standing.totalScore == best
                                  ? WizardColors.goldMid
                                  : Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet listing every played round so you can pick a rewind point.
class RewindSheet extends StatelessWidget {
  const RewindSheet({required this.state, super.key});

  final GameState state;

  @override
  Widget build(BuildContext context) {
    // Newest first, so the most likely targets are at the top. A round only
    // works as a rewind target when there is something after it to erase,
    // which means some later round must have been scored or skipped.
    final played = state.rounds
        .where(
          (round) =>
              round.isComplete && round.roundNumber < state.lastResolvedRound,
        )
        .toList(growable: false)
        .reversed
        .toList(growable: false);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.history_toggle_off),
                const SizedBox(width: 10),
                const Text(
                  'Time travel',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Pick a round to return to. Everything after it is erased and the '
              'game carries on from there.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: played.length,
                itemBuilder: (context, index) {
                  final round = played[index];
                  final delta = state.roundPointsDelta(round);
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.white.withValues(alpha: 0.12),
                      child: Text('${round.roundNumber}'),
                    ),
                    title: Text('Back to after round ${round.roundNumber}'),
                    subtitle: Text(
                      'erases rounds ${round.roundNumber + 1}-'
                      '${state.lastResolvedRound}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 12,
                      ),
                    ),
                    trailing: Text(
                      '${delta >= 0 ? '+' : ''}$delta pts',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                    onTap: () => Navigator.of(context).pop(round.roundNumber),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
