// The dashboard card is a thin renderer of an organizer journey state:
// one phase chip, honest counts, ONE next action, the small-group chip
// (spec §4.1, §5). One test per state.
import 'package:core_domain/journeys/journey.dart';
import 'package:core_domain/journeys/organizer_journey.dart';
import 'package:feature_organize/feature_organize.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _spec = OrganizerPollSpec(
  module: OrganizerModule.anonVote,
  title: 'Snack budget',
  options: ['Fruit', 'Crisps'],
);

Future<void> _pump(
  WidgetTester tester,
  OrganizerDeployedState state, {
  VoidCallback? onAction,
  VoidCallback? onDistribute,
  VoidCallback? onRunEvent,
  String? errorText,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: OrganizerPollCard(
          state: state,
          title: 'Snack budget',
          onAction: onAction ?? () {},
          onDistribute: onDistribute,
          onRunEvent: onRunEvent,
          errorText: errorText,
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('created: unlisted notice + DISTRIBUTE as THE next action', (
    tester,
  ) async {
    await _pump(
      tester,
      const OrganizerCreated(
        pollAddress: '0xpoll',
        spec: _spec,
        shareTargets: [ShareTarget.qr, ShareTarget.link, ShareTarget.code],
      ),
    );

    expect(find.text('CREATED'), findsOneWidget);
    expect(find.text('DISTRIBUTE'), findsOneWidget);
    expect(
      find.textContaining('Your poll is private'),
      findsOneWidget,
      reason: 'spec §5: the unlisted default is said out loud',
    );
  });

  testWidgets('registrationOpen: roster count + START VOTING', (tester) async {
    var started = false;
    await _pump(
      tester,
      OrganizerRegistrationOpen(
        pollAddress: '0xpoll',
        spec: _spec,
        rosterCount: 9,
        fetchPending: false,
        cancellation: CancellationToken(),
      ),
      onAction: () => started = true,
      onDistribute: () {},
      onRunEvent: () {},
    );

    expect(find.text('REGISTRATION'), findsOneWidget);
    expect(find.text('9 registered'), findsOneWidget);
    expect(find.text('START VOTING'), findsOneWidget);
    // Distribute + run-event side entries ride along in this phase.
    expect(find.byKey(const Key('card-distribute')), findsOneWidget);
    expect(find.byKey(const Key('card-run-event')), findsOneWidget);

    await tester.tap(find.byKey(OrganizerPollCard.nextActionKey));
    expect(started, isTrue);
  });

  testWidgets('votingOpen: turnout only (never a tally) + CLOSE VOTING + '
      'small-group chip', (tester) async {
    await _pump(
      tester,
      OrganizerVotingOpen(
        pollAddress: '0xpoll',
        spec: _spec,
        rosterCount: 4,
        turnout: 3,
        smallGroupWarning: true,
        fetchPending: false,
        cancellation: CancellationToken(),
      ),
    );

    expect(find.text('VOTING OPEN'), findsOneWidget);
    expect(find.text('3 of 4 voted'), findsOneWidget);
    expect(find.text('CLOSE VOTING'), findsOneWidget);
    expect(find.byKey(OrganizerPollCard.smallGroupChipKey), findsOneWidget);
    expect(find.textContaining('results can identify people'), findsOneWidget);
  });

  testWidgets('closed (non-blind): PUBLISH RESULTS enabled', (tester) async {
    await _pump(
      tester,
      OrganizerClosed(
        pollAddress: '0xpoll',
        spec: _spec,
        rosterCount: 10,
        turnout: 8,
        smallGroupWarning: false,
        finalized: true,
        revealWindowElapsed: true,
        fetchPending: false,
        cancellation: CancellationToken(),
      ),
    );

    expect(find.text('CLOSED'), findsOneWidget);
    expect(find.text('PUBLISH RESULTS'), findsOneWidget);
    expect(find.byKey(const Key('card-disabled-reason')), findsNothing);
  });

  testWidgets('closed blind before the reveal window elapses: FINALIZE '
      'disabled with the honest reason', (tester) async {
    await _pump(
      tester,
      OrganizerClosed(
        pollAddress: '0xpoll',
        spec: const OrganizerPollSpec(
          module: OrganizerModule.blindVote,
          title: 'Sealed vote',
          options: ['Yes', 'No'],
          revealWindow: Duration(hours: 1),
        ),
        rosterCount: 10,
        turnout: 8,
        smallGroupWarning: false,
        finalized: false,
        revealWindowElapsed: false,
        fetchPending: false,
        cancellation: CancellationToken(),
      ),
    );

    expect(find.text('FINALIZE RESULTS'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(OrganizerPollCard.nextActionKey),
    );
    expect(button.onPressed, isNull);
    expect(find.textContaining('reveal window is still open'), findsOneWidget);
  });

  testWidgets('published: results bars, no further action', (tester) async {
    await _pump(
      tester,
      const OrganizerPublished(
        pollAddress: '0xpoll',
        spec: _spec,
        results: OrganizerResults({'Fruit': 5, 'Crisps': 3}),
        turnout: 8,
        smallGroupWarning: false,
      ),
    );

    expect(find.text('RESULTS'), findsOneWidget);
    expect(find.byKey(OrganizerPollCard.nextActionKey), findsNothing);
    expect(find.text('Fruit'), findsOneWidget);
    expect(find.text('Crisps'), findsOneWidget);
  });

  testWidgets('a failed action surfaces its organizer-facing error text', (
    tester,
  ) async {
    await _pump(
      tester,
      OrganizerRegistrationOpen(
        pollAddress: '0xpoll',
        spec: _spec,
        rosterCount: 2,
        fetchPending: false,
        cancellation: CancellationToken(),
      ),
      errorText: 'Voting could not be started. Try again.',
    );

    expect(
      find.text('Voting could not be started. Try again.'),
      findsOneWidget,
    );
  });

  testWidgets('icon-only side actions carry accessible labels — a screen '
      'reader hears what distribute / run-event do', (tester) async {
    await _pump(
      tester,
      OrganizerRegistrationOpen(
        pollAddress: '0xpoll',
        spec: _spec,
        rosterCount: 9,
        fetchPending: false,
        cancellation: CancellationToken(),
      ),
      onDistribute: () {},
      onRunEvent: () {},
    );

    // The qr_code_2 / sensors glyphs alone say nothing to assistive tech.
    expect(find.bySemanticsLabel('Distribute this poll'), findsOneWidget);
    expect(find.bySemanticsLabel('Run live event'), findsOneWidget);
  });
}
