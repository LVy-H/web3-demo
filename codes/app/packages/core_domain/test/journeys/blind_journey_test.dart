import 'package:core_domain/journeys/blind_journey.dart';
import 'package:core_domain/journeys/journey.dart';
// `hide`: the journey contract's Retry/Timeout events share names with
// package:test configuration types we don't use here.
import 'package:test/test.dart' hide Retry, Timeout;

/// Drains the event queue so fire-and-forget effect completions land.
Future<void> settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Controllable fake port: every effect can be made to fail once, and the
/// reveal deadline / salt availability are settable per test.
final class FakeBlindPort implements BlindJourneyPort {
  BlindJourneySnapshot snapshot = const BlindJourneySnapshot(
    phase: 0,
    registered: false,
    committed: false,
    revealed: false,
    finalized: false,
  );

  bool saltAvailable = true;
  DateTime revealDeadline = DateTime.utc(2026, 6, 11, 13);

  Object? nextFetchError;
  Object? nextRegisterError;
  Object? nextCommitError;
  Object? nextRevealError;
  Object? nextDeadlineError;

  int fetchCalls = 0;
  int registerCalls = 0;
  int commitCalls = 0;
  int revealCalls = 0;
  final List<int> committedOptions = [];

  Object? _take(Object? error, void Function() clear) {
    if (error != null) clear();
    return error;
  }

  @override
  Future<BlindJourneySnapshot> fetchState() async {
    fetchCalls++;
    final error = _take(nextFetchError, () => nextFetchError = null);
    if (error != null) throw error;
    return snapshot;
  }

  @override
  Future<void> register() async {
    registerCalls++;
    final error = _take(nextRegisterError, () => nextRegisterError = null);
    if (error != null) throw error;
  }

  @override
  Future<SaltReceipt> commit(int optionIndex) async {
    commitCalls++;
    final error = _take(nextCommitError, () => nextCommitError = null);
    if (error != null) throw error;
    committedOptions.add(optionIndex);
    return SaltReceipt(optionIndex: optionIndex, saltHex: '0xfeedc0de');
  }

  @override
  Future<bool> hasSalt() async => saltAvailable;

  @override
  Future<void> reveal() async {
    revealCalls++;
    final error = _take(nextRevealError, () => nextRevealError = null);
    if (error != null) throw error;
  }

  @override
  Future<DateTime> fetchRevealDeadline() async {
    final error = _take(nextDeadlineError, () => nextDeadlineError = null);
    if (error != null) throw error;
    return revealDeadline;
  }
}

