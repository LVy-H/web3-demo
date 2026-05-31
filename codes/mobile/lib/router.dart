import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'data/repositories/poll_repository.dart';
import 'ui/features/browse/browse_screen.dart';
import 'ui/features/browse/browse_view_model.dart';
import 'ui/features/poll_detail/poll_detail_screen.dart';

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
          path: '/poll/:address',
          builder: (context, state) =>
              PollDetailScreen(address: state.pathParameters['address']!),
        ),
      ],
    );
