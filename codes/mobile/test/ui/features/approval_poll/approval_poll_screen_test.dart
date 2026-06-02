import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:tessera/data/models/poll_snapshot.dart';
import 'package:tessera/data/models/relay_proof.dart';
import 'package:tessera/data/repositories/approval_repository.dart';
import 'package:tessera/data/services/identity_store.dart';
import 'package:tessera/data/services/proof_service.dart';
import 'package:tessera/data/services/relay_client.dart';
import 'package:tessera/ui/features/approval_poll/approval_poll_screen.dart';
import 'package:tessera/ui/features/approval_poll/approval_vote_view_model.dart';

class FakeApprovalRepo implements ApprovalRepository {
  final PollSnapshot? snap;
  final Object? error;
  FakeApprovalRepo({this.snap, this.error});
  @override
  Future<PollSnapshot> fetchPoll(String address) async {
    if (error != null) throw error!;
    return snap!;
  }

  @override
  Future<List<String>> fetchGroup(String address) async => const [];
}

/// In-memory IdentityStore so the form's prefill doesn't hit a platform channel.
class _MemIdentityStore implements IdentityStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String seed) async {}
  @override
  Future<void> delete() async {}
}

const addr = '0xd8058efe0198ae9dD7D563e1b4938Dcbc86A1F81';

const _proof = RelayProof(
  merkleTreeDepth: 1,
  merkleTreeRoot: '1',
  nullifier: '2',
  message: '1',
  scope: '3',
  points: ['1', '2', '3', '4', '5', '6', '7', '8'],
);

Widget _wrap(ApprovalRepository repo) => MaterialApp(
  home: MultiProvider(
    providers: [
      Provider<IdentityStore>(create: (_) => _MemIdentityStore()),
      ChangeNotifierProvider(
        create: (_) => ApprovalVoteViewModel(
          repository: repo,
          proofService: const FakeProofService(_proof),
          relayClient: RelayClient(
            baseUrl: 'http://relayer.test',
            client: MockClient((r) async => http.Response('{}', 200)),
          ),
          pollAddress: addr,
        ),
      ),
    ],
    child: const ApprovalPollScreen(address: addr),
  ),
);

void main() {
  testWidgets(
    'renders approval chrome: ZK · APPROVAL badge + APPROVALS results',
    (tester) async {
      final snap = PollSnapshot(
        address: addr,
        state: 1, // Voting
        options: const ['Pizza', 'Sushi', 'Tacos'],
        // Approvals can sum past the voter count (4): 3+2+1 = 6 approvals, 4 voters.
        results: [BigInt.from(3), BigInt.from(2), BigInt.one],
        owner: '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266',
        participantCount: BigInt.from(4),
      );
      await tester.pumpWidget(_wrap(FakeApprovalRepo(snap: snap)));
      await tester.pumpAndSettle();

      // Approval-specific chrome (distinct from the anon screen).
      expect(find.text('ZK · APPROVAL'), findsOneWidget);
      expect(find.text('APPROVALS'), findsOneWidget);
      expect(find.text('4 VOTERS'), findsOneWidget);
      // Options render.
      expect(find.text('Pizza'), findsOneWidget);
      expect(find.text('Sushi'), findsOneWidget);
      expect(find.text('Tacos'), findsOneWidget);
      // % denominator is voters (4), so 3 approvals of 4 voters = 75.0%.
      expect(find.text('75.0%'), findsOneWidget);
    },
  );

  testWidgets('shows error state on read failure', (tester) async {
    await tester.pumpWidget(
      _wrap(FakeApprovalRepo(error: Exception('rpc down'))),
    );
    await tester.pumpAndSettle();
    expect(find.text("COULDN'T LOAD THIS POLL"), findsOneWidget);
  });
}
