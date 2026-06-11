/// The three-space shell (spec §4.1): VOTE / ORGANIZE / YOU bottom
/// navigation + the universal JOIN action. Structural — R3 fills the spaces,
/// not this scaffold.
library;

import 'package:design_system/theme.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppShellScaffold extends StatelessWidget {
  final StatefulNavigationShell shell;

  const AppShellScaffold({super.key, required this.shell});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: shell,
    floatingActionButton: FloatingActionButton.extended(
      heroTag: 'join-fab',
      backgroundColor: Db.segnale,
      foregroundColor: Db.void_,
      onPressed: () => context.push('/join'),
      icon: const Icon(Icons.qr_code_scanner),
      label: Text('JOIN', style: dbMono(13, Db.void_)),
    ),
    floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    bottomNavigationBar: NavigationBar(
      selectedIndex: shell.currentIndex,
      onDestinationSelected: (index) =>
          shell.goBranch(index, initialLocation: index == shell.currentIndex),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.how_to_vote_outlined),
          selectedIcon: Icon(Icons.how_to_vote),
          label: 'VOTE',
        ),
        NavigationDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard),
          label: 'ORGANIZE',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: 'YOU',
        ),
      ],
    ),
  );
}