void main() {
  late FakeBlindPort port;
  late DateTime now;
  late BlindJourneyMachine machine;

  /// Builds a machine over [port] with a controllable clock and lets the
  /// initial load settle.
  Future<void> start() async {
    machine = BlindJourneyMachine(port: port, clock: () => now);
    addTearDown(machine.dispose);
    await settle();
  }

  /// Drives a fresh machine to [BlindRevealWindow] via the resume route
  /// (snapshot: committed, poll ended).
  Future<void> startInRevealWindow() async {
    port.snapshot = const BlindJourneySnapshot(
      phase: 2,
      registered: true,
      committed: true,
      revealed: false,
      finalized: false,
    );
    await start();
    expect(machine.state, isA<BlindRevealWindow>());
  }

  setUp(() {
    port = FakeBlindPort();
    now = DateTime.utc(2026, 6, 11, 12);
    port.revealDeadline = now.add(const Duration(hours: 1));
  });

  group('happy path: register → commit → ack → reveal → results', () {
    test('walks every state in order with the right NextActions', () async {
      await start();

      // Loaded into registration.
      expect(machine.state, isA<BlindRegistrationOpen>());
      expect(machine.state.nextAction!.labelKey, 'action.register');
      expect(machine.state.nextAction!.type, NextActionType.submit);

      // Register. (The registering/committing/revealing in-progress states
      // are asserted via the states-stream test below: a fake port resolves
      // on a microtask, so they may already be left when advance() returns.)
      await machine.advance(const BlindRegisterRequested());
      await settle();
      expect(machine.state, isA<BlindRegistered>());
      expect(port.registerCalls, 1);
      expect(machine.state.nextAction!.type, NextActionType.wait);

      // Voting opens (external truth).
      await machine.advance(const ExternalPhaseChanged(1));
      expect(machine.state, isA<BlindVotingOpen>());
      expect(machine.state.nextAction!.labelKey, 'action.commitVote');

      // Commit option 2.
      await machine.advance(const BlindCommitRequested(2));
      await settle();
      final committed = machine.state as BlindCommitted;
      expect(port.committedOptions, [2]);
      expect(committed.receipt, isNotNull);
      expect(committed.receipt!.optionIndex, 2);
      expect(committed.receipt!.saltHex, '0xfeedc0de');

      // The backup gate: the ONE action is backing up the salt.
      expect(committed.backupAcknowledged, isFalse);
      expect(committed.nextAction!.labelKey, 'action.backUpSalt');
      expect(committed.nextAction!.type, NextActionType.submit);

      await machine.advance(const BlindSaltBackupAcknowledged());
      final acked = machine.state as BlindCommitted;
      expect(acked.backupAcknowledged, isTrue);
      expect(acked.receipt, committed.receipt);
      expect(acked.nextAction!.labelKey, 'action.waitingForPollEnd');
      expect(acked.nextAction!.type, NextActionType.wait);

      // Poll ends → salt + deadline check → reveal window.
      await machine.advance(const ExternalPhaseChanged(2));
      await settle();
      final window = machine.state as BlindRevealWindow;
      expect(window.revealDeadline, port.revealDeadline);
      expect(window.remaining, const Duration(hours: 1));
      expect(window.nextAction!.labelKey, 'action.revealVote');
      expect(window.nextAction!.enabled, isTrue);

      // Reveal.
      await machine.advance(const BlindRevealRequested());
      await settle();
      expect(machine.state, isA<BlindRevealed>());
      expect(port.revealCalls, 1);
      expect(machine.state.nextAction!.labelKey, 'action.waitingForResults');

      // Finalized.
      await machine.advance(const BlindResultsFinalized());
      expect(machine.state, isA<BlindResults>());
      expect(machine.state.isTerminal, isTrue);
      expect(machine.state.nextAction, isNull);
    });

    test('states stream emits ids in journey order', () async {
      await start();
      final seen = <String>[];
      final sub = machine.states.listen((s) => seen.add(s.id));
      addTearDown(sub.cancel);

      await machine.advance(const BlindRegisterRequested());
      await settle();
      await machine.advance(const ExternalPhaseChanged(1));
      await machine.advance(const BlindCommitRequested(0));
      await settle();
      await machine.advance(const BlindSaltBackupAcknowledged());
      await machine.advance(const ExternalPhaseChanged(2));
      await settle();
      await machine.advance(const BlindRevealRequested());
      await settle();
      await machine.advance(const BlindResultsFinalized());

      expect(seen, [
        'blind.registering',
        'blind.registered',
        'blind.votingOpen',
        'blind.committing',
        'blind.committed',
        'blind.committed', // backup acknowledged
        'blind.revealCheck',
        'blind.revealWindow',
        'blind.revealing',
        'blind.revealed',
        'blind.results',
      ]);
    });
  });

  group('salt-backup gate (audit fix: device-local salt loss)', () {
    Future<BlindCommitted> commitInSession() async {
      await start();
      await machine.advance(const BlindRegisterRequested());
      await settle();
      await machine.advance(const ExternalPhaseChanged(1));
      await machine.advance(const BlindCommitRequested(1));
      await settle();
      return machine.state as BlindCommitted;
    }

    test('exporting the salt counts as acknowledgment', () async {
      final committed = await commitInSession();
      expect(committed.saltExported, isFalse);

      await machine.advance(const BlindExportSaltRequested());
      final exported = machine.state as BlindCommitted;
      expect(exported.saltExported, isTrue);
      expect(exported.backupAcknowledged, isTrue);
      expect(exported.nextAction!.type, NextActionType.wait);
    });

    test('export without an in-session receipt is guard-rejected', () async {
      // Resumed session: committed on-chain, but the receipt cannot be
      // re-shown (salt lives only in local storage).
      port.snapshot = const BlindJourneySnapshot(
        phase: 1,
        registered: true,
        committed: true,
        revealed: false,
        finalized: false,
      );
      await start();
      final resumed = machine.state as BlindCommitted;
      expect(resumed.receipt, isNull);
      expect(resumed.backupAcknowledged, isTrue); // gate fired at commit time

      await expectLater(
        machine.advance(const BlindExportSaltRequested()),
        throwsA(
          isA<JourneyViolation>().having(
            (v) => v.guardRejected,
            'guardRejected',
            isTrue,
          ),
        ),
      );
    });

    test('SaltReceipt redacts the salt in toString', () {
      const receipt = SaltReceipt(optionIndex: 1, saltHex: '0xsecret');
      expect(receipt.toString(), isNot(contains('0xsecret')));
      expect(receipt, const SaltReceipt(optionIndex: 1, saltHex: '0xsecret'));
    });
  });

  group('reveal deadline (audit fix: client-enforced, not fail-on-chain)', () {
    test('reveal is guard-rejected once the deadline passes', () async {
      await startInRevealWindow();

      now = port.revealDeadline.add(const Duration(seconds: 1));
      await expectLater(
        machine.advance(const BlindRevealRequested()),
        throwsA(
          isA<JourneyViolation>().having(
            (v) => v.guardRejected,
            'guardRejected',
            isTrue,
          ),
        ),
      );
      // State unchanged; the action honestly says why it is disabled.
      final window = machine.state as BlindRevealWindow;
      expect(window.isExpired, isTrue);
      expect(window.nextAction!.enabled, isFalse);
      expect(
        window.nextAction!.disabledReasonKey,
        'reason.revealDeadlinePassed',
      );

      // The UI's Timeout lands in the typed terminal explanation.
      await machine.advance(const Timeout());
      final missed = machine.state as BlindMissedReveal;
      expect(missed.isTerminal, isTrue);
      expect(missed.copyKey, 'copy.blind.missedReveal');
      expect(missed.nextAction, isNull);
    });

    test('arriving after the deadline goes straight to missedReveal', () async {
      port.revealDeadline = now.subtract(const Duration(minutes: 5));
      port.snapshot = const BlindJourneySnapshot(
        phase: 2,
        registered: true,
        committed: true,
        revealed: false,
        finalized: false,
      );
      await start();
      expect(machine.state, isA<BlindMissedReveal>());
    });

    test('countdown: remaining tracks the clock and clamps at zero', () async {
      await startInRevealWindow();
      final window = machine.state as BlindRevealWindow;

      expect(window.remaining, const Duration(hours: 1));
      expect(machine.revealTimeRemaining, const Duration(hours: 1));

      now = now.add(const Duration(minutes: 59));
      expect(window.remaining, const Duration(minutes: 1));

      now = now.add(const Duration(minutes: 2)); // past the deadline
      expect(window.remaining, Duration.zero);
      expect(window.isExpired, isTrue);
    });

    test('revealTimeRemaining is null outside the reveal window', () async {
      await start();
      expect(machine.state, isA<BlindRegistrationOpen>());
      expect(machine.revealTimeRemaining, isNull);
    });

    test('reveal failure: Retry allowed before the deadline, guard-rejected '
        'after; Timeout explains the miss', () async {
      await startInRevealWindow();
      port.nextRevealError = StateError('rpc unreachable');

      await machine.advance(const BlindRevealRequested());
      await settle();
      final failed = machine.state as BlindRevealError;
      expect(failed.messageKey, 'error.blind.revealFailed');
      expect(failed.recoveryEvent, isA<Retry>());

      // Window closes while sitting on the error.
      now = port.revealDeadline.add(const Duration(seconds: 1));
      await expectLater(
        machine.advance(const Retry()),
        throwsA(
          isA<JourneyViolation>().having(
            (v) => v.guardRejected,
            'guardRejected',
            isTrue,
          ),
        ),
      );
      await machine.advance(const Timeout());
      expect(machine.state, isA<BlindMissedReveal>());
      expect(port.revealCalls, 1);
    });

    test('reveal failure: Retry before the deadline reveals', () async {
      await startInRevealWindow();
      port.nextRevealError = StateError('rpc unreachable');

      await machine.advance(const BlindRevealRequested());
      await settle();
      expect(machine.state, isA<BlindRevealError>());

      await machine.advance(const Retry());
      await settle();
      expect(machine.state, isA<BlindRevealed>());
      expect(port.revealCalls, 2);
    });
  });

  group('saltMissing (audit fix: the unrecoverable case is typed)', () {
    test(
      'entering the reveal window without a salt dead-ends honestly',
      () async {
        port.saltAvailable = false;
        port.snapshot = const BlindJourneySnapshot(
          phase: 2,
          registered: true,
          committed: true,
          revealed: false,
          finalized: false,
        );
        await start();

        final missing = machine.state as BlindSaltMissing;
        expect(missing.isTerminal, isTrue);
        expect(missing.copyKey, 'copy.blind.saltMissing');
        expect(missing.nextAction, isNull);
      },
    );

    test('live poll-end with no salt also lands in saltMissing', () async {
      port.snapshot = const BlindJourneySnapshot(
        phase: 1,
        registered: true,
        committed: true,
        revealed: false,
        finalized: false,
      );
      await start();
      expect(machine.state, isA<BlindCommitted>());

      port.saltAvailable = false;
      await machine.advance(const ExternalPhaseChanged(2));
      await settle();
      expect(machine.state, isA<BlindSaltMissing>());
    });
  });

  group('effect failures are typed states with an exit', () {
    test(
      'commit failure → commitError → Retry re-commits same option',
      () async {
        await start();
        await machine.advance(const BlindRegisterRequested());
        await settle();
        await machine.advance(const ExternalPhaseChanged(1));

        port.nextCommitError = StateError('relayer down');
        await machine.advance(const BlindCommitRequested(3));
        await settle();

        final failed = machine.state as BlindCommitError;
        expect(failed.messageKey, 'error.blind.commitFailed');
        expect(failed.optionIndex, 3);
        expect(failed.cause, isA<StateError>());
        expect(failed.recoveryEvent, isA<Retry>());
        expect(failed.nextAction!.type, NextActionType.retry);

        await machine.advance(failed.recoveryEvent);
        await settle();
        final committed = machine.state as BlindCommitted;
        expect(committed.receipt!.optionIndex, 3);
        expect(port.commitCalls, 2);
        expect(port.committedOptions, [3]);
      },
    );

    test('load failure → loadError → Retry reloads', () async {
      port.nextFetchError = StateError('rpc down');
      await start();

      final failed = machine.state as BlindLoadError;
      expect(failed.messageKey, 'error.blind.loadFailed');

      await machine.advance(const Retry());
      await settle();
      expect(machine.state, isA<BlindRegistrationOpen>());
      expect(port.fetchCalls, 2);
    });

    test('register failure → registerError → Retry registers', () async {
      port.nextRegisterError = StateError('nonce too low');
      await start();
      await machine.advance(const BlindRegisterRequested());
      await settle();

      expect(machine.state, isA<BlindRegisterError>());
      await machine.advance(const Retry());
      await settle();
      expect(machine.state, isA<BlindRegistered>());
      expect(port.registerCalls, 2);
    });

    test('deadline-fetch failure → revealCheckError → Retry', () async {
      port.nextDeadlineError = StateError('rpc down');
      port.snapshot = const BlindJourneySnapshot(
        phase: 2,
        registered: true,
        committed: true,
        revealed: false,
        finalized: false,
      );
      await start();

      expect(machine.state, isA<BlindRevealCheckError>());
      await machine.advance(const Retry());
      await settle();
      expect(machine.state, isA<BlindRevealWindow>());
    });
  });

  group('phase gating and illegal transitions', () {
    test('voting ends before commit → cannotParticipate', () async {
      port.snapshot = const BlindJourneySnapshot(
        phase: 1,
        registered: true,
        committed: false,
        revealed: false,
        finalized: false,
      );
      await start();
      expect(machine.state, isA<BlindVotingOpen>());

      await machine.advance(const ExternalPhaseChanged(2));
      final out = machine.state as BlindCannotParticipate;
      expect(out.copyKey, 'copy.blind.endedWithoutCommit');
      expect(out.isTerminal, isTrue);
    });

    test('voting opens before registering → cannotParticipate', () async {
      await start();
      expect(machine.state, isA<BlindRegistrationOpen>());

      await machine.advance(const ExternalPhaseChanged(1));
      final out = machine.state as BlindCannotParticipate;
      expect(out.copyKey, 'copy.blind.registrationClosed');
    });

    test('reveal is not legal while merely committed', () async {
      port.snapshot = const BlindJourneySnapshot(
        phase: 1,
        registered: true,
        committed: true,
        revealed: false,
        finalized: false,
      );
      await start();
      expect(machine.state, isA<BlindCommitted>());

      await expectLater(
        machine.advance(const BlindRevealRequested()),
        throwsA(isA<JourneyViolation>()),
      );
      expect(machine.state, isA<BlindCommitted>());
    });

    test('commit with a negative option index is guard-rejected', () async {
      port.snapshot = const BlindJourneySnapshot(
        phase: 1,
        registered: true,
        committed: false,
        revealed: false,
        finalized: false,
      );
      await start();

      await expectLater(
        machine.advance(const BlindCommitRequested(-1)),
        throwsA(
          isA<JourneyViolation>().having(
            (v) => v.guardRejected,
            'guardRejected',
            isTrue,
          ),
        ),
      );
    });

    test('terminal states accept no events', () async {
      port.snapshot = const BlindJourneySnapshot(
        phase: 2,
        registered: true,
        committed: true,
        revealed: true,
        finalized: true,
      );
      await start();
      expect(machine.state, isA<BlindResults>());

      await expectLater(
        machine.advance(const Refresh()),
        throwsA(isA<JourneyViolation>()),
      );
    });
  });

  group('snapshot routing (resume anywhere)', () {
    test('revealed but not finalized resumes at revealed', () async {
      port.snapshot = const BlindJourneySnapshot(
        phase: 2,
        registered: true,
        committed: true,
        revealed: true,
        finalized: false,
      );
      await start();
      expect(machine.state, isA<BlindRevealed>());
    });

    test('registered during registration resumes waiting', () async {
      port.snapshot = const BlindJourneySnapshot(
        phase: 0,
        registered: true,
        committed: false,
        revealed: false,
        finalized: false,
      );
      await start();
      expect(machine.state, isA<BlindRegistered>());
    });

    test('unregistered after registration closes is honest about it', () async {
      port.snapshot = const BlindJourneySnapshot(
        phase: 1,
        registered: false,
        committed: false,
        revealed: false,
        finalized: false,
      );
      await start();
      final out = machine.state as BlindCannotParticipate;
      expect(out.copyKey, 'copy.blind.registrationClosed');
    });

    test('Refresh re-reads external truth from resting states', () async {
      port.snapshot = const BlindJourneySnapshot(
        phase: 0,
        registered: true,
        committed: false,
        revealed: false,
        finalized: false,
      );
      await start();
      expect(machine.state, isA<BlindRegistered>());

      // Voting opened and this voter committed elsewhere in the meantime.
      port.snapshot = const BlindJourneySnapshot(
        phase: 1,
        registered: true,
        committed: true,
        revealed: false,
        finalized: false,
      );
      await machine.advance(const Refresh());
      await settle();
      expect(machine.state, isA<BlindCommitted>());
      expect(port.fetchCalls, 2);
    });
  });
}
