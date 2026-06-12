// Widget tests for the proof-module poll surface: the machine is real, the
// PORT is faked — every screen state is reached the way production reaches
// it (through transitions), never by constructing widgets in fake states.
import 'dart:async';

import 'package:core_domain/journeys/capabilities.dart';
import 'package:core_domain/journeys/journey.dart';
import 'package:core_domain/journeys/policy.dart';
import 'package:core_domain/journeys/voter_journey.dart';
import 'package:core_domain/models/poll_snapshot.dart';
import 'package:core_domain/models/relay_proof.dart';
import 'package:design_system/widgets/results_bars.dart';
import 'package:feature_vote/feature_vote.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

class FakeVoterPort implements VoterJourneyPort {
  int phase;
  List<String> options;
  List<BigInt> results;
  ResultsPolicy policy;
  bool eligible;
  bool joinOk = true;

  /// When set, generateProof waits on it (to observe the proving state).
  Completer<void>? proofGate;

  BallotSpec? provedSpec;
  BallotSpec? relayedSpec;

  FakeVoterPort({
    this.phase = 1,
    this.options = const ['Alpha', 'Beta', 'Gamma'],
    List<BigInt>? results,
    this.policy = ResultsPolicy.livePublic,
    this.eligible = true,
  }) : results = results ?? [BigInt.two, BigInt.one, BigInt.zero];

  VoterModule module = VoterModule.anon;

  @override
  Future<VoterPollView> fetchSnapshot() async => VoterPollView(
    snapshot: PollSnapshot(
      address: testPollAddress,
      state: phase,
      options: options,
      results: results,
      owner: '0x2222222222222222222222222222222222222222',
      participantCount: BigInt.from(4),
    ),
    module: module,
    resultsPolicy: policy,
  );

  @override
  Future<bool> checkEligibility(VoterPollView view) async => eligible;

  @override
  Future<void> requestJoin(VoterPollView view) async {
    if (!joinOk) throw Exception('refused');
  }

  @override
  Future<RelayProof> generateProof(
    BallotSpec spec,
    VoterPollView view,
    CancellationToken cancellation,
  ) async {
    provedSpec = spec;
    final gate = proofGate;
    if (gate != null) await gate.future;
    return testProof;
  }

  @override
  Future<VoterReceipt> relayBallot(
    BallotSpec spec,
    RelayProof proof,
    VoterPollView view,
    CancellationToken cancellation,
  ) async {
    relayedSpec = spec;
    return VoterReceipt(nullifier: proof.nullifier, txHash: '0xtx');
  }
}

const canVote = Capabilities(
  canProve: true,
  canSign: false,
  canScanQr: false,
  hasNfc: false,
  hasBle: false,
  canUseWallet: false,
  relayerAvailable: true,
);

