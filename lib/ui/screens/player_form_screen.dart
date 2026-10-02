import 'package:flutter/material.dart';

import '../../data/player_repository.dart';
import '../../data/services.dart';
import '../../models/player.dart';
import '../../theme/palette.dart';
import '../widgets/player_avatar.dart';

/// Create or edit a player: a unique name plus one of twelve avatar colours.
///
/// The duplicate-name check runs live as you type and again on save, so the
/// error appears under the field rather than surfacing as a crash.
class PlayerFormScreen extends StatefulWidget {
  const PlayerFormScreen({this.existing, super.key});

  /// `null` when adding a new player.
  final Player? existing;

  @override
  State<PlayerFormScreen> createState() => _PlayerFormScreenState();
}

class _PlayerFormScreenState extends State<PlayerFormScreen> {
  final TextEditingController _name = TextEditingController();
  late int _colorIndex;
  String? _error;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name.text = existing?.name ?? '';
    _colorIndex = existing?.colorIndex ?? 0;
    if (existing == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _pickFreeColor());
    }
  }

  /// Suggests a colour nobody in the roster is using, so a table looks varied.
  Future<void> _pickFreeColor() async {
    if (!mounted) return;
    final services = ServicesScope.of(context);
    final rows = await services.games.leaderboard();
    if (!mounted) return;
    final taken = rows.map((row) => row.player.colorIndex).toSet();
    for (var index = 0; index < playerColorCount; index++) {
      if (!taken.contains(index)) {
        setState(() => _colorIndex = index);
        return;
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _checkName(String value) async {
    final services = ServicesScope.of(context);
    final problem = await services.players.nameProblem(
      value,
      ignoreId: widget.existing?.id,
    );
    if (!mounted) return;
    setState(() => _error = problem);
  }

  Future<void> _save() async {
    final services = ServicesScope.of(context);
    setState(() => _saving = true);

    try {
      final existing = widget.existing;
      if (existing == null) {
        await services.players.create(
          name: _name.text,
          colorIndex: _colorIndex,
        );
      } else {
        await services.players.update(
          existing.copyWith(name: _name.text, colorIndex: _colorIndex),
        );
      }
      services.events.changed();
      if (mounted) Navigator.of(context).pop(true);
    } on DuplicatePlayerNameException catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } on ArgumentError catch (error) {
      if (mounted) setState(() => _error = error.message.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final typed = _name.text.trim();
    final preview = Player(
      name: typed.isEmpty ? '?' : typed,
      colorIndex: _colorIndex,
    );

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit player' : 'Add player')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Center(
            child: PlayerAvatar(player: preview, size: 96, showBorder: true),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _name,
            autofocus: !_isEditing,
            textCapitalization: TextCapitalization.words,
            maxLength: 24,
            decoration: InputDecoration(
              labelText: 'Name',
              hintText: 'e.g. Suchit',
              errorText: _error,
              prefixIcon: const Icon(Icons.person_outline),
            ),
            onChanged: (value) {
              setState(() {}); // refresh the initials preview
              _checkName(value);
            },
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 8),
          const Text(
            'Colour',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: <Widget>[
              for (var index = 0; index < playerColorCount; index++)
                ColorSwatchOption(
                  index: index,
                  selected: index == _colorIndex,
                  onTap: () => setState(() => _colorIndex = index),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            playerColorAt(_colorIndex).name,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_isEditing ? 'Save changes' : 'Add player'),
          ),
        ],
      ),
    );
  }
}

/// One tappable avatar colour in the picker.
class ColorSwatchOption extends StatelessWidget {
  const ColorSwatchOption({
    required this.index,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final int index;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = playerColorAt(index);
    return Semantics(
      label: palette.name,
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: palette.color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? Colors.white : Colors.transparent,
              width: 3,
            ),
          ),
          child: selected ? Icon(Icons.check, color: palette.onColor) : null,
        ),
      ),
    );
  }
}
