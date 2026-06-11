import 'dart:async';

import 'package:core_domain/journeys/capabilities.dart';
import 'package:core_domain/journeys/journey.dart';
import 'package:core_domain/journeys/live_journeys.dart';
// `hide`: the journey contract's Retry/Timeout events share names with
// package:test configuration types we don't use here.
import 'package:test/test.dart' hide Retry, Timeout;

/// Drains the event queue so fire-and-forget effect completions land.
Future<void> settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

final class FakeTickerHandle {
  final Duration interval;
  late final StreamController<void> controller = StreamController<void>(
    onCancel: () => cancelled = true,
  );
  bool cancelled = false;

  FakeTickerHandle(this.interval);
}

/// Deterministic ticker: tests fire ticks by hand; cancellation observable.
final class FakeTicker implements LiveTicker {
  final List<FakeTickerHandle> handles = [];

  @override
  Stream<void> every(Duration interval) {
    final handle = FakeTickerHandle(interval);
    handles.add(handle);
    return handle.controller.stream;
  }

  FakeTickerHandle get active => handles.lastWhere((h) => !h.cancelled);

  int get liveCount => handles.where((h) => !h.cancelled).length;

  /// Fires one tick on the most recent live subscription and settles.
  Future<void> tick() async {
    active.controller.add(null);
    await settle();
  }
}

final class FakeVoterPort implements LiveVoterPort {
  Object? parseError;
  Object? announceError;
  Object? pollError;
  Object? proofError;
  Object? relayError;

  /// Non-null once the "host" has admitted the voter.
  LiveAdmission? admission;

  bool alive = true;

  int announceCount = 0;
  int pollCount = 0;
  int? provedOption;
  int? relayedOption;

  Object? _take(Object? error) => error;

  @override
  Future<LiveTicket> parseTicket(String raw) async {
    final error = _take(parseError);
    if (error != null) {
      parseError = null;
      throw error;
    }
    return LiveTicket(raw);
  }

  @override
  Future<LiveAnnouncement> announce(LiveTicket ticket) async {
    final error = _take(announceError);
    if (error != null) {
      announceError = null;
      throw error;
    }
    announceCount++;
    return LiveAnnouncement(
      commitment: 'commit-$announceCount',
      confirmationCode: 'CODE-$announceCount',
    );
  }

  @override
  Future<LiveAdmission?> pollAdmission(LiveAnnouncement announcement) async {
    pollCount++;
    final error = _take(pollError);
    if (error != null) {
      pollError = null;
      throw error;
    }
    return admission;
  }

  @override
  Future<bool> hostAlive() async => alive;

  @override
  Future<Object> generateProof(
    LiveAnnouncement announcement,
    int option,
  ) async {
    final error = _take(proofError);
    if (error != null) {
      proofError = null;
      throw error;
    }
    provedOption = option;
    return 'proof-$option';
  }

  @override
  Future<String> relayBallot(int option, Object proof) async {
    final error = _take(relayError);
    if (error != null) {
      relayError = null;
      throw error;
    }
    relayedOption = option;
    return '0xfeed';
  }
}

final class FakeHostPort implements LiveHostPort {
  Object? loadError;
  Object? confirmError;
  Object? startError;
  Object? closeError;

  AdmitQueue queueResponse = AdmitQueue.empty;

  int ticketCount = 0;
  int fetchCount = 0;
  final List<String> confirmedCodes = [];
  bool startCalled = false;
  bool closeCalled = false;

  @override
  Future<void> loadSession() async {
    final error = loadError;
    if (error != null) {
      loadError = null; // self-clearing so Retry can succeed
      throw error;
    }
  }

  @override
  Future<String> rotateTicket() async => 'T${++ticketCount}';

  @override
  Future<AdmitQueue> fetchQueue() async {
    fetchCount++;
    return queueResponse;
  }

