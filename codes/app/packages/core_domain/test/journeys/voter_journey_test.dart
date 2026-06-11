import 'dart:async';

import 'package:core_domain/journeys/capabilities.dart';
import 'package:core_domain/journeys/journey.dart';
import 'package:core_domain/journeys/policy.dart';
import 'package:core_domain/journeys/voter_journey.dart';
import 'package:core_domain/models/poll_snapshot.dart';
import 'package:core_domain/models/relay_proof.dart';
// `hide`: the journey contract's Retry/Timeout events share names with
// package:test configuration types we don't use here.
import 'package:test/test.dart' hide Retry, Timeout;

/// Drains the event queue so fire-and-forget effect completions land.
Future<void> settle() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

VoterPollView makeView({
  int phase = 1,
  int options = 3,
  VoterModule module = VoterModule.anon,
  ResultsPolicy policy = ResultsPolicy.sealedUntilClose,
  List<BigInt>? results,
}) {
  return VoterPollView(
    snapshot: PollSnapshot(
      address: '0xpoll',
      state: phase,
      options: List.generate(options, (i) => 'Option $i'),
      results: results ?? List<BigInt>.filled(options, BigInt.zero),
      owner: '0xowner',
      participantCount: BigInt.two,
    ),
    module: module,
    resultsPolicy: policy,
  );
}

/// A proving, relayer-backed device (the normal voter configuration).
final Capabilities proverCaps = Capabilities.none.copyWith(
  canProve: true,
  relayerAvailable: true,
);

/// A browse-only device: cannot prove.
final Capabilities browseCaps = Capabilities.none.copyWith(
  relayerAvailable: true,
  reasons: const {Capability.prove: 'reason.deviceCannotProve'},
);

final class FakeVoterPort implements VoterJourneyPort {
  FakeVoterPort({required this.view});

  /// What [fetchSnapshot] returns next (mutable: tests move chain truth).
  VoterPollView view;

  bool eligible = true;
  Object? fetchError;
  Object? eligibilityError;
  Object? joinError;
  Object? proofError;
  Object? relayError;

  /// When set, [generateProof] blocks on it (for cancellation tests).
  Completer<void>? proofGate;

  VoterReceipt receipt = const VoterReceipt(
    nullifier: '0xnullifier',
    txHash: '0xtxhash',
  );

  final List<String> calls = [];
  BallotSpec? provedSpec;
  BallotSpec? relayedSpec;
  RelayProof? relayedProof;
  int proveCount = 0;
  int relayCount = 0;

  static const RelayProof proof = RelayProof(
    merkleTreeDepth: 1,
    merkleTreeRoot: '1',
    nullifier: '0xnullifier',
    message: '0',
    scope: '0xpoll',
    points: [],
  );

  @override
  Future<VoterPollView> fetchSnapshot() async {
    calls.add('fetchSnapshot');
    if (fetchError != null) throw fetchError!;
    return view;
  }

  @override
  Future<bool> checkEligibility(VoterPollView view) async {
    calls.add('checkEligibility');
    if (eligibilityError != null) throw eligibilityError!;
    return eligible;
  }

  @override
  Future<void> requestJoin(VoterPollView view) async {
    calls.add('requestJoin');
    if (joinError != null) throw joinError!;
  }

  @override
  Future<RelayProof> generateProof(
    BallotSpec spec,
    VoterPollView view,
    CancellationToken cancellation,
  ) async {
    calls.add('generateProof');
    proveCount++;
    provedSpec = spec;
    final gate = proofGate;
    if (gate != null) await gate.future;
    if (proofError != null) throw proofError!;
    return proof;
  }

  @override
  Future<VoterReceipt> relayBallot(
    BallotSpec spec,
    RelayProof proof,
    VoterPollView view,
    CancellationToken cancellation,
  ) async {
    calls.add('relayBallot');
    relayCount++;
    relayedSpec = spec;
    relayedProof = proof;
    if (relayError != null) throw relayError!;
    return receipt;
  }
}

Future<(VoterJourneyMachine, FakeVoterPort)> machineAt({
  required VoterPollView view,
  Capabilities? capabilities,
  bool eligible = true,
}) async {
  final port = FakeVoterPort(view: view)..eligible = eligible;
  final machine = VoterJourneyMachine(
    port: port,
    capabilities: capabilities ?? proverCaps,
  );
  addTearDown(machine.dispose);
  await settle();
  return (machine, port);
}

