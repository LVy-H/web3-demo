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
import 'package:tessera/ui/features/poll_detail/poll_detail_screen.dart';
import 'package:tessera/ui/features/poll_detail/poll_detail_view_model.dart';

class FakeRepo implements PollRepository {
  final PollSnapshot? snap;
  final Object? error;
  FakeRepo({this.snap, this.error});

  @override
  Future<List<PollInfo>> fetchPolls() => throw UnimplementedError();

  @override
  Future<PollSnapshot> fetchPoll(String address) async {
    if (error != null) throw error!;
    return snap!;
  }

  @override
  Future<List<String>> fetchGroup(String address) => throw UnimplementedError();

  @override
  Future<PollSummary> fetchSummary(String address) =>
      throw UnimplementedError();
}

const addr = '0xd8058efe0198ae9dD7D563e1b4938Dcbc86A1F81';

Widget wrap(PollRepository repo) => MaterialApp(
  home: MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => PollDetailViewModel(repo, addr)),
      // No dev key → canSign false → the "organize live session" entry hides.
      Provider<ChainWriter>(
        create: (_) =>
            ChainWriter(rpcUrl: 'http://127.0.0.1:1', chainId: 31337),
      ),
      // Relayer 503 → no relayer address → RUN BY falls back to the short
      // address (the detail screen probes /info on open).
      Provider<RelayClient>(
        create: (_) => RelayClient(
          baseUrl: 'http://relayer.test',
          client: MockClient((_) async => http.Response('{}', 503)),
        ),
      ),
    ],
    child: const PollDetailScreen(address: addr),
  ),
);

void main() {
  testWidgets('renders phase badge, options, and result percentages', (
    tester,
  ) async {
    final snap = PollSnapshot(
      address: addr,
      state: 1, // Voting
      options: const ['Yes', 'No', 'Abstain'],
      results: [BigInt.from(3), BigInt.from(1), BigInt.zero],
      owner: '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266',
      participantCount: BigInt.from(4),
    );
    await tester.pumpWidget(wrap(FakeRepo(snap: snap)));
    await tester.pumpAndSettle();

    expect(find.text('VOTING'), findsOneWidget); // phase strip current step
    expect(find.text('Yes'), findsOneWidget);
    expect(find.text('No'), findsOneWidget);
    expect(find.text('Abstain'), findsOneWidget);
    expect(find.text('75.0%'), findsOneWidget); // Yes = 3 of 4
    expect(find.textContaining('4 REGISTERED'), findsOneWidget);
  });

  testWidgets('all-zero results render the "No votes yet" empty state', (
    tester,
  ) async {
    // Carried results-charts case: a Voting poll with no votes yet shows the
    // ResultsBars empty state (no bars, no divide-by-zero), not a 0% chart.
    final snap = PollSnapshot(
      address: addr,
      state: 1, // Voting
      options: const ['Yes', 'No', 'Abstain'],
      results: [BigInt.zero, BigInt.zero, BigInt.zero],
      owner: '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266',
      participantCount: BigInt.from(2),
    );
    await tester.pumpWidget(wrap(FakeRepo(snap: snap)));
    await tester.pumpAndSettle();

    expect(find.text('No votes yet'), findsOneWidget);
    expect(find.byType(FractionallySizedBox), findsNothing); // no bars drawn
  });

  testWidgets('shows error state on read failure', (tester) async {
    await tester.pumpWidget(wrap(FakeRepo(error: Exception('rpc down'))));
    await tester.pumpAndSettle();
    expect(find.text("COULDN'T LOAD THIS POLL"), findsOneWidget);
  });
}
