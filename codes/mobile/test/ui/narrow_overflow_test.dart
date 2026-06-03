import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:tessera/data/models/poll_info.dart';
import 'package:tessera/data/models/poll_snapshot.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tessera/data/models/blind_snapshot.dart';
import 'package:tessera/data/models/poll_summary.dart';
import 'package:tessera/data/models/relay_proof.dart';
import 'package:tessera/data/repositories/blind_repository.dart';
import 'package:tessera/data/repositories/poll_repository.dart';
import 'package:tessera/data/repositories/quadratic_repository.dart';
import 'package:tessera/data/services/blind_commit_store.dart';
import 'package:tessera/data/services/chain_reader.dart';
import 'package:tessera/data/services/chain_writer.dart';
import 'package:tessera/data/services/proof_service.dart';
import 'package:tessera/data/services/relay_client.dart';
import 'package:tessera/data/services/wallet_service.dart';
import 'package:tessera/ui/core/app_shell.dart';
import 'package:tessera/ui/features/blind_poll/blind_poll_screen.dart';
import 'package:tessera/ui/features/blind_poll/blind_poll_view_model.dart';
import 'package:tessera/ui/features/browse/browse_screen.dart';
import 'package:tessera/ui/features/browse/browse_view_model.dart';
import 'package:tessera/ui/features/poll_detail/poll_detail_screen.dart';
import 'package:tessera/ui/features/poll_detail/poll_detail_view_model.dart';
import 'package:tessera/ui/features/quadratic_poll/quadratic_poll_screen.dart';
import 'package:tessera/ui/features/quadratic_poll/quadratic_vote_view_model.dart';
import 'package:tessera/ui/features/settings/settings_screen.dart';
import 'package:tessera/ui/features/wallet/wallet_button.dart';

/// Narrow-width overflow regression tests. These pump the previously-overflowing
/// screens/widgets at a Galaxy-A25-class surface (340x720, the tightest width the
/// app must support) and assert no RenderFlex overflow is thrown. A RenderFlex
/// overflow is a thrown exception in widget tests, so `tester.takeException()`
/// being null is the proof the layout fits.
///
/// IMPORTANT: these MUST use a real shrunken surface via `setSurfaceSize` — a
/// bare `MediaQuery` override does NOT change the constraints a full-screen
/// `Scaffold` lays out against, so the test would pass even on the broken code.
/// Each of these was confirmed to THROW on the pre-fix code at this surface.

const _narrow = Size(340, 720);

/// Wrap a body in a minimal MaterialApp, no extra chrome, dark surface.
Widget _app(Widget child) => MaterialApp(home: child);

// ── Browse fakes (mirrors browse_screen_test.dart) ───────────────────────────

class _FakePollRepo implements PollRepository {
  final List<PollInfo> polls;
  final Map<String, PollSummary> summaries;
  _FakePollRepo(this.polls, this.summaries);

  @override
  Future<List<PollInfo>> fetchPolls() async => polls;

  @override
  Future<PollSummary> fetchSummary(String address) async {
    final s = summaries[address];
    if (s == null) throw StateError('no summary');
    return s;
  }

  @override
  Future<PollSnapshot> fetchPoll(String address) => throw UnimplementedError();

  @override
  Future<List<String>> fetchGroup(String address) => throw UnimplementedError();
}

PollInfo _poll(String addr, String title, String creator) => PollInfo(
      pollAddress: addr,
      moduleType: 'anon-vote',
      title: title,
      description: 'desc',
      creator: creator,
      createdAt: BigInt.zero,
    );

// ── Poll-detail / quadratic fakes (the shared _Header pattern lives in every
// poll screen; quadratic carries the longest badge 'ZK · QUADRATIC'). ─────────

class _DetailRepo implements PollRepository {
  final PollSnapshot snap;
  _DetailRepo(this.snap);
  @override
  Future<PollSnapshot> fetchPoll(String address) async => snap;
  @override
  Future<List<PollInfo>> fetchPolls() => throw UnimplementedError();
  @override
  Future<List<String>> fetchGroup(String address) => throw UnimplementedError();
  @override
  Future<PollSummary> fetchSummary(String address) => throw UnimplementedError();
}

class _FakeQuadRepo implements QuadraticRepository {
  final PollSnapshot snap;
  _FakeQuadRepo(this.snap);
  @override
  Future<List<String>> fetchGroup(String address) async => const [];
  @override
  Future<PollSnapshot> fetchPoll(String address) async => snap;
}

