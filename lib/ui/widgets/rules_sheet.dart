import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../theme/palette.dart';

/// Shows the Wizard ruleset, read from `assets/rules.txt`.
///
/// The file is Markdown-flavoured prose, so it is rendered by the small parser
/// below: `##`/`###` become headings, `-` lines become bullets, `1.` lines
/// become numbered items, and everything else is joined into paragraphs. This
/// keeps the app free of a Markdown dependency.
Future<void> showRulesSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: WizardColors.feltDark,
    builder: (_) => const _RulesSheet(),
  );
}

class _RulesSheet extends StatefulWidget {
  const _RulesSheet();

  @override
  State<_RulesSheet> createState() => _RulesSheetState();
}

class _RulesSheetState extends State<_RulesSheet> {
  late final Future<String> _text = rootBundle.loadString('assets/rules.txt');

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.85,
      alignment: Alignment.bottomCenter,
      child: Column(
        children: <Widget>[
          _grabber(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
            child: Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    'How to play Wizard',
                    style: TextStyle(
                      color: WizardColors.goldMid,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.white70),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          Expanded(
            child: FutureBuilder<String>(
              future: _text,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                  children: _parse(snapshot.data ?? ''),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// The little pill at the top of the sheet, a visual cue for the rounded top.
  Widget _grabber() {
    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 6),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.white24,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  /// Turns the raw file into styled blocks.
  ///
  /// The asset is lightly marked up: `## ` is a section heading, `### ` a
  /// sub-heading, `- ` a bullet, `N. ` a numbered item and everything else is
  /// body copy. Consecutive body lines are joined so the source can stay
  /// hard-wrapped without the wraps showing up on screen.
  List<Widget> _parse(String raw) {
    final widgets = <Widget>[];
    final paragraph = <String>[];

    void flush() {
      if (paragraph.isEmpty) return;
      widgets.add(_block(paragraph.join(' ')));
      paragraph.clear();
    }

    for (final line in raw.split('\n')) {
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        flush();
      } else if (trimmed.startsWith('### ')) {
        flush();
        widgets.add(_heading(trimmed.substring(4), sub: true));
      } else if (trimmed.startsWith('## ')) {
        flush();
        widgets.add(_heading(trimmed.substring(3)));
      } else if (trimmed.startsWith('- ')) {
        flush();
        widgets.add(_bullet(trimmed.substring(2), '\u2022  '));
      } else if (_numbered.hasMatch(trimmed)) {
        flush();
        widgets.add(_bullet(trimmed, ''));
      } else {
        paragraph.add(trimmed);
      }
    }
    flush();

    return widgets;
  }

  final RegExp _numbered = RegExp(r'^\d+\.\s');

  Widget _heading(String text, {bool sub = false}) {
    return Padding(
      padding: EdgeInsets.only(top: sub ? 14 : 24, bottom: sub ? 6 : 10),
      child: Text(
        text,
        style: TextStyle(
          color: WizardColors.goldMid,
          fontSize: sub ? 15 : 18,
          fontWeight: FontWeight.w800,
          letterSpacing: sub ? 0.2 : 0.4,
        ),
      ),
    );
  }

  Widget _block(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.88),
          fontSize: 14,
          height: 1.5,
        ),
      ),
    );
  }

  Widget _bullet(String text, String marker) {
    return Padding(
      padding: const EdgeInsets.only(left: 6, bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 20,
            child: Text(
              marker,
              style: TextStyle(
                color: WizardColors.goldLight,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.88),
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
