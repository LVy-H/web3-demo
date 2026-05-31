import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:zkvote_mobile/data/models/poll_info.dart';
import 'package:zkvote_mobile/data/models/poll_snapshot.dart';
import 'package:zkvote_mobile/data/repositories/poll_repository.dart';
import 'package:zkvote_mobile/ui/features/browse/browse_screen.dart';
import 'package:zkvote_mobile/ui/features/browse/browse_view_model.dart';

class FakePollRepository implements PollRepository {
  final List<PollInfo>? polls;
  final Object? error;
  FakePollRepository({this.polls, this.error});

  @override
  Future<List<PollInfo>> fetchPolls() async {
    if (error != null) throw error!;
    return polls ?? const [];
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

Widget _wrap(PollRepository repo) => MaterialApp(
      home: ChangeNotifierProvider(
        create: (_) => BrowseViewModel(repo),
        child: const BrowseScreen(),
      ),
    );

void main() {
  testWidgets('renders the hero + poll cards with VOTING state chips',
      (tester) async {
    await tester.pumpWidget(_wrap(FakePollRepository(polls: [
      _poll('0x1111111111111111111111111111111111111111', 'Budget 2026'),
      _poll('0x2222222222222222222222222222222222222222', 'Board Seat'),
    ])));
    await tester.pumpAndSettle();

    expect(find.text('POLLS'), findsOneWidget); // hero
    expect(find.text('Budget 2026'), findsOneWidget);
    expect(find.text('Board Seat'), findsOneWidget);
    expect(find.text('VOTING'), findsNWidgets(2)); // one state chip per card
  });

  testWidgets('renders empty state when no polls match', (tester) async {
    await tester.pumpWidget(_wrap(FakePollRepository(polls: const [])));
    await tester.pumpAndSettle();
    expect(find.text('No polls match this filter'), findsOneWidget);
  });

  testWidgets('renders error state with retry', (tester) async {
    await tester.pumpWidget(_wrap(FakePollRepository(error: Exception('boom'))));
    await tester.pumpAndSettle();
    expect(find.text("COULDN'T LOAD POLLS"), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'RETRY'), findsOneWidget);
  });
}
