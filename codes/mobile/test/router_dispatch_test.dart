import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:tessera/data/models/poll_info.dart';
import 'package:tessera/data/models/poll_snapshot.dart';
import 'package:tessera/data/models/poll_summary.dart';
import 'package:tessera/data/models/relay_proof.dart';
import 'package:tessera/data/repositories/approval_repository.dart';
import 'package:tessera/data/repositories/poll_repository.dart';
import 'package:tessera/data/services/chain_writer.dart';
import 'package:tessera/data/services/proof_service.dart';
import 'package:tessera/data/services/relay_client.dart';
import 'package:tessera/router.dart';

// ── Fakes for the subtree `buildPollDetail` touches ──────────────────────────

PollSnapshot _snap(String addr) => PollSnapshot(
  address: addr,
  state: 1, // Voting — so both screens render their results + ballot area
  options: const ['A', 'B', 'C'],
  results: [BigInt.from(2), BigInt.one, BigInt.zero],
  owner: '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266',
  participantCount: BigInt.from(3),
);

class _FakePollRepo implements PollRepository {
  @override
  Future<PollSnapshot> fetchPoll(String address) async => _snap(address);
  @override
  Future<List<String>> fetchGroup(String address) async => const [];
  @override
  Future<List<PollInfo>> fetchPolls() => throw UnimplementedError();
  @override
  Future<PollSummary> fetchSummary(String address) =>
      throw UnimplementedError();
}

class _FakeApprovalRepo implements ApprovalRepository {
  @override
  Future<PollSnapshot> fetchPoll(String address) async => _snap(address);
  @override
  Future<List<String>> fetchGroup(String address) async => const [];
}

const _addr = '0x1111111111111111111111111111111111111111';

const _proof = RelayProof(
  merkleTreeDepth: 1,
  merkleTreeRoot: '1',
  nullifier: '2',
  message: '1',
  scope: '3',
  points: ['1', '2', '3', '4', '5', '6', '7', '8'],
);

/// A minimal router whose ONLY route is the REAL `buildPollDetail` builder, so
/// the test exercises the actual `?module=` dispatch (not a hand-pumped screen).
/// Wrapped in only the providers that the poll-detail subtree reads.
Widget _app(String initialLocation) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [GoRoute(path: '/poll/:address', builder: buildPollDetail)],
  );
  return MultiProvider(
    providers: [
      Provider<PollRepository>(create: (_) => _FakePollRepo()),
      Provider<ApprovalRepository>(create: (_) => _FakeApprovalRepo()),
      Provider<ProofService>(create: (_) => const FakeProofService(_proof)),
      Provider<RelayClient>(
        create: (_) => RelayClient(
          baseUrl: 'http://relayer.test',
          client: MockClient((r) async => http.Response('{}', 200)),
        ),
      ),
      // canSign=false → the anon screen hides its organize-live entry. (This
      // test only exercises the anon/approval branches, so BlindRepository is
      // intentionally not provided — a blind-vote route would need it.)
      Provider<ChainWriter>(
        create: (_) =>
            ChainWriter(rpcUrl: 'http://127.0.0.1:1', chainId: 31337),
      ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets(
    '?module=approval-vote dispatches to the APPROVAL screen, not the anon one',
    (tester) async {
      await tester.pumpWidget(_app('/poll/$_addr?module=approval-vote'));
      await tester.pumpAndSettle();

      // Approval chrome present…
      expect(find.text('ZK · APPROVAL'), findsOneWidget);
      expect(find.text('APPROVALS'), findsOneWidget);
      // …and the anon screen's chrome is ABSENT (the bug this guards: falling
      // through to the anon screen would cast a single-index vote, not a bitmask).
      expect(find.text('ZK · ANON'), findsNothing);
      expect(find.text('LIVE RESULTS'), findsNothing);
    },
  );

  testWidgets('?module=anon-vote still dispatches to the ANON screen', (
    tester,
  ) async {
    await tester.pumpWidget(_app('/poll/$_addr?module=anon-vote'));
    await tester.pumpAndSettle();

    expect(find.text('ZK · ANON'), findsOneWidget);
    expect(find.text('LIVE RESULTS'), findsOneWidget);
    expect(find.text('ZK · APPROVAL'), findsNothing);
    expect(find.text('APPROVALS'), findsNothing);
  });

  testWidgets('no module param falls back to the ANON screen', (tester) async {
    await tester.pumpWidget(_app('/poll/$_addr'));
    await tester.pumpAndSettle();

    expect(find.text('ZK · ANON'), findsOneWidget);
    expect(find.text('ZK · APPROVAL'), findsNothing);
  });
}
