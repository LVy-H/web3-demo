import 'dart:async' show Completer;

import 'package:core_domain/journeys/capabilities.dart';
import 'package:core_domain/journeys/journey.dart';
import 'package:core_domain/journeys/organizer_journey.dart';
import 'package:core_domain/journeys/policy.dart';
// `hide`: the journey contract's Retry/Timeout events share names with
// package:test configuration types we don't use here.
import 'package:test/test.dart' hide Retry, Timeout;

/// Drains the event queue so fire-and-forget effect completions land.
Future<void> settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Configurable in-memory port — no chain, no relayer.
final class FakeOrganizerPort implements OrganizerJourneyPort {
  String pollAddress = '0xP011';

  /// When set, [deployPoll] waits on it — lets a test observe the
  /// deployInProgress state deterministically.
  Completer<void>? deployGate;
  int rosterCount = 10;
  int turnout = 7;
  OrganizerResults results = const OrganizerResults({'Pizza': 4, 'Sushi': 3});

  Object? deployError;
  Object? rosterError;
  Object? turnoutError;
  Object? startVotingError;
  Object? endVotingError;
  Object? finalizeError;
  Object? resultsError;

  OrganizerPollSpec? lastDeployedSpec;
  final List<String> calls = [];

  @override
  Future<String> deployPoll(OrganizerPollSpec spec) async {
    calls.add('deployPoll');
    lastDeployedSpec = spec;
    if (deployGate != null) await deployGate!.future;
    if (deployError != null) throw deployError!;
    return pollAddress;
  }

  @override
  Future<int> fetchRoster(String pollAddress) async {
    calls.add('fetchRoster');
    if (rosterError != null) throw rosterError!;
    return rosterCount;
  }

  @override
  Future<int> fetchTurnout(String pollAddress) async {
    calls.add('fetchTurnout');
    if (turnoutError != null) throw turnoutError!;
    return turnout;
  }

  @override
  Future<void> startVoting(String pollAddress) async {
    calls.add('startVoting');
    if (startVotingError != null) throw startVotingError!;
  }

  @override
  Future<void> endVoting(String pollAddress) async {
    calls.add('endVoting');
    if (endVotingError != null) throw endVotingError!;
  }

  @override
  Future<void> finalize(String pollAddress) async {
    calls.add('finalize');
    if (finalizeError != null) throw finalizeError!;
  }

  @override
  Future<OrganizerResults> fetchResults(String pollAddress) async {
    calls.add('fetchResults');
    if (resultsError != null) throw resultsError!;
    return results;
  }
}

/// Sponsored-creation device: the relayer is the (preferred) signer path.
final sponsored = Capabilities.none.copyWith(relayerAvailable: true);

const completeSpec = OrganizerPollSpec(
  title: 'Team lunch',
  options: ['Pizza', 'Sushi'],
);

const blindSpec = OrganizerPollSpec(
  module: OrganizerModule.blindVote,
  title: 'Sealed vote',
  options: ['Yes', 'No'],
  revealWindow: Duration(hours: 1),
);

OrganizerJourneyMachine machineWith(
  FakeOrganizerPort port, {
  Capabilities? capabilities,
  MinRosterPolicy minRoster = const MinRosterPolicy(),
}) {
  return OrganizerJourneyMachine(
    port: port,
    capabilities: capabilities ?? sponsored,
    minRoster: minRoster,
  );
}

/// Drives draft → created for [spec].
Future<void> toCreated(
  OrganizerJourneyMachine machine, {
  OrganizerPollSpec spec = completeSpec,
}) async {
  await machine.advance(OrganizerDraftUpdated(spec));
  await machine.advance(const OrganizerDeployRequested());
  await settle();
  expect(machine.state, isA<OrganizerCreated>());
}

/// Drives draft → registrationOpen (roster fetch settled).
Future<void> toRegistrationOpen(
  OrganizerJourneyMachine machine, {
  OrganizerPollSpec spec = completeSpec,
}) async {
  await toCreated(machine, spec: spec);
  await machine.advance(const OrganizerOpenRegistration());
  await settle();
  expect(machine.state, isA<OrganizerRegistrationOpen>());
}

