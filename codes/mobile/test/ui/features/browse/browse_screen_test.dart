import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:tessera/data/models/poll_info.dart';
import 'package:tessera/data/models/poll_snapshot.dart';
import 'package:tessera/data/models/poll_summary.dart';
import 'package:tessera/data/repositories/poll_repository.dart';
import 'package:tessera/data/services/chain_writer.dart';
import 'package:tessera/data/services/relay_client.dart';
import 'package:tessera/ui/core/format.dart';
import 'package:tessera/ui/features/browse/browse_screen.dart';
import 'package:tessera/ui/features/browse/browse_view_model.dart';

class FakePollRepository implements PollRepository {
  final List<PollInfo>? polls;
  final Map<String, PollSummary>? summaries;
  final Object? error;
  FakePollRepository({this.polls, this.summaries, this.error});

  @override
  Future<List<PollInfo>> fetchPolls() async {
    if (error != null) throw error!;
    return polls ?? const [];
  }

  @override
  Future<PollSummary> fetchSummary(String address) async {
    final s = summaries?[address];
    if (s == null) {
      throw StateError('no summary for $address'); // → best-effort skip
    }
    return s;
  }

  @override
  Future<PollSnapshot> fetchPoll(String address) => throw UnimplementedError();

  @override
  Future<List<String>> fetchGroup(String address) => throw UnimplementedError();
}

PollInfo _poll(String addr, String title) => PollInfo(
  pollAddress: addr,
  moduleType: 'anon-vote',
  title: title,
  description: 'A short description',
  creator: '0x0000000000000000000000000000000000000000',
  createdAt: BigInt.zero,
);

PollSummary _sum(int state, int votes) =>
    PollSummary(state: state, totalVotes: BigInt.from(votes));

const _a = '0x1111111111111111111111111111111111111111'; // Voting
const _b = '0x2222222222222222222222222222222222222222'; // Registration
const _c = '0x3333333333333333333333333333333333333333'; // Ended

Widget _wrap(PollRepository repo, {RelayClient? relay}) => MaterialApp(
  home: MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => BrowseViewModel(repo)),
      // Default 503 → no relayer address → cards show the creator address.
      // Tests that assert "SPONSORED" pass a relayer-returning mock.
      Provider<RelayClient>(
        create: (_) =>
            relay ??
            RelayClient(
              baseUrl: 'http://relayer.test',
              client: MockClient((_) async => http.Response('{}', 503)),
            ),
      ),
      Provider<ChainWriter>(
        create: (_) =>
            ChainWriter(rpcUrl: 'http://127.0.0.1:1', chainId: 31337),
      ),
    ],
    child: const BrowseScreen(),
  ),
);

// Three polls, one per phase, with distinct vote tallies.
FakePollRepository _threePhaseRepo() => FakePollRepository(
  polls: [
    _poll(_a, 'Voting Poll'),
    _poll(_b, 'Registration Poll'),
    _poll(_c, 'Ended Poll'),
  ],
  summaries: {
    _a: _sum(1, 5), // Voting, 5 votes
    _b: _sum(0, 0), // Registration
    _c: _sum(2, 9), // Ended, 9 votes
  },
);

Future<void> _tapPill(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'default ACTIVE filter shows only Voting polls, with real chip + vote count',
    (tester) async {
      await tester.pumpWidget(_wrap(_threePhaseRepo()));
      await tester.pumpAndSettle();

      // Only the Voting-phase poll is visible under the default ACTIVE filter.
      expect(find.text('Voting Poll'), findsOneWidget);
      expect(find.text('Registration Poll'), findsNothing);
      expect(find.text('Ended Poll'), findsNothing);

      // 'VOTING' is unique to the active state chip (no filter pill uses it).
      expect(find.text('VOTING'), findsOneWidget);
      // Real vote tally on the card.
      expect(find.text('5'), findsOneWidget);

      // Hero subtitle counts every poll by real phase.
      expect(
        find.textContaining(
          '3 total · 1 active · 1 upcoming · 1 ended',
          findRichText: true,
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('ALL filter reveals every phase with the correct chip + tally', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(_threePhaseRepo()));
    await tester.pumpAndSettle();
    await _tapPill(tester, 'ALL'); // status filter → all

    expect(find.text('Voting Poll'), findsOneWidget);
    expect(find.text('Registration Poll'), findsOneWidget);
    expect(find.text('Ended Poll'), findsOneWidget);

    // 'VOTING' chip is unique; UPCOMING/ENDED each appear once as a filter pill
    // plus once as a card chip.
    expect(find.text('VOTING'), findsOneWidget);
    expect(find.text('UPCOMING'), findsNWidgets(2));
    expect(find.text('ENDED'), findsNWidgets(2));

    expect(find.text('5'), findsOneWidget); // voting tally
    expect(find.text('9'), findsOneWidget); // ended tally
  });

  testWidgets('UPCOMING filter shows only the Registration-phase poll', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(_threePhaseRepo()));
    await tester.pumpAndSettle();
    await _tapPill(tester, 'UPCOMING');

    expect(find.text('Registration Poll'), findsOneWidget);
    expect(find.text('Voting Poll'), findsNothing);
    expect(find.text('Ended Poll'), findsNothing);
  });

  testWidgets('falls back to an active look when summaries fail to load', (
    tester,
  ) async {
    // No summaries provided → every fetchSummary throws → best-effort skips
    // them → cards render with the neutral (active) fallback, list still shows.
    await tester.pumpWidget(
      _wrap(
        FakePollRepository(
          polls: [_poll(_a, 'Budget 2026'), _poll(_b, 'Board Seat')],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('POLLS'), findsOneWidget);
    expect(find.text('Budget 2026'), findsOneWidget);
    expect(find.text('Board Seat'), findsOneWidget);
    expect(find.text('VOTING'), findsNWidgets(2)); // fallback chips
    expect(find.text('—'), findsNWidgets(2)); // unknown vote tally
  });

  testWidgets('renders empty state when no polls match', (tester) async {
    await tester.pumpWidget(_wrap(FakePollRepository(polls: const [])));
    await tester.pumpAndSettle();
    expect(find.text('No polls match this filter'), findsOneWidget);
  });

  testWidgets('renders error state with retry', (tester) async {
    await tester.pumpWidget(
      _wrap(FakePollRepository(error: Exception('boom'))),
    );
    await tester.pumpAndSettle();
    expect(find.text("COULDN'T LOAD POLLS"), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'RETRY'), findsOneWidget);
  });

  testWidgets('a relayer-owned poll card reads SPONSORED, not a raw hex', (
    tester,
  ) async {
    const relayer = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266';
    final repo = FakePollRepository(
      polls: [
        PollInfo(
          pollAddress: _a,
          moduleType: 'anon-vote',
          title: 'Community Vote',
          description: 'd',
          creator: relayer, // wallet-free: the relayer owns it
          createdAt: BigInt.zero,
        ),
      ],
      summaries: {_a: _sum(1, 1)},
    );
    final relay = RelayClient(
      baseUrl: 'http://relayer.test',
      client: MockClient(
        (_) async =>
            http.Response('{"relayer":"$relayer","registry":"0xCf7Ed3"}', 200),
      ),
    );
    await tester.pumpWidget(_wrap(repo, relay: relay));
    await tester.pumpAndSettle();
    expect(find.textContaining('SPONSORED'), findsOneWidget);
    expect(find.textContaining(shortAddr(relayer).toUpperCase()), findsNothing);
  });
}
