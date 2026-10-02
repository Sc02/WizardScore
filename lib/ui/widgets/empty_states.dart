import 'package:flutter/material.dart';

/// Shown when the roster is empty.
class EmptyRoster extends StatelessWidget {
  const EmptyRoster({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              Icons.groups_2_outlined,
              size: 72,
              color: Colors.white.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            const Text(
              'No players yet',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Add everyone at the table, give each one a colour, and they will '
              'build up a win record across every game.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
          ],
        ),
      ),
    );
  }
}