class _FakeBlindRepo extends BlindRepository {
  final BlindSnapshot snap;
  _FakeBlindRepo(this.snap)
      : super(
          reader: ChainReader(
            rpcUrl: 'http://127.0.0.1:1',
            izkPollAbiJson: '[]',
            registryAbiJson: '[]',
            anonVotingAbiJson: '[]',
            registryAddress: '0x0000000000000000000000000000000000000000',
          ),
          writer: ChainWriter(rpcUrl: 'http://127.0.0.1:1', chainId: 31337),
          commits: InMemoryBlindCommitStore(),
          blindAbiJson: '[]',
        );
  @override
  bool get canWrite => true;
  @override
  String? get signer => '0x1111111111111111111111111111111111111111';
  @override
  Future<BlindSnapshot> fetch(String poll) async => snap;
  @override
  Future<bool> hasSavedCommit(String poll) async => false;
}

BlindSnapshot _blindSnap() => BlindSnapshot(
      address: _detailAddr,
      state: 1,
      options: const ['Yes', 'No', 'Abstain'],
      results: [BigInt.zero, BigInt.one, BigInt.zero],
      participantCount: BigInt.from(2),
      owner: '0x1111111111111111111111111111111111111111',
      revealDeadline: BigInt.zero,
      finalized: false,
      registered: false,
      committed: false,
      revealed: false,
    );

const _detailAddr = '0xd8058efe0198ae9dD7D563e1b4938Dcbc86A1F81';

