import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'data/repositories/poll_repository.dart';
import 'data/repositories/verify_repository.dart';
import 'data/services/proof_service.dart';
import 'data/services/relay_client.dart';
import 'ui/features/browse/browse_screen.dart';
import 'ui/features/browse/browse_view_model.dart';
import 'ui/features/poll_detail/poll_detail_screen.dart';
import 'ui/features/poll_detail/poll_detail_view_model.dart';
import 'ui/features/poll_detail/vote_view_model.dart';
import 'ui/features/verify/verify_screen.dart';
import 'ui/features/verify/verify_view_model.dart';

/// App routes (go_router). Each screen's ViewModel is created at the route and
/// fed the [PollRepository] from the app-level provider.
GoRouter buildRouter() => GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => ChangeNotifierProvider(
            create: (ctx) => BrowseViewModel(ctx.read<PollRepository>()),
            child: const BrowseScreen(),
          ),
        ),
        GoRoute(
          path: '/verify',
          builder: (context, state) => ChangeNotifierProvider(
            create: (ctx) => VerifyViewModel(ctx.read<VerifyRepository>()),
            child: VerifyScreen(
              initialPoll: state.uri.queryParameters['poll'],
              initialNullifier: state.uri.queryParameters['nullifier'],
            ),
          ),
        ),
        GoRoute(
          path: '/poll/:address',
          builder: (context, state) {
            final address = state.pathParameters['address']!;
            return MultiProvider(
              providers: [
                ChangeNotifierProvider(
                  create: (ctx) =>
                      PollDetailViewModel(ctx.read<PollRepository>(), address),
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
    );
