import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'data/repositories/blind_repository.dart';
import 'data/repositories/live_host_repository.dart';
import 'data/repositories/poll_repository.dart';
import 'data/repositories/verify_repository.dart';
import 'data/services/chain_reader.dart';
import 'data/services/identity_store.dart';
import 'data/services/proof_service.dart';
import 'data/services/relay_client.dart';
import 'ui/core/app_shell.dart';
import 'ui/features/blind_poll/blind_poll_screen.dart';
import 'ui/features/blind_poll/blind_poll_view_model.dart';
import 'ui/features/live_host/live_host_screen.dart';
import 'ui/features/live_host/live_host_view_model.dart';
import 'ui/features/live_vote/live_vote_screen.dart';
import 'ui/features/live_vote/live_vote_view_model.dart';
import 'ui/features/settings/settings_screen.dart';
import 'ui/features/browse/browse_screen.dart';
import 'ui/features/browse/browse_view_model.dart';
import 'ui/features/create/create_screen.dart';
import 'ui/features/identity/identity_screen.dart';
import 'ui/features/identity/identity_view_model.dart';
import 'ui/features/poll_detail/poll_detail_screen.dart';
import 'ui/features/poll_detail/poll_detail_view_model.dart';
import 'ui/features/poll_detail/vote_view_model.dart';
import 'ui/features/verify/verify_screen.dart';
import 'ui/features/verify/verify_view_model.dart';

/// App routes (go_router). A StatefulShellRoute gives the mobile app a
/// persistent bottom NavigationBar (Polls / Verify / Create) + Drawer via
/// [AppShell]; each tab keeps its own navigation stack. Poll detail is nested
/// under the Polls branch so the nav bar stays visible while drilling in.
GoRouter buildRouter() => GoRouter(
      initialLocation: '/',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              AppShell(shell: navigationShell),
          branches: [
            // ── Branch 0: Polls (+ poll detail) ──
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/',
                  builder: (context, state) => ChangeNotifierProvider(
                    create: (ctx) => BrowseViewModel(ctx.read<PollRepository>()),
                    child: const BrowseScreen(),
                  ),
                  routes: [
                    GoRoute(
                      path: 'poll/:address',
                      builder: (context, state) {
                        final address = state.pathParameters['address']!;
                        // Dispatch by module type (passed by Browse). Blind
                        // (commit-reveal) polls get their own detail surface.
                        if (state.uri.queryParameters['module'] ==
                            'blind-vote') {
                          return ChangeNotifierProvider(
                            create: (ctx) => BlindPollViewModel(
                                ctx.read<BlindRepository>(), address),
                            child: BlindPollScreen(address: address),
                          );
                        }
                        return MultiProvider(
                          providers: [
                            ChangeNotifierProvider(
                              create: (ctx) => PollDetailViewModel(
                                  ctx.read<PollRepository>(), address),
                            ),
                            ChangeNotifierProvider(
                              create: (ctx) => VoteViewModel(
                                repository: ctx.read<PollRepository>(),
                                proofService: ctx.read<ProofService>(),
                                relayClient: ctx.read<RelayClient>(),
                                pollAddress: address,
                              ),
                            ),
                          ],
                          child: PollDetailScreen(address: address),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
            // ── Branch 1: Verify ──
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/verify',
                  builder: (context, state) => ChangeNotifierProvider(
                    create: (ctx) =>
                        VerifyViewModel(ctx.read<VerifyRepository>()),
                    child: VerifyScreen(
                      initialPoll: state.uri.queryParameters['poll'],
                      initialNullifier: state.uri.queryParameters['nullifier'],
                    ),
                  ),
                ),
              ],
            ),
            // ── Branch 2: Create ──
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/create',
                  builder: (context, state) => const CreateScreen(),
                ),
              ],
            ),
            // ── Branch 3: Identity ──
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/identity',
                  builder: (context, state) => ChangeNotifierProvider(
                    create: (ctx) =>
                        IdentityViewModel(ctx.read<IdentityStore>())..load(),
                    child: const IdentityScreen(),
                  ),
                ),
              ],
            ),
          ],
        ),
        // Full-screen organizer dashboard (outside the bottom-nav shell).
        GoRoute(
          path: '/live/:address/host',
          builder: (context, state) {
            final address = state.pathParameters['address']!;
            return ChangeNotifierProvider(
              create: (ctx) =>
                  LiveHostViewModel(ctx.read<LiveHostRepository>(), address),
              child: LiveHostScreen(address: address),
            );
          },
        ),
        // Full-screen live VOTER (deep-link target of the host QR).
        GoRoute(
          path: '/live/:address/vote',
          builder: (context, state) {
            final address = state.pathParameters['address']!;
            return ChangeNotifierProvider(
              create: (ctx) => LiveVoteViewModel(
                proof: ctx.read<ProofService>(),
                relay: ctx.read<RelayClient>(),
                reader: ctx.read<ChainReader>(),
                pollAddress: address,
                initialTicket: state.uri.queryParameters['t'],
              ),
              child: LiveVoteScreen(address: address),
            );
          },
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
      ],
    );
