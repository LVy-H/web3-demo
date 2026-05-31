import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:zkvote_mobile/data/models/poll_info.dart';
import 'package:zkvote_mobile/data/models/poll_snapshot.dart';
import 'package:zkvote_mobile/data/repositories/poll_repository.dart';
import 'package:zkvote_mobile/ui/features/poll_detail/poll_detail_screen.dart';
import 'package:zkvote_mobile/ui/features/poll_detail/poll_detail_view_model.dart';

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
}

const addr = '0xd8058efe0198ae9dD7D563e1b4938Dcbc86A1F81';

Widget wrap(PollRepository repo) => MaterialApp(
      home: ChangeNotifierProvider(
        create: (_) => PollDetailViewModel(repo, addr),
        child: const PollDetailScreen(address: addr),
      ),
    );

void main() {
  testWidgets('renders phase badge, options, and result percentages',
      (tester) async {
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

  testWidgets('shows error state on read failure', (tester) async {
    await tester.pumpWidget(wrap(FakeRepo(error: Exception('rpc down'))));
    await tester.pumpAndSettle();
    expect(find.text("COULDN'T LOAD THIS POLL"), findsOneWidget);
  });
}
