import 'package:flutter/material.dart';

import '../../models/player.dart';
import '../../theme/palette.dart';

/// A round avatar disc showing a player's initials on their chosen colour.
///
/// Uses initials rather than photos, so the app needs no camera, no gallery and
/// no runtime permissions at all. Scales from a small seat chip to the large
/// disc on the winner screen.
class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar({
    required this.player,
    this.size = 40,
    this.showBorder = false,
    super.key,
  });

  final Player player;
  final double size;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    final palette = playerColorAt(player.colorIndex);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.color,
        shape: BoxShape.circle,
        border: showBorder
            ? Border.all(color: palette.shade, width: size > 64 ? 4 : 2)
            : null,
      ),
      child: Text(
        player.initials,
        style: TextStyle(
          color: palette.onColor,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.4,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// A small colour dot plus seat label, used in the score sheet headers.
class PlayerChip extends StatelessWidget {
  const PlayerChip({required this.player, this.trailing, super.key});

  final Player player;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = playerColorAt(player.colorIndex);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: palette.color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            player.name,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (trailing != null) ...<Widget>[const SizedBox(width: 8), trailing!],
      ],
    );
  }
}