  @override
  Future<AdmitQueue> confirmVoter(String confirmationCode) async {
    final error = confirmError;
    if (error != null) {
      confirmError = null;
      throw error;
    }
    confirmedCodes.add(confirmationCode);
    queueResponse = AdmitQueue(
      pending: queueResponse.pending
          .where((v) => v.confirmationCode != confirmationCode)
          .toList(),
      admitted: queueResponse.admitted + 1,
      turnout: queueResponse.turnout,
    );
    return queueResponse;
  }

  @override
  Future<void> startVoting() async {
    final error = startError;
    if (error != null) {
      startError = null;
      throw error;
    }
    startCalled = true;
  }

  @override
  Future<void> close() async {
    final error = closeError;
    if (error != null) {
      closeError = null;
      throw error;
    }
    closeCalled = true;
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

final Capabilities provingDevice = Capabilities.none.copyWith(
  canProve: true,
  canScanQr: true,
);

LiveVoterMachine voterMachine({
  required FakeVoterPort port,
  required FakeTicker ticker,
  Capabilities? capabilities,
  Duration pollInterval = const Duration(seconds: 1),
  Duration pendingTimeout = const Duration(minutes: 3),
}) {
  return LiveVoterMachine(
    port: port,
    ticker: ticker,
    capabilities: capabilities ?? provingDevice,
    pollInterval: pollInterval,
    pendingTimeout: pendingTimeout,
  );
}

/// Walks a voter machine to [LiveVoterPending] (ticket provided + joined).
Future<void> reachPending(LiveVoterMachine machine) async {
  await machine.advance(const LiveTicketProvided('tessera-ticket'));
  await settle();
  expect(machine.state, isA<LiveVoterPending>());
}

/// Walks a voter machine to [LiveVoterBallotOpen] via admission at phase 1.
Future<void> reachBallot(
  LiveVoterMachine machine,
  FakeVoterPort port,
  FakeTicker ticker,
) async {
  await reachPending(machine);
  port.admission = const LiveAdmission(options: ['Yes', 'No'], phase: 1);
  await ticker.tick();
  expect(machine.state, isA<LiveVoterBallotOpen>());
}

void main() {
  group('LiveVoterMachine', () {
    test('happy path: ticket → … → done, in order', () async {
      final port = FakeVoterPort();
      final ticker = FakeTicker();
      final machine = voterMachine(port: port, ticker: ticker);
      addTearDown(machine.dispose);

      final seen = <String>[];
      final sub = machine.states.listen((s) => seen.add(s.id));
      addTearDown(sub.cancel);

      expect(machine.state.id, 'liveVoter.needsTicket');

      await machine.advance(
        const LiveTicketProvided('tessera://live/0xp/vote?t=abc'),
      );
      await settle();
      final pending = machine.state as LiveVoterPending;
      // The code the voter shows the host comes from the announcement.
      expect(pending.confirmationCode, 'CODE-1');

      // Not admitted yet: a poll tick keeps waiting.
      await ticker.tick();
      expect(machine.state, isA<LiveVoterPending>());
      expect(port.pollCount, 1);

      // Host admits during registration → waitingForOpen (phase routed
      // automatically from the admission snapshot).
      port.admission = const LiveAdmission(options: ['Yes', 'No'], phase: 0);
      await ticker.tick();
      expect(machine.state, isA<LiveVoterWaitingForOpen>());

      // Chain watcher reports voting open → ballot.
      await machine.advance(const ExternalPhaseChanged(1));
      final ballot = machine.state as LiveVoterBallotOpen;
      expect(ballot.admission.options, ['Yes', 'No']);

      // Cast: proving → relaying → done (intermediate states are asserted
      // via the `seen` stream below — the fake effects settle immediately).
      await machine.advance(const LiveCastRequested(1));
      await settle();
      final done = machine.state as LiveVoterDone;
      expect(done.txHash, '0xfeed');
      expect(done.isTerminal, isTrue);
      expect(port.provedOption, 1);
      expect(port.relayedOption, 1);

      expect(seen, [
        'liveVoter.joining',
        'liveVoter.pending',
        'liveVoter.admitted',
        'liveVoter.waitingForOpen',
        'liveVoter.ballotOpen',
        'liveVoter.provingInProgress',
        'liveVoter.castInProgress',
        'liveVoter.done',
      ]);
    });

    test(
      'admission while voting is open goes straight to the ballot',
      () async {
        final port = FakeVoterPort();
        final ticker = FakeTicker();
        final machine = voterMachine(port: port, ticker: ticker);
        addTearDown(machine.dispose);

        await reachPending(machine);
        port.admission = const LiveAdmission(options: ['A', 'B'], phase: 1);
        await ticker.tick();
        expect(machine.state, isA<LiveVoterBallotOpen>());
      },
    );

    test(
      'pending timeout → stalled(pendingTimeout) → retry re-announces',
      () async {
        final port = FakeVoterPort();
        final ticker = FakeTicker();
        final machine = voterMachine(
          port: port,
          ticker: ticker,
          pendingTimeout: const Duration(seconds: 3),
        );
        addTearDown(machine.dispose);

        await reachPending(machine);

        // Two in-budget ticks poll; the third crosses the bound → stalled.
        await ticker.tick();
        await ticker.tick();
        expect(machine.state, isA<LiveVoterPending>());
        expect(port.pollCount, 2);

        await ticker.tick();
        final stalled = machine.state as LiveVoterStalled;
        expect(stalled.reason, LiveVoterStallReason.pendingTimeout);
        expect(stalled.messageKey, 'error.liveVoter.pendingTimeout');
        expect(stalled.recoveryEvent, isA<Retry>());
        expect(stalled.nextAction!.type, NextActionType.retry);

        // Retry re-announces with the same raw ticket: fresh code, fresh
        // bounded wait.
        await machine.advance(const Retry());
        await settle();
        final pending = machine.state as LiveVoterPending;
        expect(pending.confirmationCode, 'CODE-2');
        expect(port.announceCount, 2);
      },
    );

    test('host gone → stalled(hostGone); rescan and leave both exit', () async {
      final port = FakeVoterPort();
      final ticker = FakeTicker();
      final machine = voterMachine(port: port, ticker: ticker);
      addTearDown(machine.dispose);

      await reachPending(machine);
      port.alive = false;
      await ticker.tick();

      final stalled = machine.state as LiveVoterStalled;
      expect(stalled.reason, LiveVoterStallReason.hostGone);
      expect(stalled.messageKey, 'error.liveVoter.hostGone');

      // Rescan returns to the ticket entry…
      await machine.advance(const LiveRescanRequested());
      expect(machine.state, isA<LiveVoterNeedsTicket>());

      // …and from a fresh stall, leave is terminal.
      port.alive = false;
      await reachPending(machine);
      await ticker.tick();
      expect(machine.state, isA<LiveVoterStalled>());
      await machine.advance(const LiveLeaveRequested());
      expect(machine.state, isA<LiveVoterLeft>());
      expect(machine.state.isTerminal, isTrue);
    });

    test(
      'transient poll errors keep waiting; the timeout still bounds',
      () async {
        final port = FakeVoterPort();
        final ticker = FakeTicker();
        final machine = voterMachine(
          port: port,
          ticker: ticker,
          pendingTimeout: const Duration(seconds: 2),
        );
        addTearDown(machine.dispose);

        await reachPending(machine);
        port.pollError = StateError('network blip');
        await ticker.tick();
        expect(machine.state, isA<LiveVoterPending>()); // blip swallowed
        await ticker.tick(); // 2s >= 2s → bounded
        expect(
          (machine.state as LiveVoterStalled).reason,
          LiveVoterStallReason.pendingTimeout,
        );
      },
    );

    test('leaving pending cancels the ticker subscription and token', () async {
      final port = FakeVoterPort();
      final ticker = FakeTicker();
      final machine = voterMachine(port: port, ticker: ticker);
      addTearDown(machine.dispose);

      await reachPending(machine);
      final pending = machine.state as LiveVoterPending;
      final handle = ticker.active;
      expect(handle.cancelled, isFalse);

      port.admission = const LiveAdmission(options: ['A'], phase: 0);
      await ticker.tick();
      expect(machine.state, isA<LiveVoterWaitingForOpen>());
      expect(pending.cancellation.isCancelled, isTrue);
      expect(handle.cancelled, isTrue);
      expect(ticker.liveCount, 0);
    });

    test('dispose while pending cancels the cadence', () async {
      final port = FakeVoterPort();
      final ticker = FakeTicker();
      final machine = voterMachine(port: port, ticker: ticker);

      await reachPending(machine);
      final pending = machine.state as LiveVoterPending;
      machine.dispose();
      await settle();
      expect(pending.cancellation.isCancelled, isTrue);
      expect(ticker.liveCount, 0);
    });

    test('join failure → typed error state → retry succeeds', () async {
      final port = FakeVoterPort();
      final ticker = FakeTicker();
      final machine = voterMachine(port: port, ticker: ticker);
      addTearDown(machine.dispose);

      port.announceError = StateError('relayer rejected ticket');
      await machine.advance(const LiveTicketProvided('bad-day-ticket'));
      await settle();

      final failed = machine.state as LiveVoterJoinFailed;
      expect(failed.cause, isA<StateError>());
      expect(failed.recoveryEvent, isA<Retry>());

      await machine.advance(failed.recoveryEvent);
      await settle();
      expect(machine.state, isA<LiveVoterPending>());
    });

    test(
      'proving failure → castFailed → retry returns to the ballot',
      () async {
        final port = FakeVoterPort();
        final ticker = FakeTicker();
        final machine = voterMachine(port: port, ticker: ticker);
        addTearDown(machine.dispose);

        await reachBallot(machine, port, ticker);
        port.proofError = StateError('prover crashed');
        await machine.advance(const LiveCastRequested(0));
        await settle();

        final failed = machine.state as LiveVoterCastFailed;
        expect(failed.messageKey, 'error.liveVoter.castFailed');

        await machine.advance(const Retry());
        expect(machine.state, isA<LiveVoterBallotOpen>());

        // And the retried cast completes.
        await machine.advance(const LiveCastRequested(0));
        await settle();
        expect(machine.state, isA<LiveVoterDone>());
      },
    );

    test('poll ends mid-wait → stalled(pollEnded) is leave-only', () async {
      final port = FakeVoterPort();
      final ticker = FakeTicker();
      final machine = voterMachine(port: port, ticker: ticker);
      addTearDown(machine.dispose);

      await reachPending(machine);
      port.admission = const LiveAdmission(options: ['A'], phase: 0);
      await ticker.tick();
      expect(machine.state, isA<LiveVoterWaitingForOpen>());

      await machine.advance(const ExternalPhaseChanged(2));
      final stalled = machine.state as LiveVoterStalled;
      expect(stalled.reason, LiveVoterStallReason.pollEnded);
      expect(stalled.nextAction!.type, NextActionType.navigate);
      expect(stalled.nextAction!.labelKey, 'action.leave');
      expect(stalled.recoveryEvent, isA<LiveLeaveRequested>());

      // Retrying into an ended poll is impossible, not discouraged.
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
    });

    test('illegal orderings throw JourneyViolation', () async {
      final port = FakeVoterPort();
      final ticker = FakeTicker();
      final machine = voterMachine(port: port, ticker: ticker);
      addTearDown(machine.dispose);

      // Empty ticket is guard-rejected at the door.
      await expectLater(
        machine.advance(const LiveTicketProvided('   ')),
        throwsA(
          isA<JourneyViolation>().having(
            (v) => v.guardRejected,
            'guardRejected',
            isTrue,
          ),
        ),
      );

      // Casting before admission is unrepresentable.
      await reachPending(machine);
      await expectLater(
        machine.advance(const LiveCastRequested(0)),
        throwsA(isA<JourneyViolation>()),
      );

      // A second ticket mid-wait is unrepresentable.
      await expectLater(
        machine.advance(const LiveTicketProvided('another')),
        throwsA(isA<JourneyViolation>()),
      );

      // Finish the journey; terminal accepts nothing.
      port.admission = const LiveAdmission(options: ['A'], phase: 1);
      await ticker.tick();
      await machine.advance(const LiveCastRequested(0));
      await settle();
      expect(machine.state, isA<LiveVoterDone>());
      await expectLater(
        machine.advance(const Refresh()),
        throwsA(isA<JourneyViolation>()),
      );
    });

    test('a device that cannot prove is guard-blocked from casting', () async {
      final port = FakeVoterPort();
      final ticker = FakeTicker();
      final machine = voterMachine(
        port: port,
        ticker: ticker,
        capabilities: Capabilities.none.copyWith(canScanQr: true),
      );
      addTearDown(machine.dispose);

      await reachBallot(machine, port, ticker);
      final ballot = machine.state as LiveVoterBallotOpen;
      // Honest surface: the action is disabled WITH a reason…
      expect(ballot.nextAction!.enabled, isFalse);
      expect(ballot.nextAction!.disabledReasonKey, 'reason.deviceCannotProve');

      // …and the transition is impossible regardless of the UI.
      await expectLater(
        machine.advance(const LiveCastRequested(0)),
        throwsA(
          isA<JourneyViolation>().having(
            (v) => v.guardRejected,
            'guardRejected',
            isTrue,
          ),
        ),
      );
    });

    test('NextAction per state: scan vs paste, waits, retries', () async {
      expect(
        const LiveVoterNeedsTicket(Capabilities.none).nextAction!.labelKey,
        'action.pasteTicket',
      );
      final scanner = Capabilities.none.copyWith(canScanQr: true);
      expect(
        LiveVoterNeedsTicket(scanner).nextAction!.labelKey,
        'action.scanTicket',
      );

      final port = FakeVoterPort();
      final ticker = FakeTicker();
      final machine = voterMachine(port: port, ticker: ticker);
      addTearDown(machine.dispose);

      await machine.advance(const LiveTicketProvided('t'));
      expect(machine.state.nextAction!.type, NextActionType.wait);
      await settle();
      expect(machine.state.nextAction!.labelKey, 'action.waitingForHost');
      expect(machine.state.nextAction!.type, NextActionType.wait);

      port.admission = const LiveAdmission(options: ['A'], phase: 1);
      await ticker.tick();
      final ballot = machine.state as LiveVoterBallotOpen;
      expect(ballot.nextAction!.labelKey, 'action.castVote');
      expect(ballot.nextAction!.enabled, isTrue);

      await machine.advance(const LiveCastRequested(0));
      await settle();
      expect(machine.state.nextAction, isNull); // done: router shows receipt
    });
  });

  group('LiveHostMachine', () {
    test(
      'loads into sessionOpen with a minted ticket and empty queue',
      () async {
        final port = FakeHostPort();
        final ticker = FakeTicker();
        final machine = LiveHostMachine(port: port, ticker: ticker);
        addTearDown(machine.dispose);

        expect(machine.state.id, 'liveHost.loading');
        await settle();
        final session = machine.state as LiveHostSessionOpen;
        expect(session.ticket, 'T1');
        expect(session.queue.pending, isEmpty);
        // No one admitted yet: start-voting is honestly disabled.
        expect(session.nextAction!.labelKey, 'action.startVoting');
        expect(session.nextAction!.enabled, isFalse);
        expect(
          session.nextAction!.disabledReasonKey,
          'reason.liveHost.noAdmittedVoters',
        );
      },
    );

    test('ticket rotates on the machine-owned cadence', () async {
      final port = FakeHostPort();
      final ticker = FakeTicker();
      final machine = LiveHostMachine(
        port: port,
        ticker: ticker,
        pollInterval: const Duration(seconds: 1),
        rotateEvery: const Duration(seconds: 3),
      );
      addTearDown(machine.dispose);
      await settle();
      expect(machine.rotateTicks, 3);
      expect((machine.state as LiveHostSessionOpen).ticket, 'T1');

      await ticker.tick(); // countdown 3 → 2
      await ticker.tick(); // 2 → 1
      expect((machine.state as LiveHostSessionOpen).ticket, 'T1');
      expect(port.ticketCount, 1);

      await ticker.tick(); // due → fresh ticket, countdown reset
      final rotated = machine.state as LiveHostSessionOpen;
      expect(rotated.ticket, 'T2');
      expect(rotated.ticksUntilRotate, 3);
      expect(port.ticketCount, 2);
    });

    test(
      'queue refreshes on tick (admit-queue submachine sees arrivals)',
      () async {
        final port = FakeHostPort();
        final ticker = FakeTicker();
        final machine = LiveHostMachine(port: port, ticker: ticker);
        addTearDown(machine.dispose);
        await settle();

        port.queueResponse = const AdmitQueue(
          pending: [
            PendingLiveVoter(commitment: '0xc1', confirmationCode: 'AB12'),
          ],
          admitted: 0,
        );
        await ticker.tick();
        final session = machine.state as LiveHostSessionOpen;
        expect(session.queue.pending, hasLength(1));
        expect(session.queue.pending.single.confirmationCode, 'AB12');
      },
    );

    test('admit → start → close: the one legal ordering, end to end', () async {
      final port = FakeHostPort()
        ..queueResponse = const AdmitQueue(
          pending: [
            PendingLiveVoter(commitment: '0xc1', confirmationCode: 'AB12'),
          ],
          admitted: 0,
        );
      final ticker = FakeTicker();
      final machine = LiveHostMachine(port: port, ticker: ticker);
      addTearDown(machine.dispose);

      final seen = <String>[];
      final sub = machine.states.listen((s) => seen.add(s.id));
      addTearDown(sub.cancel);
      await settle();

      // Admit: confirm the code shown face to face.
      await machine.advance(const LiveHostConfirmRequested('AB12'));
      await settle();
      final admittedSession = machine.state as LiveHostSessionOpen;
      expect(port.confirmedCodes, ['AB12']);
      expect(admittedSession.queue.admitted, 1);
      expect(admittedSession.queue.pending, isEmpty);
      expect(admittedSession.nextAction!.enabled, isTrue);

      // Start voting (only legal from sessionOpen, ≥1 admitted).
      await machine.advance(const LiveHostStartVotingRequested());
      await settle();
      expect(port.startCalled, isTrue);
      var voting = machine.state as LiveHostVotingOpen;
      expect(voting.admitted, 1);
      expect(voting.turnout, 0);
      expect(voting.nextAction!.labelKey, 'action.closeVoting');

      // Turnout heartbeat.
      port.queueResponse = const AdmitQueue(
        pending: [],
        admitted: 1,
        turnout: 1,
      );
      await ticker.tick();
      voting = machine.state as LiveHostVotingOpen;
      expect(voting.turnout, 1);

      // Close (only legal from votingOpen) → terminal.
      await machine.advance(const LiveHostCloseRequested());
      await settle();
      expect(port.closeCalled, isTrue);
      final closed = machine.state as LiveHostClosed;
      expect(closed.turnout, 1);
      expect(closed.isTerminal, isTrue);
      expect(closed.nextAction, isNull);

      await expectLater(
        machine.advance(const Refresh()),
        throwsA(isA<JourneyViolation>()),
      );

      // The full ordering, including the in-progress effect states.
      expect(seen, [
        'liveHost.sessionOpen',
        'liveHost.confirming',
        'liveHost.sessionOpen',
        'liveHost.startingVoting',
        'liveHost.votingOpen',
        'liveHost.votingOpen', // turnout heartbeat tick
        'liveHost.closing',
        'liveHost.closed',
      ]);
    });

    test('illegal phase orderings are impossible', () async {
      final port = FakeHostPort()
        ..queueResponse = const AdmitQueue(
          pending: [
            PendingLiveVoter(commitment: '0xc1', confirmationCode: 'AB12'),
          ],
          admitted: 0,
        );
      final ticker = FakeTicker();
      final machine = LiveHostMachine(port: port, ticker: ticker);
      addTearDown(machine.dispose);
      await settle();

      // Start with zero admitted: guard-rejected.
      await expectLater(
        machine.advance(const LiveHostStartVotingRequested()),
        throwsA(
          isA<JourneyViolation>().having(
            (v) => v.guardRejected,
            'guardRejected',
            isTrue,
          ),
        ),
      );

      // Close before voting opened: no such row.
      await expectLater(
        machine.advance(const LiveHostCloseRequested()),
        throwsA(isA<JourneyViolation>()),
      );

      // Confirming a code that is not in the pending queue: guard-rejected.
      await expectLater(
        machine.advance(const LiveHostConfirmRequested('ZZZZ')),
        throwsA(
          isA<JourneyViolation>().having(
            (v) => v.guardRejected,
            'guardRejected',
            isTrue,
          ),
        ),
      );

      // Walk to votingOpen; session-phase actions are now impossible.
      await machine.advance(const LiveHostConfirmRequested('AB12'));
      await settle();
      await machine.advance(const LiveHostStartVotingRequested());
      await settle();
      expect(machine.state, isA<LiveHostVotingOpen>());

      await expectLater(
        machine.advance(const LiveHostStartVotingRequested()),
        throwsA(isA<JourneyViolation>()),
      );
      await expectLater(
        machine.advance(const LiveHostConfirmRequested('AB12')),
        throwsA(isA<JourneyViolation>()),
      );
    });

    test('leaving sessionOpen cancels its ticker subscription', () async {
      final port = FakeHostPort()
        ..queueResponse = const AdmitQueue(pending: [], admitted: 1);
      final ticker = FakeTicker();
      final machine = LiveHostMachine(port: port, ticker: ticker);
      addTearDown(machine.dispose);
      await settle();

      final session = machine.state as LiveHostSessionOpen;
      final handle = ticker.active;
      expect(handle.cancelled, isFalse);

      await machine.advance(const LiveHostStartVotingRequested());
      await settle();
      expect(session.cancellation.isCancelled, isTrue);
      expect(handle.cancelled, isTrue);
      // Exactly one live cadence remains: the votingOpen turnout heartbeat.
      expect(machine.state, isA<LiveHostVotingOpen>());
      expect(ticker.liveCount, 1);
    });

    test('dispose cancels the session cadence', () async {
      final port = FakeHostPort();
      final ticker = FakeTicker();
      final machine = LiveHostMachine(port: port, ticker: ticker);
      await settle();
      expect(ticker.liveCount, 1);

      machine.dispose();
      await settle();
      expect(ticker.liveCount, 0);
    });

    test('load failure → typed failed state → retry recovers', () async {
      final port = FakeHostPort()..loadError = StateError('no keypair');
      final ticker = FakeTicker();
      final machine = LiveHostMachine(port: port, ticker: ticker);
      addTearDown(machine.dispose);
      await settle();

      final failed = machine.state as LiveHostFailed;
      expect(failed.action, LiveHostFailedAction.load);
      expect(failed.messageKey, 'error.liveHost.loadFailed');
      expect(failed.nextAction!.type, NextActionType.retry);

      await machine.advance(failed.recoveryEvent);
      await settle();
      expect(machine.state, isA<LiveHostSessionOpen>());
    });

    test('confirm failure → typed failed state → retry re-confirms', () async {
      final port = FakeHostPort()
        ..queueResponse = const AdmitQueue(
          pending: [
            PendingLiveVoter(commitment: '0xc1', confirmationCode: 'AB12'),
          ],
          admitted: 0,
        )
        ..confirmError = StateError('tx reverted');
      final ticker = FakeTicker();
      final machine = LiveHostMachine(port: port, ticker: ticker);
      addTearDown(machine.dispose);
      await settle();

      await machine.advance(const LiveHostConfirmRequested('AB12'));
      await settle();
      final failed = machine.state as LiveHostFailed;
      expect(failed.action, LiveHostFailedAction.confirm);
      expect(failed.confirmationCode, 'AB12');

      await machine.advance(const Retry());
      await settle();
      final session = machine.state as LiveHostSessionOpen;
      expect(session.queue.admitted, 1);
      expect(port.confirmedCodes, ['AB12']);
    });
  });
}
