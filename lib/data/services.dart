import 'package:flutter/widgets.dart';

import 'db.dart';
import 'game_repository.dart';
import 'player_repository.dart';

/// Broadcasts "something changed" so open screens can reload.
///
/// Deliberately tiny: the app has no server and no complex state graph, so a
/// plain notifier plus on-demand repository reads is all that is needed. This
/// is what keeps the leaderboard and score sheet in step after a round, a
/// finish or a time-travel rewind.
class AppEvents extends ChangeNotifier {
  /// Call after any write that other screens might be displaying.
  void changed() => notifyListeners();
}

/// The database and repositories for the running app.
class Services {
  Services({
    required this.db,
    required this.players,
    required this.games,
    required this.events,
  });

  final WizardDatabase db;
  final PlayerRepository players;
  final GameRepository games;
  final AppEvents events;

  /// Opens the on-device database and wires up the repositories.
  static Future<Services> boot() async {
    final db = await WizardDatabase.open();
    return Services(
      db: db,
      players: PlayerRepository(db),
      games: GameRepository(db),
      events: AppEvents(),
    );
  }

  /// For tests and previews: run against an already-open database.
  static Services from(WizardDatabase db) => Services(
    db: db,
    players: PlayerRepository(db),
    games: GameRepository(db),
    events: AppEvents(),
  );
}

/// Makes [Services] available to the widget tree.
class ServicesScope extends InheritedWidget {
  const ServicesScope({
    required this.services,
    required super.child,
    super.key,
  });

  final Services services;

  static Services of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ServicesScope>();
    assert(scope != null, 'ServicesScope is missing from the widget tree');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(ServicesScope oldWidget) =>
      oldWidget.services != services;
}
