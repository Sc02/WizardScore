import 'package:flutter/material.dart';

import 'data/services.dart';
import 'theme/theme.dart';
import 'ui/screens/history_screen.dart';
import 'ui/screens/leaderboard_screen.dart';
import 'ui/screens/play_screen.dart';
import 'ui/screens/players_screen.dart';

/// Root of the app: theme, services scope, and the four-tab shell.
class WizardApp extends StatelessWidget {
  const WizardApp({required this.services, super.key});

  final Services services;

  @override
  Widget build(BuildContext context) {
    return ServicesScope(
      services: services,
      child: MaterialApp(
        title: 'WizardScore',
        debugShowCheckedModeBanner: false,
        theme: buildWizardTheme(),
        home: const HomeShell(),
      ),
    );
  }
}

/// Bottom navigation shell: Play, Players, Leaderboard, History.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const <Widget>[
          PlayScreen(),
          PlayersScreen(),
          LeaderboardScreen(),
          HistoryScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.play_circle_outline),
            selectedIcon: Icon(Icons.play_circle),
            label: 'Play',
          ),
          NavigationDestination(
            icon: Icon(Icons.group_outlined),
            selectedIcon: Icon(Icons.group),
            label: 'Players',
          ),
          NavigationDestination(
            icon: Icon(Icons.leaderboard_outlined),
            selectedIcon: Icon(Icons.leaderboard),
            label: 'Leaderboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'History',
          ),
        ],
      ),
    );
  }
}