PollSnapshot _snap() => PollSnapshot(
      address: _detailAddr,
      state: 1, // Voting
      options: const ['Yes', 'No', 'Abstain'],
      results: [BigInt.from(3), BigInt.from(1), BigInt.zero],
      owner: '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266',
      participantCount: BigInt.from(4),
    );

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Tessera',
      packageName: 'tessera',
      version: '0.2.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  Future<void> useNarrowSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(_narrow);
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  testWidgets('WalletButton _Hint fits a tight Row at 340px', (tester) async {
    await useNarrowSurface(tester);
    // The worst case: the hint pill shares one Row with an Expanded sibling
    // that eats the rest of the width, leaving the pill nothing to grow into.
    await tester.pumpWidget(_app(
      ChangeNotifierProvider(
        create: (_) =>
            WalletService(registryAbiJson: '[]', anonAbiJson: '[]'),
        child: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(8),
            // A real tight Row: a long leading label takes most of the width and
            // the pill gets a bounded `Flexible` slot (how the drawer/create
            // banner place it). The pill must shrink to fit, not overflow.
            child: Row(
              children: [
                Expanded(
                    flex: 3,
                    child: Text('A long leading label beside the pill')),
                SizedBox(width: 8),
                Flexible(flex: 2, child: WalletButton()),
              ],
            ),
          ),
        ),
      ),
    ));
    await tester.pump(); // let the post-frame ensureInit run
    expect(tester.takeException(), isNull);
    // On a non-web test host (TargetPlatform.android default) the wallet is
    // "supported" but not "configured" (empty WC_PROJECT_ID) → the hint shows.
    expect(find.byType(WalletButton), findsOneWidget);
  });

  testWidgets('App drawer (with WalletButton) fits at 340px', (tester) async {
    await useNarrowSurface(tester);
    // Drive the AppShell so the real Drawer + WalletButton slot render.
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => AppShell(shell: shell),
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/',
                  builder: (_, _) =>
                      const Scaffold(body: Center(child: Text('home')))),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/verify',
                  builder: (_, _) => const SizedBox.shrink()),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/create',
                  builder: (_, _) => const SizedBox.shrink()),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/identity',
                  builder: (_, _) => const SizedBox.shrink()),
            ]),
          ],
        ),
        GoRoute(path: '/settings', builder: (_, _) => const SizedBox.shrink()),
      ],
    );
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => WalletService(registryAbiJson: '[]', anonAbiJson: '[]'),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    // Open the drawer via the AppBar leading menu button.
    final ScaffoldState scaffold = tester.firstState(find.byType(Scaffold));
    scaffold.openDrawer();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.byType(WalletButton), findsOneWidget);
    expect(find.text('WALLET'), findsOneWidget);
  });

  testWidgets('Settings screen fits at 340px with a long dev-signer string',
      (tester) async {
    await useNarrowSurface(tester);
    await tester.pumpWidget(_app(
      Provider<ChainWriter>(
        // A configured dev signer makes the "Signer" row carry the long
        // 'dev signer · 0x…' value — the widest value in the screen.
        create: (_) => ChainWriter(
          rpcUrl: 'http://some-fairly-long-rpc-host.example.com:8545',
          chainId: 31337,
          privateKey:
              '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d',
        ),
        child: const SettingsScreen(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('SETTINGS'), findsOneWidget);
  });

  testWidgets('Settings screen fits at 320px with an enlarged font scale (1.3)',
      (tester) async {
    // This is the condition the user actually hit: a narrow phone with the
    // system font scaled up. The fixed-width row LABELS used to push the row
    // past the edge here (33px at this width/scale on the pre-fix code).
    await tester.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 900),
          textScaler: TextScaler.linear(1.3),
        ),
        child: Provider<ChainWriter>(
          create: (_) => ChainWriter(
            rpcUrl: 'http://eth-sepolia.g.alchemy.com:8545',
            chainId: 11155111,
            privateKey:
                '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d',
          ),
          child: const SettingsScreen(),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('SETTINGS'), findsOneWidget);
  });

  testWidgets('Browse _HeroStat / poll cards fit at 340px', (tester) async {
    await useNarrowSurface(tester);
    final repo = _FakePollRepo(
      [
        _poll('0x1111111111111111111111111111111111111111', 'Voting Poll',
            '0xabcdef0000000000000000000000000000000000'),
      ],
      {
        '0x1111111111111111111111111111111111111111':
            PollSummary(state: 1, totalVotes: BigInt.from(123456)),
      },
    );
    await tester.pumpWidget(_app(
      ChangeNotifierProvider(
        create: (_) => BrowseViewModel(repo),
        child: const BrowseScreen(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // The hero stat renders the real vote tally.
    expect(find.text('VOTES'), findsOneWidget);
    expect(find.text('123456'), findsOneWidget);
    // The confusing 'T-MINUS —' jargon placeholder is gone (the card already
    // shows the poll phase via the _StateChip, e.g. 'VOTING').
    expect(find.textContaining('T-MINUS'), findsNothing);
    expect(find.text('VOTING'), findsOneWidget);
  });

  testWidgets('Poll-detail header (back + ZK · ANON badge + addr) fits at 340px',
      (tester) async {
    await useNarrowSurface(tester);
    await tester.pumpWidget(_app(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
              create: (_) => PollDetailViewModel(_DetailRepo(_snap()), _detailAddr)),
          Provider<ChainWriter>(
              create: (_) =>
                  ChainWriter(rpcUrl: 'http://127.0.0.1:1', chainId: 31337)),
        ],
        child: const PollDetailScreen(address: _detailAddr),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('ZK · ANON'), findsOneWidget);
  });

  testWidgets(
      'Quadratic-poll header (longest badge ZK · QUADRATIC) fits at 340px',
      (tester) async {
    await useNarrowSurface(tester);
    final relay = MockClient((req) async => http.Response('{}', 200));
    await tester.pumpWidget(_app(
      ChangeNotifierProvider(
        create: (_) => QuadraticVoteViewModel(
          repository: _FakeQuadRepo(_snap()),
          proofService: const FakeProofService(RelayProof(
            merkleTreeDepth: 1,
            merkleTreeRoot: '1',
            nullifier: '2',
            message: '134',
            scope: '3',
            points: ['1', '2', '3', '4', '5', '6', '7', '8'],
          )),
          relayClient: RelayClient(baseUrl: 'http://relayer.test', client: relay),
          pollAddress: _detailAddr,
        ),
        child: const QuadraticPollScreen(address: _detailAddr),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('ZK · QUADRATIC'), findsOneWidget);
  });

  testWidgets(
      'Blind-poll header (longest badge BLIND · COMMIT-REVEAL) fits at 340px',
      (tester) async {
    await useNarrowSurface(tester);
    await tester.pumpWidget(_app(
      ChangeNotifierProvider(
        create: (_) => BlindPollViewModel(_FakeBlindRepo(_blindSnap()), _detailAddr),
        child: const BlindPollScreen(address: _detailAddr),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('BLIND · COMMIT-REVEAL'), findsOneWidget);
  });
}