void main() {
  Future<VoterJourneyMachine> pumpScreen(
    WidgetTester tester,
    FakeVoterPort port, {
    Capabilities capabilities = canVote,
    Future<SurveyDetails> Function()? loadSurveyDetails,
    Future<SurveyDetails> Function()? loadSurveyResults,
    void Function(String code)? onVerifyReceipt,
  }) async {
    final machine = VoterJourneyMachine(port: port, capabilities: capabilities);
    addTearDown(machine.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: PollJourneyScreen(
          machine: machine,
          title: 'Board vote',
          kindLabel: voteKindLabel(switch (port.module) {
            VoterModule.anon => 'anon-vote',
            VoterModule.approval => 'approval-vote',
            VoterModule.ranked => 'ranked-vote',
            VoterModule.quadratic => 'quadratic-vote',
            VoterModule.survey => 'survey-vote',
          }),
          loadSurveyDetails: loadSurveyDetails,
          loadSurveyResults: loadSurveyResults,
          onVerifyReceipt: onVerifyReceipt,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return machine;
  }

  group('single-choice (pick one)', () {
    testWidgets('ballot renders radios; cast disabled until a choice', (
      tester,
    ) async {
      final port = FakeVoterPort();
      await pumpScreen(tester, port);

      expect(find.text('Alpha'), findsWidgets);
      expect(find.text('CAST YOUR VOTE'), findsOneWidget);
      // Honest disabled reason, straight from the machine's nextAction.
      expect(find.text('Make your choice first.'), findsOneWidget);

      await tester.tap(find.text('Beta').first);
      await tester.pumpAndSettle();
      expect(find.text('Make your choice first.'), findsNothing);
    });

    testWidgets(
      'submit → proving (≈10s copy, cancellable) → success auto-shows '
      'receipt + refreshed results with VERIFY action',
      (tester) async {
        final port = FakeVoterPort()..proofGate = Completer<void>();
        String? verified;
        await pumpScreen(
          tester,
          port,
          onVerifyReceipt: (code) => verified = code,
        );

        await tester.tap(find.text('Beta').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('CAST YOUR VOTE'));
        // No pumpAndSettle: the proving spinner animates until the gate opens.
        await tester.pump();
        await tester.pump();

        // Proving state: progress with the honest duration + CANCEL.
        expect(find.textContaining('about 10 seconds'), findsOneWidget);
        expect(find.text('CANCEL'), findsOneWidget);

        port.proofGate!.complete();
        await tester.pumpAndSettle();

        // Landed: success + receipt panel + live results, no extra taps.
        expect(find.byKey(PollJourneyScreen.successKey), findsOneWidget);
        expect(find.text('YOUR PRIVATE VOTE RECEIPT'), findsOneWidget);
        expect(port.relayedSpec, const SingleChoice(1));
        expect(find.byType(ResultsBars), findsOneWidget);

        await tester.tap(find.byKey(ReceiptPanel.verifyKey));
        expect(verified, testProof.nullifier);
      },
    );

    testWidgets('cancel during proving returns to the ballot, draft kept', (
      tester,
    ) async {
      final port = FakeVoterPort()..proofGate = Completer<void>();
      final machine = await pumpScreen(tester, port);

      await tester.tap(find.text('Gamma').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('CAST YOUR VOTE'));
      // No pumpAndSettle: the proving spinner animates until cancelled.
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();

      final state = machine.state;
      expect(state, isA<VoterBallotOpen>());
      expect((state as VoterBallotOpen).draft, const SingleChoice(2));
      expect(find.text('CAST YOUR VOTE'), findsOneWidget);
    });
  });

  group('sealed vs live results (spec §3 principle 2)', () {
    testWidgets('sealed policy + voting open: sealed panel INSTEAD of tallies, '
        'even though chain data is readable', (tester) async {
      final port = FakeVoterPort(policy: ResultsPolicy.sealedUntilClose);
      await pumpScreen(tester, port);

      expect(find.byKey(SealedResultsPanel.panelKey), findsOneWidget);
      expect(find.text('Results open when voting closes.'), findsOneWidget);
      expect(find.byType(ResultsBars), findsNothing);
    });

    testWidgets('live-public policy shows the live tally next to the ballot', (
      tester,
    ) async {
      final port = FakeVoterPort(policy: ResultsPolicy.livePublic);
      await pumpScreen(tester, port);

      expect(find.byType(ResultsBars), findsOneWidget);
      expect(find.byKey(SealedResultsPanel.panelKey), findsNothing);
    });

    testWidgets('after casting under sealed policy: receipt + sealed panel', (
      tester,
    ) async {
      final port = FakeVoterPort(policy: ResultsPolicy.sealedUntilClose);
      await pumpScreen(tester, port);

      await tester.tap(find.text('Alpha').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('CAST YOUR VOTE'));
      await tester.pumpAndSettle();

      expect(find.text('YOUR PRIVATE VOTE RECEIPT'), findsOneWidget);
      expect(find.byKey(SealedResultsPanel.panelKey), findsOneWidget);
      expect(find.byType(ResultsBars), findsNothing);
    });

    testWidgets('ended poll shows results (terminal state)', (tester) async {
      final port = FakeVoterPort(phase: 2);
      await pumpScreen(tester, port);
      expect(find.byType(ResultsBars), findsOneWidget);
    });
  });

  group('honest disabled / waiting / join states', () {
    testWidgets(
      'not eligible + registration closed: ASK TO JOIN disabled with reason',
      (tester) async {
        final port = FakeVoterPort(eligible: false); // phase 1: reg closed
        await pumpScreen(tester, port);

        expect(find.text('ASK TO JOIN'), findsOneWidget);
        expect(find.text('Joining is closed for this vote.'), findsOneWidget);
      },
    );

    testWidgets(
      'eligible but device cannot prove: cast disabled with the honest reason',
      (tester) async {
        final port = FakeVoterPort();
        await pumpScreen(
          tester,
          port,
          capabilities: canVote.copyWith(
            canProve: false,
            reasons: {Capability.prove: 'reason.prove.platformUnsupported'},
          ),
        );

        expect(find.text('CAST YOUR VOTE'), findsOneWidget);
        expect(find.textContaining('isn’t supported yet'), findsOneWidget);
      },
    );

    testWidgets('join flow: request → pending → recheck → ballot', (
      tester,
    ) async {
      final port = FakeVoterPort(phase: 0, eligible: false);
      final machine = await pumpScreen(tester, port);

      await tester.tap(find.text('ASK TO JOIN'));
      await tester.pumpAndSettle();
      expect(machine.state, isA<VoterJoinPending>());
      expect(find.text('CHECK AGAIN'), findsOneWidget);

      // The chain confirms; the recheck lands in the waiting room (phase 0).
      port.eligible = true;
      await tester.tap(find.text('CHECK AGAIN'));
      await tester.pumpAndSettle();
      expect(machine.state, isA<VoterWaitingForOpen>());
      expect(find.text('WAITING FOR VOTING TO OPEN'), findsOneWidget);
    });

    testWidgets('load failure renders the typed error with a way out', (
      tester,
    ) async {
      final port = _ThrowingPort();
      final machine = VoterJourneyMachine(port: port, capabilities: canVote);
      addTearDown(machine.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: PollJourneyScreen(
            machine: machine,
            title: 'Board vote',
            kindLabel: 'PICK ONE',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Could not load this vote. Check your connection.'),
        findsOneWidget,
      );
      expect(find.text('TRY AGAIN'), findsOneWidget);
    });
  });

  group('module ballots submit through the machine', () {
    testWidgets('approval: checkboxes → bitmask', (tester) async {
      final port = FakeVoterPort()..module = VoterModule.approval;
      await pumpScreen(tester, port);

      await tester.tap(find.text('Alpha').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gamma').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('CAST YOUR VOTE'));
      await tester.pumpAndSettle();

      expect(port.relayedSpec, Approval(BigInt.from(0x5)));
      expect(find.text('YOUR PRIVATE VOTE RECEIPT'), findsOneWidget);
    });

    testWidgets('approval: deselecting back to empty disables cast again', (
      tester,
    ) async {
      final port = FakeVoterPort()..module = VoterModule.approval;
      await pumpScreen(tester, port);

      await tester.tap(find.text('Alpha').first);
      await tester.pumpAndSettle();
      expect(find.text('Make your choice first.'), findsNothing);

      await tester.tap(find.text('Alpha').first);
      await tester.pumpAndSettle();
      expect(find.text('Make your choice first.'), findsOneWidget);
    });

    testWidgets('ranked: confirm order → full ordering ballot', (tester) async {
      final port = FakeVoterPort()..module = VoterModule.ranked;
      await pumpScreen(tester, port);

      expect(find.text('Make your choice first.'), findsOneWidget);
      await tester.tap(find.byKey(RankedBallot.confirmOrderKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CAST YOUR VOTE'));
      await tester.pumpAndSettle();

      expect(port.relayedSpec, Ranked([0, 1, 2]));
    });

    testWidgets('quadratic: steppers spend the credit meter', (tester) async {
      final port = FakeVoterPort()..module = VoterModule.quadratic;
      await pumpScreen(tester, port);

      expect(find.text('100 / 100'), findsOneWidget);
      await tester.tap(find.byKey(QuadraticBallot.plusKey(0)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(QuadraticBallot.plusKey(0)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(QuadraticBallot.plusKey(2)));
      await tester.pumpAndSettle();

      // 2² + 1² = 5 spent.
      expect(find.text('95 / 100'), findsOneWidget);

      await tester.tap(find.text('CAST YOUR VOTE'));
      await tester.pumpAndSettle();
      expect(port.relayedSpec, Quadratic([2, 0, 1]));
    });

    testWidgets('survey: question pager → full answer vector', (tester) async {
      final port = FakeVoterPort(options: const ['Q1', 'Q2'])
        ..module = VoterModule.survey;
      const details = SurveyDetails(
        questions: [
          SurveyQuestion(type: 0, options: ['Yes', 'No']),
          SurveyQuestion(type: 1, options: ['Mon', 'Tue', 'Wed']),
        ],
      );
      await pumpScreen(tester, port, loadSurveyDetails: () async => details);

      expect(find.text('QUESTION 1 OF 2'), findsOneWidget);
      // Page 2 unreachable until question 1 is answered.
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(SurveyBallot.nextQuestionKey));
      await tester.pumpAndSettle();
      expect(find.text('QUESTION 2 OF 2'), findsOneWidget);

      await tester.tap(find.text('Mon'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wed'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CAST YOUR VOTE'));
      await tester.pumpAndSettle();

      expect(port.relayedSpec, Survey([BigInt.zero, BigInt.from(0x5)]));
    });
  });
}

class _ThrowingPort extends FakeVoterPort {
  @override
  Future<VoterPollView> fetchSnapshot() async =>
      throw Exception('rpc unreachable');
}
