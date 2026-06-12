/// The three-space shell (spec §4.1): VOTE / ORGANIZE / YOU bottom
/// navigation + the universal JOIN action. Structural — R3 fills the spaces,
/// not this scaffold.
///
/// JOIN is the "droplet": a circular button docked into a notch cut out of
/// the square bottom bar, half above the bar and half sunk into it
/// (`FloatingActionButtonLocation.centerDocked` + [CircularNotchedRectangle]).
/// It is the ONE deliberate circle in the Dark Bauhaus design — everything
/// else stays sharp. The dot-grid body shows through the notch meniscus
/// because the shell extends the body behind the bar ([Scaffold.extendBody]).
library;

import 'package:design_system/theme.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../routing/safe_navigation.dart';

/// Content height of the bottom bar (safe-area inset is added on top).
const double kShellBarHeight = 64;

/// Clearance kept between the tab rows and the docked droplet
/// (56 droplet + 2 x 6 notch margin, rounded up for breathing room).
const double _notchClearance = 76;

class AppShellScaffold extends StatelessWidget {
  final StatefulNavigationShell shell;

  const AppShellScaffold({super.key, required this.shell});

  @override
  Widget build(BuildContext context) => Scaffold(
    // Body extends behind the bar so the dot-grid background is what shows
    // through the notch gap around the droplet. Space screens already pad
    // their scrollables (bottom: 96 >= bar 64 + droplet overhang 28).
    extendBody: true,
    body: shell,
    floatingActionButton: _JoinDroplet(
      // pushOnce: a rapid double-tap (or re-fire while /join is already
      // open) is a no-op instead of stacking a second /join page — the tab
      // re-tap convention applied to the droplet.
      onPressed: () => context.pushOnce('/join'),
    ),
    floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    bottomNavigationBar: BottomAppBar(
      color: Db.slate3,
      elevation: 0,
      padding: EdgeInsets.zero,
      height: kShellBarHeight + MediaQuery.paddingOf(context).bottom,
      shape: const CircularNotchedRectangle(),
      notchMargin: 6,
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // VOTE + ORGANIZE flank the droplet on the left; YOU balances
            // the right half (the IA has exactly three spaces, so the
            // halves are equal-width with even spacing inside each).
            Expanded(
              child: Row(
                children: [
                  _ShellTab(
                    icon: Icons.how_to_vote_outlined,
                    selectedIcon: Icons.how_to_vote,
                    label: 'VOTE',
                    selected: shell.currentIndex == 0,
                    onTap: () => _goBranch(0),
                  ),
                  _ShellTab(
                    icon: Icons.dashboard_outlined,
                    selectedIcon: Icons.dashboard,
                    label: 'ORGANIZE',
                    selected: shell.currentIndex == 1,
                    onTap: () => _goBranch(1),
                  ),
                ],
              ),
            ),
            const SizedBox(width: _notchClearance),
            Expanded(
              child: Row(
                children: [
                  _ShellTab(
                    icon: Icons.person_outline,
                    selectedIcon: Icons.person,
                    label: 'YOU',
                    selected: shell.currentIndex == 2,
                    onTap: () => _goBranch(2),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  void _goBranch(int index) =>
      shell.goBranch(index, initialLocation: index == shell.currentIndex);
}

/// The circular JOIN droplet. Segnale fill, hairline [Db.rule] ring, chalk
/// glyphs. The label lives INSIDE the circle (small stamped mono caption
/// under the icon) so nothing floats over body content below the bar.
class _JoinDroplet extends StatelessWidget {
  final VoidCallback onPressed;

  const _JoinDroplet({required this.onPressed});

  @override
  Widget build(BuildContext context) => FloatingActionButton(
    heroTag: 'join-fab',
    tooltip: 'Join with a code',
    elevation: 0,
    focusElevation: 0,
    hoverElevation: 0,
    highlightElevation: 0,
    backgroundColor: Db.segnale,
    foregroundColor: Db.chalk,
    shape: const CircleBorder(side: BorderSide(color: Db.rule)),
    onPressed: onPressed,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.qr_code_scanner, size: 20),
        const SizedBox(height: 2),
        Text('JOIN', style: dbLabel(size: 8, color: Db.chalk, wght: 700)),
      ],
    ),
  );
}

/// One square tab cell: icon over a stamped mono label, segnale when active.
/// Fills its flex cell edge-to-edge so the whole cell is the hit target.
class _ShellTab extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ShellTab({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Expanded(
    child: Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? selectedIcon : icon,
              size: 22,
              color: selected ? Db.segnale : Db.mute,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: dbLabel(
                size: 9,
                color: selected ? Db.chalk : Db.mute,
                wght: selected ? 700 : 500,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
