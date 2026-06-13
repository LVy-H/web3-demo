// Widget tests for the sealed-until-reveal surface: real machine, fake port.
// The salt-backup gate, the client-side reveal deadline and the honest
// dead-ends are exercised the way production reaches them.
import 'package:core_domain/journeys/blind_journey.dart';
import 'package:feature_vote/feature_vote.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeBlindPort implements BlindJourneyPort {
  int phase;
  bool registered;
  bool committed;
  bool revealed;
  bool finalized;
  bool saltAvailable;
  DateTime deadline;

  int registerCalls = 0;
  int? committedOption;
  int revealCalls = 0;

  FakeBlindPort({
    this.phase = 0,
    this.registered = false,
    this.committed = false,
    this.revealed = false,
    this.finalized = false,
    this.saltAvailable = true,
    DateTime? deadline,
  }) : deadline = deadline ?? DateTime(2100);

  @override
  Future<BlindJourneySnapshot> fetchState() async => BlindJourneySnapshot(
    phase: phase,
    registered: registered,
    committed: committed,
    revealed: revealed,
    finalized: finalized,
  );

  @override
  Future<void> register() async {
    registerCalls += 1;
    registered = true;
  }

  @override
  Future<SaltReceipt> commit(int optionIndex) async {
    committedOption = optionIndex;
    committed = true;
    return SaltReceipt(optionIndex: optionIndex, saltHex: '0x${'ab' * 32}');
  }

  @override
  Future<bool> hasSalt() async => saltAvailable;

  @override
  Future<void> reveal() async {
    revealCalls += 1;
    revealed = true;
  }

  @override
  Future<DateTime> fetchRevealDeadline() async => deadline;
}

