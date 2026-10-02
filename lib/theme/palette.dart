import 'package:flutter/material.dart';

/// The twelve avatars a player can pick from.
///
/// Colours are stored on the player row as an *index* into [playerPalette]
/// rather than as a hex string, so the palette can be retuned (or gain a
/// dark-mode variant) later without a database migration.
///
/// Note: these colours are deliberately NOT reused for score sheet cells. The
/// score sheet reserves green for "bid made" and red for "bid missed", so
/// player colour only ever appears as an avatar disc and a thin header
/// underline.
class PlayerColor {
  const PlayerColor(this.name, this.color);

  /// Human readable label shown next to the swatch in the colour picker.
  final String name;

  /// The actual swatch colour.
  final Color color;

  /// A darker shade used for the header underline / avatar border.
  Color get shade => Color.lerp(color, Colors.black, 0.28)!;

  /// Text colour that stays readable on top of [color].
  Color get onColor =>
      color.computeLuminance() > 0.55 ? Colors.black87 : Colors.white;
}

/// Twelve perceptually distinct options. Index order is stable and persisted,
/// so append new colours at the end rather than inserting.
const List<PlayerColor> playerPalette = <PlayerColor>[
  PlayerColor('Crimson', Color(0xFFD64545)),
  PlayerColor('Coral', Color(0xFFE8703A)),
  PlayerColor('Amber', Color(0xFFE0A32E)),
  PlayerColor('Lime', Color(0xFF8FA83A)),
  PlayerColor('Emerald', Color(0xFF2E9E6B)),
  PlayerColor('Teal', Color(0xFF1F9AA5)),
  PlayerColor('Sky', Color(0xFF2F80D6)),
  PlayerColor('Indigo', Color(0xFF4A56C4)),
  PlayerColor('Violet', Color(0xFF8055C8)),
  PlayerColor('Magenta', Color(0xFFC24BA8)),
  PlayerColor('Rose', Color(0xFFD95C8A)),
  PlayerColor('Slate', Color(0xFF6B7A8F)),
];

/// Number of available avatar colours.
int get playerColorCount => playerPalette.length;

/// Safe lookup that clamps out-of-range or legacy values instead of throwing,
/// so a corrupt row can never crash the roster.
PlayerColor playerColorAt(int index) {
  if (index < 0 || index >= playerPalette.length) return playerPalette.first;
  return playerPalette[index];
}

/// App-wide colour tokens for the Wizard theme.
abstract final class WizardColors {
  /// Deep purple felt, used for app bars and the winner screen backdrop.
  static const Color felt = Color(0xFF2A1E4F);
  static const Color feltDark = Color(0xFF1B1338);

  /// Accent gold, used for the crown, the word WINNER and the end-game action.
  static const Color goldLight = Color(0xFFFFF2A8);
  static const Color goldMid = Color(0xFFD4AF37);
  static const Color goldDark = Color(0xFF9A7B1F);

  /// Semantics reserved by the score sheet.
  static const Color bidMade = Color(0xFF2E7D46);
  static const Color bidMissed = Color(0xFFB33A3A);

  /// Highlight for the round that is up next.
  static const Color nextRound = Color(0xFFB9F6CA);
}
