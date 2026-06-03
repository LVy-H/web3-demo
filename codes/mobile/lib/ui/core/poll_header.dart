import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'theme.dart';

/// The shared poll-screen header row: a back affordance on the left, then a
/// module badge ("ZK · QUADRATIC", "ZK · ANON", …) and the short poll address
/// badge on the right. Every poll-detail surface (anon / approval / ranked /
/// quadratic / survey) renders the same thing, so the overflow-hardening lives
/// here once.
///
/// Overflow safety on narrow phones (Galaxy A25 ~393px, and down to ~340px),
/// while keeping the original right-aligned badge layout:
///  - The back area is [Flexible] and its label ellipsizes, so it gives way
///    first.
///  - A [Spacer] sits between the back area and the badge group, so the badges
///    stay pinned to the RIGHT edge (the look the original `Expanded` back gave)
///    and collapses to zero before anything overflows.
///  - The module-badge LABEL is wrapped in a `Flexible` + `FittedBox(scaleDown)`
///    so a long badge ("ZK · QUADRATIC") shrinks to fit instead of overflowing,
///    while staying legible at normal widths.
///  - The address badge text ellipsizes inside a `Flexible`.
/// Together these guarantee the row never throws a RenderFlex overflow.
Widget pollDetailHeaderRow({
  required BuildContext context,
  required String badgeLabel,
  required Color badgeColor,
  required String shortAddr,
  String backLabel = 'BACK TO POLLS',
}) =>
    Row(children: [
      Flexible(
        child: InkWell(
          onTap: () => context.canPop() ? context.pop() : context.go('/'),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.arrow_back, size: 14, color: Db.mute),
            const SizedBox(width: 6),
            Flexible(
              child: Text(backLabel,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: dbLabel(size: 11, tracking: 0.16)),
            ),
          ]),
        ),
      ),
      // Pushes the badge group to the right edge (the original look); collapses
      // to zero on a tight row so it never forces an overflow.
      const Spacer(),
      const SizedBox(width: 8),
      // The module badge — its label scales down on a tight row rather than
      // overflowing. Flexible so the whole badge can cede width if needed.
      Flexible(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: badgeColor,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(badgeLabel,
                maxLines: 1,
                style: dbSans(11, 800, Db.void_, letterSpacing: 2.0)),
          ),
        ),
      ),
      const SizedBox(width: 8),
      // The short address badge — ellipsizes if it ever can't fit.
      Flexible(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: const BoxDecoration(
            color: Db.slate,
            border: Border.fromBorderSide(BorderSide(color: Db.rule)),
          ),
          child: Text(shortAddr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: dbMono(11, Db.mute, letterSpacing: 0.5)),
        ),
      ),
    ]);

/// The shared "results card" title row: a leading icon, the section title, and a
/// right-aligned count chip ("12 VOTES", "5 VOTERS", …). The title is [Expanded]
/// + ellipsis and the count is [Flexible] so the row can't overflow when both
/// the title and the count are wide on a narrow screen.
Widget resultsTitleRow({
  required IconData icon,
  required String title,
  required String trailing,
}) =>
    Row(children: [
      Icon(icon, size: 16, color: Db.mute),
      const SizedBox(width: 8),
      Expanded(
        child: Text(title,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: dbSectionTitle),
      ),
      const SizedBox(width: 8),
      Flexible(
        child: Text(trailing,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            textAlign: TextAlign.right,
            style: dbLabel(size: 11, tracking: 0.05)),
      ),
    ]);
