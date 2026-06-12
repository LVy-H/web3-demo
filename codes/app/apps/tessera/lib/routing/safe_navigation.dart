/// Idempotent imperative navigation.
///
/// Re-triggering a push for the location that is already current is a no-op,
/// mirroring the tab re-tap convention (re-tapping an active tab does
/// nothing). Without this, a rapid double-tap — two taps landing before the
/// push transition covers the button — stacks two copies of the same page:
/// the lower one sits offstage (invisible, but back-navigation lands on the
/// zombie), and for `const` pages both list entries are the SAME canonical
/// instance, corrupting go_router's page→match bookkeeping.
library;

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

extension SafeNavigation on BuildContext {
  /// Pushes [location] unless it is already the topmost location.
  ///
  /// The check reads the router delegate's current configuration, which
  /// go_router updates synchronously during `push` (the parse chain is a
  /// SynchronousFuture when redirects are synchronous, as ours are), so a
  /// double-tap's second push already sees the first push on top. NOTE:
  /// `routeInformationProvider.value` is NOT usable here — it keeps
  /// reporting the BASE location of the match list, which a push never
  /// changes.
  void pushOnce(String location) {
    final router = GoRouter.of(this);
    final matches = router.routerDelegate.currentConfiguration;
    final top = matches.lastOrNull;
    final topLocation = top is ImperativeRouteMatch
        ? top.matches.uri.toString()
        : matches.uri.toString();
    if (topLocation == Uri.parse(location).toString()) return;
    router.push(location);
  }
}