/// Drives draft → votingOpen (turnout fetch settled).
Future<void> toVotingOpen(
  OrganizerJourneyMachine machine, {
  OrganizerPollSpec spec = completeSpec,
}) async {
  await toRegistrationOpen(machine, spec: spec);
  await machine.advance(const OrganizerStartVotingRequested());
  await settle();
  expect(machine.state, isA<OrganizerVotingOpen>());
}

/// Drives draft → closed.
Future<void> toClosed(
  OrganizerJourneyMachine machine, {
  OrganizerPollSpec spec = completeSpec,
}) async {
  await toVotingOpen(machine, spec: spec);
  await machine.advance(const OrganizerEndVotingRequested());
  await settle();
  expect(machine.state, isA<OrganizerClosed>());
}

void main() {
  group('privacy defaults (spec §5)', () {
    test('an untouched draft is unlisted + sealedUntilClose', () {
      final machine = machineWith(FakeOrganizerPort());
      addTearDown(machine.dispose);

      final draft = machine.state as OrganizerDraft;
      expect(draft.spec.visibility, PollVisibility.unlisted);
      expect(draft.spec.resultsPolicy, ResultsPolicy.sealedUntilClose);
      // The form starts incomplete — and says so, honestly.
      expect(draft.nextAction!.enabled, isFalse);
      expect(
        draft.nextAction!.disabledReasonKey,
        'reason.organizer.draftIncomplete',
      );
    });

    test(
      'deployPoll receives the spec including visibility + policy',
      () async {
        final port = FakeOrganizerPort();
        final machine = machineWith(port);
        addTearDown(machine.dispose);

        await toCreated(machine);
        expect(port.lastDeployedSpec!.visibility, PollVisibility.unlisted);
        expect(
          port.lastDeployedSpec!.resultsPolicy,
          ResultsPolicy.sealedUntilClose,
        );
      },
    );
  });

  group('full lifecycle happy path', () {
    test('draft → deploy → created → registration → voting → closed → '
        'published', () async {
      final port = FakeOrganizerPort();
      final machine = machineWith(port);
      addTearDown(machine.dispose);

      await machine.advance(const OrganizerDraftUpdated(completeSpec));
      final draft = machine.state as OrganizerDraft;
      expect(draft.nextAction!.enabled, isTrue);

      port.deployGate = Completer<void>();
      await machine.advance(const OrganizerDeployRequested());
      // Deploying is a state, not a busy flag — observable while in flight.
      final deploying = machine.state as OrganizerDeployInProgress;
      expect(deploying.nextAction!.type, NextActionType.wait);
      port.deployGate!.complete();
      await settle();

      // Created: the one next action is DISTRIBUTE, and the copy key says
      // the poll starts unlisted — the legacy "creator thinks it's live"
      // confusion becomes a guided announce step.
      final created = machine.state as OrganizerCreated;
      expect(created.id, 'organizer.created');
      expect(created.pollAddress, '0xP011');
      expect(created.nextAction!.labelKey, 'action.organizer.distribute');
      expect(created.noticeKey, 'notice.organizer.createdUnlisted');
      expect(created.shareTargets, [
        ShareTarget.qr,
        ShareTarget.link,
        ShareTarget.code,
      ]);

      await machine.advance(const OrganizerOpenRegistration());
      await settle(); // roster auto-fetch
      final registration = machine.state as OrganizerRegistrationOpen;
      expect(registration.rosterCount, 10);
      expect(registration.nextAction!.labelKey, 'action.organizer.startVoting');

      await machine.advance(const OrganizerStartVotingRequested());
      await settle();
      final voting = machine.state as OrganizerVotingOpen;
      expect(voting.id, 'organizer.votingOpen');
      expect(voting.turnout, 7);
      expect(voting.smallGroupWarning, isFalse);
      expect(voting.nextAction!.labelKey, 'action.organizer.endVoting');

      await machine.advance(const OrganizerEndVotingRequested());
      await settle();
      final closed = machine.state as OrganizerClosed;
      expect(closed.id, 'organizer.closed');
      expect(closed.nextAction!.labelKey, 'action.organizer.publishResults');

      await machine.advance(const OrganizerPublishRequested());
      await settle();
      final published = machine.state as OrganizerPublished;
      expect(published.isTerminal, isTrue);
      expect(published.nextAction, isNull);
      expect(published.results.tallies, {'Pizza': 4, 'Sushi': 3});

      expect(port.calls, [
        'deployPoll',
        'fetchRoster',
        'startVoting',
        'fetchTurnout',
        'endVoting',
        'fetchResults',
      ]);
    });

    test('share targets include NFC only with the hardware', () async {
      final machine = machineWith(
        FakeOrganizerPort(),
        capabilities: sponsored.copyWith(hasNfc: true),
      );
      addTearDown(machine.dispose);

      await toCreated(machine);
      final created = machine.state as OrganizerCreated;
      expect(created.shareTargets, contains(ShareTarget.nfc));
    });
  });

  group('results gate (sealed vs live-public)', () {
    test('sealedUntilClose: even the organizer sees turnout, not tallies, '
        'until close', () async {
      final machine = machineWith(FakeOrganizerPort());
      addTearDown(machine.dispose);

      await toVotingOpen(machine);
      final voting = machine.state as OrganizerVotingOpen;
      expect(voting.turnout, isNotNull); // turnout is always visible
      expect(voting.tallyVisible, isFalse); // tallies are not

      await machine.advance(const OrganizerEndVotingRequested());
      await settle();
      final closed = machine.state as OrganizerClosed;
      expect(closed.tallyVisible, isTrue); // sealed means *until close*
    });

    test('livePublic (explicit opt-in) shows tallies during voting', () async {
      final machine = machineWith(FakeOrganizerPort());
      addTearDown(machine.dispose);

      await toVotingOpen(
        machine,
        spec: completeSpec.copyWith(resultsPolicy: ResultsPolicy.livePublic),
      );
      expect((machine.state as OrganizerVotingOpen).tallyVisible, isTrue);
    });

    test('no organizer override mid-poll: the spec cannot be edited after '
        'deploy', () async {
      final machine = machineWith(FakeOrganizerPort());
      addTearDown(machine.dispose);

      await toVotingOpen(machine);
      await expectLater(
        machine.advance(
          OrganizerDraftUpdated(
            completeSpec.copyWith(resultsPolicy: ResultsPolicy.livePublic),
          ),
        ),
        throwsA(isA<JourneyViolation>()),
      );
    });
  });

  group('phase-order enforcement', () {
    test('endVoting before startVoting throws', () async {
      final machine = machineWith(FakeOrganizerPort());
      addTearDown(machine.dispose);

      await toRegistrationOpen(machine);
      await expectLater(
        machine.advance(const OrganizerEndVotingRequested()),
        throwsA(isA<JourneyViolation>()),
      );
      expect(machine.state, isA<OrganizerRegistrationOpen>());
    });

    test('publish before closed throws', () async {
      final machine = machineWith(FakeOrganizerPort());
      addTearDown(machine.dispose);

      await toVotingOpen(machine);
      await expectLater(
        machine.advance(const OrganizerPublishRequested()),
        throwsA(isA<JourneyViolation>()),
      );
    });

    test('startVoting before the announce step throws', () async {
      final machine = machineWith(FakeOrganizerPort());
      addTearDown(machine.dispose);

      await toCreated(machine);
      await expectLater(
        machine.advance(const OrganizerStartVotingRequested()),
        throwsA(isA<JourneyViolation>()),
      );
    });

    test('finalize on a non-blind poll is guard-rejected', () async {
      final machine = machineWith(FakeOrganizerPort());
      addTearDown(machine.dispose);

      await toClosed(machine);
      await expectLater(
        machine.advance(const OrganizerFinalizeRequested()),
        throwsA(
          isA<JourneyViolation>().having(
            (v) => v.guardRejected,
            'guardRejected',
            isTrue,
          ),
        ),
      );
    });

    test('external phase regression is guard-rejected', () async {
      final machine = machineWith(FakeOrganizerPort());
      addTearDown(machine.dispose);

      await toVotingOpen(machine);
      await expectLater(
        machine.advance(const ExternalPhaseChanged(0)),
        throwsA(
          isA<JourneyViolation>().having(
            (v) => v.guardRejected,
            'guardRejected',
            isTrue,
          ),
        ),
      );
    });

    test('external phase change advances the journey (another owner device '
        'started voting)', () async {
      final machine = machineWith(FakeOrganizerPort());
      addTearDown(machine.dispose);

      await toRegistrationOpen(machine);
      await machine.advance(const ExternalPhaseChanged(1));
      expect(machine.state, isA<OrganizerVotingOpen>());
      await settle(); // turnout auto-fetch
      expect((machine.state as OrganizerVotingOpen).turnout, 7);
    });
  });

  group('signer path (spec §4.3 honest capability surface)', () {
    test('no signer path: deploy is disabled with a reason, never a cryptic '
        'string', () async {
      final machine = machineWith(
        FakeOrganizerPort(),
        capabilities: Capabilities.none,
      );
      addTearDown(machine.dispose);

      await machine.advance(const OrganizerDraftUpdated(completeSpec));
      final draft = machine.state as OrganizerDraft;
      expect(draft.nextAction!.enabled, isFalse);
      expect(
        draft.nextAction!.disabledReasonKey,
        'reason.organizer.noSignerPath',
      );

      // The guard backs the disabled button: forcing the event throws.
      await expectLater(
        machine.advance(const OrganizerDeployRequested()),
        throwsA(
          isA<JourneyViolation>().having(
            (v) => v.guardRejected,
            'guardRejected',
            isTrue,
          ),
        ),
      );
    });

    test('any one path enables deploy: relayer, dev signer, or wallet', () {
      for (final capabilities in [
        Capabilities.none.copyWith(relayerAvailable: true),
        Capabilities.none.copyWith(canSign: true),
        Capabilities.none.copyWith(canUseWallet: true),
      ]) {
        expect(OrganizerJourneyMachine.hasSignerPath(capabilities), isTrue);
      }
      expect(OrganizerJourneyMachine.hasSignerPath(Capabilities.none), isFalse);
    });
  });

  group('small-group warning (spec §5)', () {
    test(
      'roster below the default threshold flags votingOpen and closed',
      () async {
        final port = FakeOrganizerPort()..rosterCount = 3;
        final machine = machineWith(port);
        addTearDown(machine.dispose);

        await toVotingOpen(machine);
        expect(
          (machine.state as OrganizerVotingOpen).smallGroupWarning,
          isTrue,
        );

        await machine.advance(const OrganizerEndVotingRequested());
        await settle();
        expect((machine.state as OrganizerClosed).smallGroupWarning, isTrue);
      },
    );

    test('threshold is constructor-injected', () async {
      final port = FakeOrganizerPort()..rosterCount = 3;
      final machine = machineWith(
        port,
        minRoster: const MinRosterPolicy(threshold: 2),
      );
      addTearDown(machine.dispose);

      await toVotingOpen(machine);
      expect((machine.state as OrganizerVotingOpen).smallGroupWarning, isFalse);
    });
  });

  group('failure → typed error → Retry', () {
    test(
      'deploy failure lands in OrganizerDeployFailed and Retry redeploys',
      () async {
        final port = FakeOrganizerPort()
          ..deployError = StateError('relayer unreachable');
        final machine = machineWith(port);
        addTearDown(machine.dispose);

        await machine.advance(const OrganizerDraftUpdated(completeSpec));
        await machine.advance(const OrganizerDeployRequested());
        await settle();

        final failed = machine.state as OrganizerDeployFailed;
        expect(failed.messageKey, 'error.organizer.deployFailed');
        expect(failed.cause, isA<StateError>());
        expect(failed.nextAction!.type, NextActionType.retry);

        port.deployError = null;
        await machine.advance(failed.recoveryEvent);
        await settle();
        expect(machine.state, isA<OrganizerCreated>());
        expect(port.calls.where((c) => c == 'deployPoll').length, 2);
      },
    );

    test('a deploy failure can also go back to the form', () async {
      final port = FakeOrganizerPort()..deployError = StateError('boom');
      final machine = machineWith(port);
      addTearDown(machine.dispose);

      await machine.advance(const OrganizerDraftUpdated(completeSpec));
      await machine.advance(const OrganizerDeployRequested());
      await settle();
      expect(machine.state, isA<OrganizerDeployFailed>());

      await machine.advance(const OrganizerDraftUpdated(completeSpec));
      expect(machine.state, isA<OrganizerDraft>());
    });

    test('startVoting failure retains context and Retry re-attempts', () async {
      final port = FakeOrganizerPort()
        ..startVotingError = StateError('tx reverted');
      final machine = machineWith(port);
      addTearDown(machine.dispose);

      await toRegistrationOpen(machine);
      await machine.advance(const OrganizerStartVotingRequested());
      await settle();

      final failed = machine.state as OrganizerPhaseActionFailed;
      expect(failed.action, OrganizerPhaseAction.startVoting);
      expect(failed.messageKey, 'error.organizer.startVotingFailed');
      expect(failed.rosterCount, 10);

      port.startVotingError = null;
      await machine.advance(failed.recoveryEvent);
      await settle();
      expect(machine.state, isA<OrganizerVotingOpen>());
    });
  });

  group('roster/turnout refresh', () {
    test('Refresh re-reads the roster while registration is open', () async {
      final port = FakeOrganizerPort()..rosterCount = 2;
      final machine = machineWith(port);
      addTearDown(machine.dispose);

      await toRegistrationOpen(machine);
      expect((machine.state as OrganizerRegistrationOpen).rosterCount, 2);

      port.rosterCount = 6;
      await machine.advance(const Refresh());
      await settle();
      expect((machine.state as OrganizerRegistrationOpen).rosterCount, 6);
    });

    test(
      'a failed refresh keeps the last known count (stale over dead end)',
      () async {
        final port = FakeOrganizerPort();
        final machine = machineWith(port);
        addTearDown(machine.dispose);

        await toRegistrationOpen(machine);
        port.rosterError = StateError('rpc down');
        await machine.advance(const Refresh());
        await settle();
        final open = machine.state as OrganizerRegistrationOpen;
        expect(open.rosterCount, 10);
        expect(open.fetchPending, isFalse);
      },
    );
  });

  group('blind module owner actions (ordered)', () {
    test('endVoting → reveal window (Timeout) → finalize → publish', () async {
      final port = FakeOrganizerPort();
      final machine = machineWith(port);
      addTearDown(machine.dispose);

      await toClosed(machine, spec: blindSpec);
      var closed = machine.state as OrganizerClosed;
      expect(closed.revealWindowElapsed, isFalse);

      // Finalize is offered but disabled while voters can still reveal —
      // and the guard backs the disabled button.
      expect(closed.nextAction!.labelKey, 'action.organizer.finalize');
      expect(
        closed.nextAction!.disabledReasonKey,
        'reason.organizer.revealWindowOpen',
      );
      await expectLater(
        machine.advance(const OrganizerFinalizeRequested()),
        throwsA(
          isA<JourneyViolation>().having(
            (v) => v.guardRejected,
            'guardRejected',
            isTrue,
          ),
        ),
      );

      // Publishing before finalize is equally illegal for blind polls.
      await expectLater(
        machine.advance(const OrganizerPublishRequested()),
        throwsA(isA<JourneyViolation>()),
      );

      // The reveal deadline elapses; monitoring can still Refresh reveals.
      await machine.advance(const Timeout());
      closed = machine.state as OrganizerClosed;
      expect(closed.revealWindowElapsed, isTrue);
      expect(closed.nextAction!.enabled, isTrue);

      await machine.advance(const OrganizerFinalizeRequested());
      await settle();
      closed = machine.state as OrganizerClosed;
      expect(closed.finalized, isTrue);
      expect(closed.nextAction!.labelKey, 'action.organizer.publishResults');

      await machine.advance(const OrganizerPublishRequested());
      await settle();
      expect(machine.state, isA<OrganizerPublished>());
      expect(port.calls, contains('finalize'));
    });

    test('a blind draft is incomplete without a reveal window', () {
      const spec = OrganizerPollSpec(
        module: OrganizerModule.blindVote,
        title: 'Sealed',
        options: ['Yes', 'No'],
      );
      expect(spec.isComplete, isFalse);
      expect(blindSpec.isComplete, isTrue);
    });
  });
}