void main() {
  group('BallotSpec validity', () {
    test('SingleChoice: index must be in range', () {
      expect(const SingleChoice(0).isValidFor(3), isTrue);
      expect(const SingleChoice(2).isValidFor(3), isTrue);
      expect(const SingleChoice(3).isValidFor(3), isFalse);
      expect(const SingleChoice(-1).isValidFor(3), isFalse);
      expect(const SingleChoice(1).module, VoterModule.anon);
    });

    test('Approval: non-empty bitmask, no out-of-range bits', () {
      expect(Approval(BigInt.from(0x5)).isValidFor(3), isTrue);
      expect(Approval(BigInt.from(0x7)).isValidFor(3), isTrue);
      expect(Approval(BigInt.zero).isValidFor(3), isFalse);
      expect(Approval(BigInt.from(0x8)).isValidFor(3), isFalse);
      expect(Approval(BigInt.one).module, VoterModule.approval);
    });

    test('Ranked: non-empty prefix of distinct in-range options', () {
      expect(Ranked([2, 0]).isValidFor(3), isTrue);
      expect(Ranked([0, 1, 2]).isValidFor(3), isTrue);
      expect(Ranked([]).isValidFor(3), isFalse);
      expect(Ranked([0, 0]).isValidFor(3), isFalse, reason: 'duplicate');
      expect(Ranked([3]).isValidFor(3), isFalse, reason: 'out of range');
      expect(Ranked([0, 1, 2, 0]).isValidFor(3), isFalse, reason: 'too long');
      expect(Ranked([0]).module, VoterModule.ranked);
    });

    test('Quadratic: budget Σv² ≤ 100, slot cap 15, not all-zero', () {
      expect(Quadratic([10, 0, 0]).isValidFor(3), isTrue);
      expect(Quadratic([6, 8, 0]).isValidFor(3), isTrue);
      expect(Quadratic([5, 5, 5]).isValidFor(3), isTrue);
      expect(Quadratic([0, 0, 0]).isValidFor(3), isFalse, reason: 'empty');
      expect(Quadratic([10, 1, 0]).isValidFor(3), isFalse, reason: '>100');
      expect(Quadratic([16]).isValidFor(3), isFalse, reason: 'slot cap');
      expect(Quadratic([1, 1, 1, 1]).isValidFor(3), isFalse);
      expect(Quadratic([1]).module, VoterModule.quadratic);
    });

    test('Survey: one non-negative answer per question', () {
      expect(Survey([BigInt.two, BigInt.from(5)]).isValidFor(2), isTrue);
      expect(Survey([BigInt.two]).isValidFor(2), isFalse, reason: 'length');
      expect(Survey([]).isValidFor(0), isFalse);
      expect(Survey([BigInt.from(-1), BigInt.one]).isValidFor(2), isFalse);
      expect(Survey([BigInt.one]).module, VoterModule.survey);
    });
  });

  group('happy path per module', () {
    final cases = <(VoterModule, BallotSpec)>[
      (VoterModule.anon, const SingleChoice(1)),
      (VoterModule.approval, Approval(BigInt.from(0x5))),
      (VoterModule.ranked, Ranked([2, 0])),
      (VoterModule.quadratic, Quadratic([6, 8, 0])),
      (VoterModule.survey, Survey([BigInt.two, BigInt.from(5), BigInt.zero])),
    ];

    for (final (module, spec) in cases) {
      test('${module.name}: load → ballot → prove → cast → receipt', () async {
        final (machine, port) = await machineAt(
          view: makeView(phase: 1, module: module),
        );

        // Eligible + voting + proving device → the ballot, no detours.
        expect(machine.state, isA<VoterBallotOpen>());
        expect(machine.state.id, 'voter.ballotOpen');

        await machine.advance(VoterBallotEdited(spec));
        expect((machine.state as VoterBallotOpen).draft, spec);
        expect(machine.state.nextAction!.enabled, isTrue);

        // The fake effects complete in microtasks, so assert the proving →
        // casting sequence from the states stream rather than polling.
        final seen = <String>[];
        final sub = machine.states.listen((s) => seen.add(s.id));
        addTearDown(sub.cancel);

        await machine.advance(const VoterBallotSubmitted());
        await settle();
        expect(seen, [
          'voter.provingInProgress',
          'voter.castInProgress',
          'voter.castSucceeded', // refreshed: false (cast landed)
          'voter.castSucceeded', // refreshed: true (auto-refresh)
        ]);

        final done = machine.state as VoterCastSucceeded;
        expect(done.receipt, port.receipt);
        expect(done.refreshed, isTrue, reason: 'auto-refresh completed');
        expect(port.provedSpec, spec);
        expect(port.relayedSpec, spec);
        expect(port.relayedProof, FakeVoterPort.proof);

        await machine.advance(const VoterReceiptAcknowledged());
        final saved = machine.state as VoterReceiptSaved;
        expect(saved.receipt.nullifier, '0xnullifier');
        expect(saved.receipt.txHash, '0xtxhash');

        // Default policy + voting still open → sealed, honestly.
        await machine.advance(const VoterResultsRequested());
        expect(machine.state, isA<VoterResultsSealed>());
      });
    }

    test(
      'livePublic policy: receipt → results visible during voting',
      () async {
        final (machine, _) = await machineAt(
          view: makeView(phase: 1, policy: ResultsPolicy.livePublic),
        );
        await machine.advance(const VoterBallotEdited(SingleChoice(0)));
        await machine.advance(const VoterBallotSubmitted());
        await settle();
        await machine.advance(const VoterReceiptAcknowledged());
        await machine.advance(const VoterResultsRequested());
        expect(machine.state, isA<VoterResultsVisible>());
      },
    );
  });

  group('phase gating: the ballot is unreachable outside voting', () {
    test(
      'registration phase → waitingForOpen, ballot events violate',
      () async {
        final (machine, _) = await machineAt(view: makeView(phase: 0));

        final waiting = machine.state as VoterWaitingForOpen;
        expect(waiting.blockedReasonKey, isNull);
        expect(waiting.nextAction!.type, NextActionType.wait);

        // Forcing ballot events from outside the ballot is a violation.
        await expectLater(
          machine.advance(const VoterBallotSubmitted()),
          throwsA(isA<JourneyViolation>()),
        );
        await expectLater(
          machine.advance(const VoterBallotEdited(SingleChoice(0))),
          throwsA(isA<JourneyViolation>()),
        );
        expect(machine.state, isA<VoterWaitingForOpen>());
      },
    );

    test(
      'ended phase at load → results, never a ballot or eligibility check',
      () async {
        final (machine, port) = await machineAt(view: makeView(phase: 2));

        expect(machine.state, isA<VoterResultsVisible>());
        expect(machine.state.isTerminal, isTrue);
        expect(port.calls, isNot(contains('checkEligibility')));
      },
    );

    test(
      'voting opens (ExternalPhaseChanged) → ballot on a proving device',
      () async {
        final (machine, _) = await machineAt(view: makeView(phase: 0));
        expect(machine.state, isA<VoterWaitingForOpen>());

        await machine.advance(const ExternalPhaseChanged(1));
        final open = machine.state as VoterBallotOpen;
        expect(open.view.phase, 1);
        expect(open.draft, isNull);
      },
    );

    test(
      'non-proving device never reaches the ballot; reason is honest',
      () async {
        final (machine, _) = await machineAt(
          view: makeView(phase: 1),
          capabilities: browseCaps,
        );

        // Eligible, voting open — but this device cannot prove.
        final waiting = machine.state as VoterWaitingForOpen;
        expect(waiting.blockedReasonKey, 'reason.deviceCannotProve');
        expect(waiting.nextAction!.enabled, isFalse);
        expect(
          waiting.nextAction!.disabledReasonKey,
          'reason.deviceCannotProve',
        );

        // Phase events keep it out of the ballot too.
        await machine.advance(const ExternalPhaseChanged(1));
        expect(machine.state, isA<VoterWaitingForOpen>());
      },
    );

    test(
      'voting ends while on the ballot → results, draft abandoned',
      () async {
        final (machine, _) = await machineAt(view: makeView(phase: 1));
        await machine.advance(const VoterBallotEdited(SingleChoice(1)));

        await machine.advance(const ExternalPhaseChanged(2));
        expect(machine.state, isA<VoterResultsVisible>());
      },
    );

    test('submit without a selection is guard-rejected', () async {
      final (machine, _) = await machineAt(view: makeView(phase: 1));
      expect(machine.state.nextAction!.disabledReasonKey, 'reason.noSelection');

      await expectLater(
        machine.advance(const VoterBallotSubmitted()),
        throwsA(
          isA<JourneyViolation>().having(
            (v) => v.guardRejected,
            'guardRejected',
            isTrue,
          ),
        ),
      );
      expect(machine.state, isA<VoterBallotOpen>());
    });

    test('a payload of the wrong module is guard-rejected', () async {
      final (machine, _) = await machineAt(
        view: makeView(phase: 1, module: VoterModule.approval),
      );

      await expectLater(
        machine.advance(const VoterBallotEdited(SingleChoice(0))),
        throwsA(
          isA<JourneyViolation>().having(
            (v) => v.guardRejected,
            'guardRejected',
            isTrue,
          ),
        ),
      );

      // An invalid payload of the right module is rejected too.
      await expectLater(
        machine.advance(VoterBallotEdited(Approval(BigInt.zero))),
        throwsA(isA<JourneyViolation>()),
      );
      expect((machine.state as VoterBallotOpen).draft, isNull);
    });
  });

  group('join flow', () {
    test('not eligible → join → pending → recheck loop → confirmed', () async {
      final (machine, port) = await machineAt(
        view: makeView(phase: 0),
        eligible: false,
      );

      final notEligible = machine.state as VoterNotEligible;
      expect(notEligible.canRequestJoin, isTrue);
      expect(notEligible.nextAction!.enabled, isTrue);

      await machine.advance(const VoterRequestJoin());
      await settle();
      expect(machine.state, isA<VoterJoinPending>());

      // Recheck: still not confirmed on-chain → typed pending error.
      await machine.advance(const Refresh());
      await settle();
      final pending = machine.state as VoterRegistrationStillPending;
      expect(pending.recoveryEvent, isA<Refresh>());
      expect(pending.messageKey, 'error.registrationStillPending');

      // Recheck again once the chain caught up → eligible landing.
      port.eligible = true;
      await machine.advance(pending.recoveryEvent);
      await settle();
      expect(machine.state, isA<VoterWaitingForOpen>());
      expect(
        port.calls.where((c) => c == 'checkEligibility').length,
        3,
        reason: 'initial + two rechecks',
      );
    });

    test('join failure → typed error → Retry re-joins', () async {
      final (machine, port) = await machineAt(
        view: makeView(phase: 0),
        eligible: false,
      );
      port.joinError = StateError('relayer down');

      await machine.advance(const VoterRequestJoin());
      await settle();
      final failed = machine.state as VoterJoinFailed;
      expect(failed.messageKey, 'error.joinFailed');
      expect(failed.cause, isA<StateError>());

      port.joinError = null;
      await machine.advance(failed.recoveryEvent);
      await settle();
      expect(machine.state, isA<VoterJoinPending>());
    });

    test('join is honestly disabled when registration is closed', () async {
      final (machine, _) = await machineAt(
        view: makeView(phase: 1),
        eligible: false,
      );

      final notEligible = machine.state as VoterNotEligible;
      expect(notEligible.canRequestJoin, isFalse);
      expect(
        notEligible.nextAction!.disabledReasonKey,
        'reason.registrationClosed',
      );

      await expectLater(
        machine.advance(const VoterRequestJoin()),
        throwsA(
          isA<JourneyViolation>().having(
            (v) => v.guardRejected,
            'guardRejected',
            isTrue,
          ),
        ),
      );
    });

    test('join is honestly disabled without a relayer', () async {
      final (machine, _) = await machineAt(
        view: makeView(phase: 0),
        capabilities: proverCaps.copyWith(relayerAvailable: false),
        eligible: false,
      );

      final notEligible = machine.state as VoterNotEligible;
      expect(notEligible.canRequestJoin, isFalse);
      expect(
        notEligible.nextAction!.disabledReasonKey,
        'reason.relayerUnavailable',
      );
    });
  });

  group('proving', () {
    test(
      'proof failure → typed error → Retry resumes with the same ballot',
      () async {
        final (machine, port) = await machineAt(view: makeView(phase: 1));
        port.proofError = StateError('prover crashed');

        await machine.advance(const VoterBallotEdited(SingleChoice(2)));
        await machine.advance(const VoterBallotSubmitted());
        await settle();

        final failed = machine.state as VoterProofFailed;
        expect(failed.messageKey, 'error.proofFailed');
        expect(failed.spec, const SingleChoice(2));
        expect(failed.cause, isA<StateError>());

        port.proofError = null;
        await machine.advance(failed.recoveryEvent);
        await settle();

        expect(machine.state, isA<VoterCastSucceeded>());
        expect(port.proveCount, 2);
        expect(port.provedSpec, const SingleChoice(2));
        expect(port.relayCount, 1);
      },
    );

    test(
      'cancellation during proving → ballot with draft, no late writes',
      () async {
        final (machine, port) = await machineAt(view: makeView(phase: 1));
        port.proofGate = Completer<void>();

        await machine.advance(const VoterBallotEdited(SingleChoice(1)));
        await machine.advance(const VoterBallotSubmitted());
        final proving = machine.state as VoterProvingInProgress;
        expect(proving.nextAction!.labelKey, 'action.cancel');
        expect(proving.cancellation.isCancelled, isFalse);

        await machine.advance(const VoterProvingCancelled());
        final open = machine.state as VoterBallotOpen;
        expect(open.draft, const SingleChoice(1), reason: 'draft preserved');
        expect(
          proving.cancellation.isCancelled,
          isTrue,
          reason: 'leaving the state cancels its token',
        );

        // The abandoned prover finishing later can never write back.
        port.proofGate!.complete();
        await settle();
        expect(machine.state, same(open));
        expect(port.relayCount, 0);
      },
    );
  });

  group('casting', () {
    test(
      'relay failure → typed error → Retry re-relays the SAME proof',
      () async {
        final (machine, port) = await machineAt(view: makeView(phase: 1));
        port.relayError = StateError('relayer 502');

        await machine.advance(const VoterBallotEdited(SingleChoice(0)));
        await machine.advance(const VoterBallotSubmitted());
        await settle();

        final failed = machine.state as VoterRelayFailed;
        expect(failed.messageKey, 'error.relayFailed');
        expect(failed.proof, FakeVoterPort.proof);

        port.relayError = null;
        await machine.advance(failed.recoveryEvent);
        await settle();

        expect(machine.state, isA<VoterCastSucceeded>());
        expect(port.proveCount, 1, reason: 'no re-proving on relay retry');
        expect(port.relayCount, 2);
      },
    );

    test(
      'cast success AUTO-refreshes the snapshot (relay before fetch)',
      () async {
        final (machine, port) = await machineAt(view: makeView(phase: 1));

        await machine.advance(const VoterBallotEdited(SingleChoice(0)));
        // Chain truth moves while we vote: the refresh must pick this up.
        port.view = makeView(
          phase: 1,
          results: [BigInt.from(7), BigInt.zero, BigInt.zero],
        );
        await machine.advance(const VoterBallotSubmitted());
        await settle();

        final done = machine.state as VoterCastSucceeded;
        expect(done.refreshed, isTrue);
        expect(
          done.view.snapshot.results.first,
          BigInt.from(7),
          reason: 'castSucceeded carries the POST-cast snapshot, never stale',
        );

        // Ordering: the machine refreshed after the relay, automatically.
        expect(port.calls, [
          'fetchSnapshot',
          'checkEligibility',
          'generateProof',
          'relayBallot',
          'fetchSnapshot',
        ]);
      },
    );

    test(
      'refresh failure after cast is non-fatal: receipt path still works',
      () async {
        final (machine, port) = await machineAt(view: makeView(phase: 1));

        await machine.advance(const VoterBallotEdited(SingleChoice(0)));
        port.fetchError = StateError('rpc flake');
        await machine.advance(const VoterBallotSubmitted());
        await settle();

        final done = machine.state as VoterCastSucceeded;
        expect(done.refreshed, isTrue, reason: 'loop stops; view kept');
        expect(done.receipt, port.receipt);

        await machine.advance(const VoterReceiptAcknowledged());
        expect(machine.state, isA<VoterReceiptSaved>());
      },
    );
  });

  group('load errors', () {
    test('snapshot fetch failure → typed error → Retry reloads', () async {
      final port = FakeVoterPort(view: makeView(phase: 1))
        ..fetchError = StateError('rpc down');
      final machine = VoterJourneyMachine(port: port, capabilities: proverCaps);
      addTearDown(machine.dispose);
      await settle();

      final failed = machine.state as VoterLoadFailed;
      expect(failed.messageKey, 'error.loadFailed');

      port.fetchError = null;
      await machine.advance(failed.recoveryEvent);
      await settle();
      expect(machine.state, isA<VoterBallotOpen>());
    });
  });

  group('NextAction per state', () {
    final view = makeView(phase: 1);
    final receipt = const VoterReceipt(nullifier: '0xn', txHash: '0xt');

    test('every state exposes one primary action or an honest null', () {
      expect(
        VoterLoading(CancellationToken()).nextAction,
        const NextAction(labelKey: 'action.loading', type: NextActionType.wait),
      );
      expect(
        VoterEligibilityChecking(
          view: view,
          afterJoin: false,
          cancellation: CancellationToken(),
        ).nextAction!.type,
        NextActionType.wait,
      );
      expect(
        VoterNotEligible(view: view).nextAction,
        const NextAction(
          labelKey: 'action.requestJoin',
          type: NextActionType.submit,
        ),
      );
      expect(
        VoterNotEligible(
          view: view,
          joinDisabledReasonKey: 'reason.registrationClosed',
        ).nextAction!.enabled,
        isFalse,
      );
      expect(
        VoterJoinInProgress(
          view: view,
          cancellation: CancellationToken(),
        ).nextAction!.type,
        NextActionType.wait,
      );
      expect(
        VoterJoinPending(view: view).nextAction,
        const NextAction(
          labelKey: 'action.recheckRegistration',
          type: NextActionType.submit,
        ),
      );
      expect(
        VoterWaitingForOpen(view: view).nextAction!.type,
        NextActionType.wait,
      );
      expect(
        VoterWaitingForOpen(
          view: view,
          blockedReasonKey: 'reason.deviceCannotProve',
        ).nextAction,
        const NextAction(
          labelKey: 'action.castVote',
          type: NextActionType.submit,
          disabledReasonKey: 'reason.deviceCannotProve',
        ),
      );
      expect(
        VoterBallotOpen(view: view).nextAction,
        const NextAction(
          labelKey: 'action.castVote',
          type: NextActionType.submit,
          disabledReasonKey: 'reason.noSelection',
        ),
      );
      expect(
        VoterBallotOpen(
          view: view,
          draft: const SingleChoice(0),
        ).nextAction!.enabled,
        isTrue,
      );
      expect(
        VoterProvingInProgress(
          view: view,
          spec: const SingleChoice(0),
          cancellation: CancellationToken(),
        ).nextAction,
        const NextAction(
          labelKey: 'action.cancel',
          type: NextActionType.submit,
        ),
      );
      expect(
        VoterCastInProgress(
          view: view,
          spec: const SingleChoice(0),
          proof: FakeVoterPort.proof,
          cancellation: CancellationToken(),
        ).nextAction!.type,
        NextActionType.wait,
      );
      expect(
        VoterCastSucceeded(
          view: view,
          receipt: receipt,
          refreshed: true,
          cancellation: CancellationToken(),
        ).nextAction,
        const NextAction(
          labelKey: 'action.viewReceipt',
          type: NextActionType.navigate,
        ),
        reason: 'the next action after casting leads to the receipt',
      );
      expect(
        VoterReceiptSaved(view: view, receipt: receipt).nextAction,
        const NextAction(
          labelKey: 'action.viewResults',
          type: NextActionType.navigate,
        ),
      );
      expect(
        VoterResultsSealed(
          view: view,
          policy: ResultsPolicy.sealedUntilClose,
        ).nextAction!.disabledReasonKey,
        'reason.resultsSealedUntilClose',
      );

      final visible = VoterResultsVisible(view: view);
      expect(visible.nextAction, isNull);
      expect(visible.isTerminal, isTrue);
    });

    test('error states surface the retry action from the contract', () {
      for (final JourneyState state in [
        const VoterLoadFailed('x'),
        VoterJoinFailed(view: view, cause: 'x'),
        VoterRegistrationStillPending(view: view),
        VoterProofFailed(view: view, spec: const SingleChoice(0), cause: 'x'),
        VoterRelayFailed(
          view: view,
          spec: const SingleChoice(0),
          proof: FakeVoterPort.proof,
          cause: 'x',
        ),
      ]) {
        expect(state.nextAction!.type, NextActionType.retry, reason: state.id);
        expect(state.nextAction!.labelKey, 'action.retry', reason: state.id);
      }
    });
  });

  group('results phase changes', () {
    test('sealed results unseal when the poll ends', () async {
      final (machine, _) = await machineAt(view: makeView(phase: 1));
      await machine.advance(const VoterBallotEdited(SingleChoice(0)));
      await machine.advance(const VoterBallotSubmitted());
      await settle();
      await machine.advance(const VoterReceiptAcknowledged());
      await machine.advance(const VoterResultsRequested());
      expect(machine.state, isA<VoterResultsSealed>());

      await machine.advance(const ExternalPhaseChanged(2));
      expect(machine.state, isA<VoterResultsVisible>());
    });

    test('terminal results accept no further events', () async {
      final (machine, _) = await machineAt(view: makeView(phase: 2));
      expect(machine.state, isA<VoterResultsVisible>());

      await expectLater(
        machine.advance(const Refresh()),
        throwsA(isA<JourneyViolation>()),
      );
    });
  });
}
