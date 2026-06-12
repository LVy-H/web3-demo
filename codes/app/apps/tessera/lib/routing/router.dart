/// The route table for the three-space IA (R2f deliverable 1).
///
/// Guards live in guards.dart as pure functions; this wiring stays thin:
/// `redirect` delegates to [redirectForLocation], re-evaluated whenever
/// [AppState] notifies (refreshListenable). Placeholder screens live one per
/// file under spaces/ so R3 agents replace files without touching this
/// router.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../shell/app_shell.dart';
import '../spaces/blocked_screen.dart';
import '../spaces/join_resolve_screen.dart';
import '../spaces/join_screen.dart';
import '../spaces/live_host_screen.dart';
import '../spaces/live_vote_screen.dart';
import '../spaces/organize_create_screen.dart';
import '../spaces/organize_space_screen.dart';
import '../spaces/poll_screen.dart';
import '../spaces/route_error_screen.dart';
import '../spaces/vote_space_screen.dart';
import '../spaces/you_space_screen.dart';
import '../spaces/you_verify_screen.dart';
import '../state/app_state.dart';
import 'guards.dart';
import 'poll_module_resolver.dart';

GoRouter buildTesseraRouter({
  required AppState appState,
  required PollModuleResolver pollModuleResolver,
  String initialLocation = '/vote',
}) {
  final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: initialLocation,
    refreshListenable: appState,
    redirect: (context, state) => redirectForLocation(
      uri: state.uri,
      capabilities: appState.capabilities,
    ),
    // Catch-all error route — the legacy router had none (a bad link crashed
    // into the framework error widget).
    errorBuilder: (context, state) => RouteErrorScreen(
      messageKey: kRouteNotFoundKey,
      detail: state.uri.toString(),
    ),
    routes: [
      // ── Three spaces (persistent bottom nav + JOIN action) ──
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShellScaffold(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/vote',
                builder: (context, state) => const VoteSpaceScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/organize',
                builder: (context, state) => const OrganizeSpaceScreen(),
                routes: [
                  GoRoute(
                    path: 'create',
                    builder: (context, state) => const OrganizeCreateScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/you',
                builder: (context, state) => const YouSpaceScreen(),
                routes: [
                  GoRoute(
                    path: 'verify',
                    // Verify is a focused TASK page, pushed from poll
                    // receipts and the YOU space alike. It must render on
                    // the ROOT navigator: pushing a shell-branch page while
                    // a root-level page (/poll/:address) is topmost makes
                    // go_router clone a SECOND shell whose page shares the
                    // first shell's ValueKey → Navigator's duplicate
                    // page-key assertion (the red-screen crash).
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => YouVerifyScreen(
                      poll: state.uri.queryParameters['poll'],
                      nullifier: state.uri.queryParameters['nullifier'],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),

      // ── Single poll route: module resolved ON-CHAIN, no ?module= dispatch ──
      GoRoute(
        path: '/poll/:address',
        builder: (context, state) => PollScreen(
          address: state.pathParameters['address']!,
          resolver: pollModuleResolver,
        ),
      ),

      // ── Live session, full-screen (outside the shell) ──
      GoRoute(
        path: '/live/:address/host',
        builder: (context, state) =>
            LiveHostScreen(address: state.pathParameters['address']!),
      ),
      GoRoute(
        path: '/live/:address/vote',
        builder: (context, state) => LiveVoteScreen(
          address: state.pathParameters['address']!,
          ticket: state.uri.queryParameters['t'],
        ),
      ),

      // ── JOIN (modal-style) ──
      GoRoute(
        path: '/join',
        // state.pageKey gives every match its own page identity (stable
        // ValueKey('/join') for a go, a unique key per push). A keyless
        // `const` page here would canonicalize: two pushes would put the
        // SAME instance in the page stack twice.
        pageBuilder: (context, state) => MaterialPage(
          key: state.pageKey,
          fullscreenDialog: true,
          child: const JoinScreen(),
        ),
        routes: [
          GoRoute(
            path: 'resolve',
            builder: (context, state) =>
                JoinResolveScreen(code: state.uri.queryParameters['code']),
          ),
        ],
      ),

      // ── Guard exit + typed error route (never re-guarded) ──
      GoRoute(
        path: '/blocked',
        builder: (context, state) => BlockedScreen(
          reasonKey: state.uri.queryParameters['reason'] ?? kCannotProveReason,
          from: state.uri.queryParameters['from'],
        ),
      ),
      GoRoute(
        path: '/error',
        builder: (context, state) => RouteErrorScreen(
          messageKey:
              state.uri.queryParameters['messageKey'] ?? kRouteNotFoundKey,
          detail: state.uri.queryParameters['detail'],
        ),
      ),
    ],
  );
}