void main() {
  Future<BlindJourneyMachine> pumpScreen(
    WidgetTester tester,
    FakeBlindPort port, {
    DateTime Function()? clock,
    Future<List<String>> Function()? loadOptions,
    Future<(List<String>, List<BigInt>)> Function()? loadTally,
  }) async {
    final machine = BlindJourneyMachine(port: port, clock: clock);
    addTearDown(machine.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: BlindJourneyScreen(
          machine: machine,
          title: 'Budget vote',
          loadOptions: loadOptions ?? () async => const ['Alpha', 'Beta'],
          loadTally:
              loadTally ??
              () async => (const ['Alpha', 'Beta'], [BigInt.two, BigInt.one]),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return machine;
  }

  testWidgets('registration open → join → registered (waiting)', (
    tester,
  ) async {
    final port = FakeBlindPort();
    final machine = await pumpScreen(tester, port);

    expect(find.text('JOIN THIS VOTE'), findsOneWidget);
    await tester.tap(find.text('JOIN THIS VOTE'));
    await tester.pumpAndSettle();

    expect(port.registerCalls, 1);
    expect(machine.state, isA<BlindRegistered>());
    expect(find.text('WAITING FOR VOTING TO OPEN'), findsOneWidget);
  });

  testWidgets(
    'voting open → pick + lock in → salt gate blocks until acknowledged',
    (tester) async {
      final port = FakeBlindPort(phase: 1, registered: true);
      final machine = await pumpScreen(tester, port);
      await tester.pumpAndSettle();

      // Lock-in disabled until a choice is made — with the reason shown.
      expect(find.text('LOCK IN YOUR VOTE'), findsOneWidget);
      expect(find.text('Make your choice first.'), findsOneWidget);

      await tester.tap(find.text('Beta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('LOCK IN YOUR VOTE'));
      await tester.pumpAndSettle();

      expect(port.committedOption, 1);
      // The salt-backup gate is THE next action — key shown, not skippable
      // silently.
      expect(find.byKey(BlindJourneyScreen.saltGateKey), findsOneWidget);
      expect(find.textContaining('0x${'ab' * 32}'), findsOneWidget);

      await tester.tap(find.byKey(BlindJourneyScreen.saltAckKey));
      await tester.pumpAndSettle();
      final state = machine.state;
      expect(state, isA<BlindCommitted>());
      expect((state as BlindCommitted).backupAcknowledged, isTrue);
      expect(
        find.text('LOCKED IN — WAITING FOR VOTING TO CLOSE'),
        findsOneWidget,
      );
    },
  );

  testWidgets('reveal window: countdown shown, confirm sends the reveal', (
    tester,
  ) async {
    final now = DateTime(2026, 6, 12, 12);
    final port = FakeBlindPort(
      phase: 2,
      registered: true,
      committed: true,
      deadline: now.add(const Duration(minutes: 5)),
    );
    final machine = await pumpScreen(tester, port, clock: () => now);
    // No pumpAndSettle here: the countdown's periodic timer never settles.
    await tester.pump();
    await tester.pump();

    expect(machine.state, isA<BlindRevealWindow>());
    expect(find.byKey(BlindJourneyScreen.countdownKey), findsOneWidget);
    expect(find.text('CONFIRM YOUR VOTE'), findsOneWidget);

    await tester.tap(find.text('CONFIRM YOUR VOTE'));
    await tester.pump();
    await tester.pump();

    expect(port.revealCalls, 1);
    expect(machine.state, isA<BlindRevealed>());
    expect(find.text('WAITING FOR FINAL RESULTS'), findsOneWidget);

    // Tear the widget down explicitly so no countdown timer outlives the test.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('deadline already passed → honest missed-confirmation end', (
    tester,
  ) async {
    final now = DateTime(2026, 6, 12, 12);
    final port = FakeBlindPort(
      phase: 2,
      registered: true,
      committed: true,
      deadline: now.subtract(const Duration(minutes: 1)),
    );
    final machine = await pumpScreen(tester, port, clock: () => now);
    await tester.pumpAndSettle();

    expect(machine.state, isA<BlindMissedReveal>());
    expect(
      find.textContaining('closed before this vote was confirmed'),
      findsOneWidget,
    );
  });

  testWidgets('salt missing on this device → honest dead-end, no actions', (
    tester,
  ) async {
    final port = FakeBlindPort(
      phase: 2,
      registered: true,
      committed: true,
      saltAvailable: false,
    );
    final machine = await pumpScreen(tester, port);
    await tester.pumpAndSettle();

    expect(machine.state, isA<BlindSaltMissing>());
    expect(
      find.textContaining('Your vote key isn’t on this device'),
      findsOneWidget,
    );
    expect(find.text('CONFIRM YOUR VOTE'), findsNothing);
  });

  testWidgets('finalized poll renders the revealed tally', (tester) async {
    final port = FakeBlindPort(
      phase: 2,
      registered: true,
      committed: true,
      revealed: true,
      finalized: true,
    );
    await pumpScreen(tester, port);
    await tester.pumpAndSettle();

    expect(find.text('FINAL RESULTS'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
  });

  testWidgets('ended before joining → honest cannot-take-part copy', (
    tester,
  ) async {
    final port = FakeBlindPort(phase: 2);
    final machine = await pumpScreen(tester, port);
    await tester.pumpAndSettle();

    expect(machine.state, isA<BlindCannotParticipate>());
    expect(
      find.textContaining('Joining closed before you joined'),
      findsOneWidget,
    );
  });

  testWidgets('results load failure shows an error with a way out, never a '
      'forever spinner', (tester) async {
    final port = FakeBlindPort(
      phase: 2,
      registered: true,
      committed: true,
      revealed: true,
      finalized: true,
    );
    var attempts = 0;
    await pumpScreen(
      tester,
      port,
      loadTally: () async {
        attempts += 1;
        if (attempts == 1) throw Exception('network');
        return (const ['Alpha', 'Beta'], [BigInt.two, BigInt.one]);
      },
    );
    await tester.pumpAndSettle();

    // The failed load must NOT leave a perpetual "LOADING RESULTS…" spinner.
    expect(find.text('LOADING RESULTS…'), findsNothing);
    expect(
      find.text('Could not load this vote. Check your connection.'),
      findsOneWidget,
    );

    // Retrying re-runs the loader and renders the tally.
    await tester.tap(find.text('TRY AGAIN'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('FINAL RESULTS'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
  });

  testWidgets('options load failure shows an error with a way out, never a '
      'forever spinner', (tester) async {
    final port = FakeBlindPort(phase: 1, registered: true);
    var attempts = 0;
    await pumpScreen(
      tester,
      port,
      loadOptions: () async {
        attempts += 1;
        if (attempts == 1) throw Exception('network');
        return const ['Alpha', 'Beta'];
      },
    );
    await tester.pumpAndSettle();

    expect(find.text('LOADING OPTIONS…'), findsNothing);
    expect(
      find.text('Could not load this vote. Check your connection.'),
      findsOneWidget,
    );

    await tester.tap(find.text('TRY AGAIN'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
  });

  testWidgets(
    'reveal countdown is a live region with a spoken time-left label',
    (tester) async {
      final handle = tester.ensureSemantics();
      final now = DateTime(2026, 6, 12, 12);
      final port = FakeBlindPort(
        phase: 2,
        registered: true,
        committed: true,
        deadline: now.add(const Duration(minutes: 5)),
      );
      await pumpScreen(tester, port, clock: () => now);
      await tester.pump();
      await tester.pump();

      // The deadline — the most consequential fact on this screen — must be
      // announced (a missed confirmation is a permanently lost vote), and it
      // must be a live region so a screen reader re-reads it as it ticks down.
      expect(
        tester.getSemantics(find.byKey(BlindJourneyScreen.countdownKey)),
        isSemantics(
          isLiveRegion: true,
          label: 'Time left to confirm your vote: 5 minutes 0 seconds',
        ),
      );

      handle.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('save-your-vote-key gate: copy confirms, and the buttons are '
      'labelled for assistive tech', (tester) async {
    final handle = tester.ensureSemantics();
    final port = FakeBlindPort(phase: 1, registered: true);
    await pumpScreen(tester, port);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('LOCK IN YOUR VOTE'));
    await tester.pumpAndSettle();

    // The "I've saved it" acknowledgement is a real button to a screen reader,
    // not a mystery tap target.
    expect(
      tester.getSemantics(find.byKey(BlindJourneyScreen.saltAckKey)),
      isSemantics(isButton: true, label: 'I’VE SAVED IT'),
    );

    // "Did it copy?" — tapping copy surfaces an unmistakable confirmation,
    // not a silent no-op (the vote key is the one irreversible thing here).
    expect(find.text('COPY KEY'), findsOneWidget);
    await tester.tap(find.byKey(BlindJourneyScreen.saltCopyKey));
    await tester.pump(); // let the SnackBar appear

    expect(
      find.text('Vote key copied — keep it somewhere safe.'),
      findsOneWidget,
    );

    handle.dispose();
  });

  testWidgets(
    'reveal countdown does not overflow on a multi-day window at large text '
    'scale and narrow width',
    (tester) async {
      // A render-time regression invisible to logic tests: a multi-hour /
      // multi-day window (H:MM:SS with unbounded hours) plus a large OS text
      // scale would stripe a RenderFlex overflow across the deadline — the
      // single most consequential fact on this screen.
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final now = DateTime(2026, 6, 12, 12);
      final port = FakeBlindPort(
        phase: 2,
        registered: true,
        committed: true,
        deadline: now.add(const Duration(hours: 120)),
      );
      final machine = BlindJourneyMachine(port: port, clock: () => now);
      addTearDown(machine.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
            child: BlindJourneyScreen(
              machine: machine,
              title: 'Budget vote',
              loadOptions: () async => const ['Alpha', 'Beta'],
            ),
          ),
        ),
      );
      // No pumpAndSettle: the countdown's periodic timer never settles.
      await tester.pump();
      await tester.pump();

      expect(machine.state, isA<BlindRevealWindow>());
      expect(find.byKey(BlindJourneyScreen.countdownKey), findsOneWidget);
      // The unbounded-hours value is rendered (proves the wide-window path),
      // and the row lays out without a RenderFlex overflow exception.
      expect(find.textContaining('120:00:00'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Tear the widget down so no countdown timer outlives the test.
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'salt-ack control meets the 48dp tap target and still acknowledges',
    (tester) async {
      // The irreversible "I backed up my vote key" gate must clear the 48dp
      // minimum (it was a fixed 40dp box that also clipped its label at large
      // font scale) — and tapping it must still advance the journey.
      final port = FakeBlindPort(phase: 1, registered: true);
      final machine = await pumpScreen(tester, port);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Beta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('LOCK IN YOUR VOTE'));
      await tester.pumpAndSettle();

      final ackSize = tester.getSize(find.byKey(BlindJourneyScreen.saltAckKey));
      expect(
        ackSize.height,
        greaterThanOrEqualTo(48.0),
        reason: 'the vote-key backup gate must hold the 48dp minimum',
      );

      await tester.tap(find.byKey(BlindJourneyScreen.saltAckKey));
      await tester.pumpAndSettle();
      final state = machine.state;
      expect(state, isA<BlindCommitted>());
      expect((state as BlindCommitted).backupAcknowledged, isTrue);
    },
  );
}
