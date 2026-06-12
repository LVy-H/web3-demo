// Widget tests for the VOTE home: section bucketing by journey state,
// receipt chips, the friendly empty push toward JOIN, and the DIRECTORY tab.
import 'package:feature_vote/feature_vote.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

KnownPoll poll(
  String address, {
  required KnownPollStage stage,
  String title = 'Poll',
  String moduleType = 'anon-vote',
  int joinedAtMs = 1,
  String? receiptCode,
}) => KnownPoll(
  address: address,
  title: title,
  moduleType: moduleType,
  stage: stage,
  joinedAtMs: joinedAtMs,
  receiptCode: receiptCode,
);

void main() {
  Future<void> pumpHome(
    WidgetTester tester, {
    List<KnownPoll> polls = const [],
    Map<String, int> phases = const {},
    Future<List<ListedPoll>> Function()? fetchDirectory,
    void Function(String address)? onOpenPoll,
    VoidCallback? onJoin,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: VoteHomeScreen(
          knownPolls: InMemoryKnownPollsStore(polls),
          fetchPhase: (address) async =>
              phases[address] ?? (throw Exception('unreachable')),
          fetchDirectory: fetchDirectory ?? () async => const [],
          onOpenPoll: onOpenPoll ?? (_) {},
          onJoin: onJoin ?? () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('sections bucket polls by journey state', (tester) async {
    await pumpHome(
      tester,
      polls: [
        poll('0xa', stage: KnownPollStage.joined, title: 'Open now'),
        poll('0xb', stage: KnownPollStage.joined, title: 'Not open yet'),
        poll('0xc', stage: KnownPollStage.committed, title: 'Locked in'),
        poll('0xd', stage: KnownPollStage.committed, title: 'Confirm me'),
        poll(
          '0xe',
          stage: KnownPollStage.voted,
          title: 'Voted already',
          receiptCode: '9876543210123',
        ),
      ],
      phases: {'0xa': 1, '0xb': 0, '0xc': 1, '0xd': 2, '0xe': 1},
    );

    expect(find.text('NEEDS YOU'), findsOneWidget);
    expect(find.text('WAITING'), findsOneWidget);
    expect(find.text('DONE'), findsOneWidget);

    // NEEDS YOU: voting open and not voted + committed poll whose
    // confirmation window opened.
    expect(find.text('Open now'), findsOneWidget);
    expect(find.text('VOTING IS OPEN'), findsOneWidget);
    expect(find.text('Confirm me'), findsOneWidget);
    expect(find.text('CONFIRM YOUR VOTE NOW'), findsOneWidget);

    // WAITING: joined-not-open + committed-awaiting-close.
    expect(find.text('Not open yet'), findsOneWidget);
    expect(find.text('Locked in'), findsOneWidget);

    // DONE: receipt chip with the (truncated) code.
    expect(find.text('Voted already'), findsOneWidget);
    expect(find.text('RECEIPT 9876543210…'), findsOneWidget);
  });

  testWidgets('unreachable chain reads land in WAITING with honest copy', (
    tester,
  ) async {
    await pumpHome(
      tester,
      polls: [poll('0xa', stage: KnownPollStage.joined, title: 'Offline')],
      phases: const {}, // fetchPhase throws for every address
    );

    expect(find.text('WAITING'), findsOneWidget);
    expect(find.text('CAN’T CHECK RIGHT NOW'), findsOneWidget);
  });

  testWidgets('empty home pushes toward JOIN', (tester) async {
    var joined = false;
    await pumpHome(tester, onJoin: () => joined = true);

    expect(find.byKey(VoteHomeScreen.emptyStateKey), findsOneWidget);
    expect(
      find.text('Scan or paste an invite to join your first vote.'),
      findsOneWidget,
    );

    await tester.tap(find.text('JOIN A VOTE'));
    expect(joined, isTrue);
  });

  testWidgets('tapping a poll card opens the poll route', (tester) async {
    String? opened;
    await pumpHome(
      tester,
      polls: [poll('0xAbC', stage: KnownPollStage.joined, title: 'Open now')],
      phases: const {'0xAbC': 1},
      onOpenPoll: (address) => opened = address,
    );

    await tester.tap(find.text('Open now'));
    expect(opened, '0xAbC');
  });

  group('DIRECTORY tab', () {
    testWidgets('lists publicly listed polls with jargon-free kind labels', (
      tester,
    ) async {
      String? opened;
      await pumpHome(
        tester,
        fetchDirectory: () async => const [
          ListedPoll(
            address: '0x1',
            moduleType: 'ranked-vote',
            title: 'Community board',
            description: 'Pick the new board.',
          ),
        ],
        onOpenPoll: (address) => opened = address,
      );

      await tester.tap(find.byKey(VoteHomeScreen.directoryTabKey));
      await tester.pumpAndSettle();

      expect(find.text('Community board'), findsOneWidget);
      expect(find.text('RANK THEM'), findsOneWidget);
      expect(find.text('ranked-vote'), findsNothing); // raw id never leaks

      await tester.tap(find.text('Community board'));
      expect(opened, '0x1');
    });

    testWidgets('directory failure shows a retry, not a crash', (tester) async {
      var calls = 0;
      await pumpHome(
        tester,
        fetchDirectory: () async {
          calls += 1;
          if (calls == 1) throw Exception('rpc down');
          return const [
            ListedPoll(
              address: '0x1',
              moduleType: 'anon-vote',
              title: 'Back online',
              description: '',
            ),
          ];
        },
      );

      await tester.tap(find.byKey(VoteHomeScreen.directoryTabKey));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Could not load the directory'),
        findsOneWidget,
      );

      await tester.tap(find.text('TRY AGAIN'));
      await tester.pumpAndSettle();
      expect(find.text('Back online'), findsOneWidget);
    });

    testWidgets('empty directory explains private-by-default', (tester) async {
      await pumpHome(tester);
      await tester.tap(find.byKey(VoteHomeScreen.directoryTabKey));
      await tester.pumpAndSettle();
      expect(find.textContaining('Most votes are private'), findsOneWidget);
    });
  });
}
