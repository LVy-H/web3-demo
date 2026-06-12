// The production VoterJourneyPort over the core services: snapshot shape,
// lazy identity creation on join, message encodings, endpoint routing, and
// the local participation record.
import 'package:core_crypto/crypto/survey_commit.dart';
import 'package:core_crypto/proof/proof_service.dart';
import 'package:core_domain/journeys/journey.dart';
import 'package:core_domain/journeys/policy.dart';
import 'package:core_domain/journeys/voter_journey.dart';
import 'package:core_storage/identity_store.dart';
import 'package:feature_vote/feature_vote.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  late FakeChainReader reader;
  late FakeRelayClient relay;
  late InMemoryIdentityStore identity;
  late InMemoryKnownPollsStore knownPolls;

  VoterPortAdapter adapter({
    VoterModule module = VoterModule.anon,
    ResultsPolicy? policy = ResultsPolicy.sealedUntilClose,
  }) => VoterPortAdapter(
    reader: reader,
    relay: relay,
    proofService: FakeProofService(testProof),
    identityStore: identity,
    pollAddress: testPollAddress,
    module: module,
    readResultsPolicy: () async => policy,
    knownPolls: knownPolls,
    pollTitle: 'Test poll',
    moduleType: 'anon-vote',
  );

  setUp(() {
    reader = FakeChainReader();
    relay = FakeRelayClient();
    identity = InMemoryIdentityStore();
    knownPolls = InMemoryKnownPollsStore();
  });

  test('fetchSnapshot maps chain reads + R4 policy', () async {
    final v = await adapter().fetchSnapshot();
    expect(v.phase, 1);
    expect(v.snapshot.options, ['Alpha', 'Beta', 'Gamma']);
    expect(v.resultsPolicy, ResultsPolicy.sealedUntilClose);
  });

  test(
    'pre-R4 polls (no resultsPolicy on-chain) read as live-public',
    () async {
      final v = await adapter(policy: null).fetchSnapshot();
      expect(v.resultsPolicy, ResultsPolicy.livePublic);
    },
  );

  test('survey snapshots get one option slot per QUESTION', () async {
    final v = await adapter(module: VoterModule.survey).fetchSnapshot();
    expect(v.optionCount, 2);
    expect(v.module, VoterModule.survey);
  });

  test('checkEligibility: no identity → not eligible (no throw)', () async {
    final v = await adapter().fetchSnapshot();
    expect(await adapter().checkEligibility(v), isFalse);
  });

  test(
    'checkEligibility: member when the derived id is in the group',
    () async {
      await identity.write('0xseed');
      reader.commitments = ['1234567890']; // FakeProofService's derivation
      final v = await adapter().fetchSnapshot();
      expect(await adapter().checkEligibility(v), isTrue);
    },
  );

  test(
    'requestJoin lazily creates the voting pass, registers, records the poll',
    () async {
      expect(await identity.read(), isNull);
      final port = adapter();
      final v = await port.fetchSnapshot();
      await port.requestJoin(v);

      expect(await identity.read(), isNotNull); // pass created on first need
      expect(relay.calls.single.$1, 'register');
      final record = (await knownPolls.find(testPollAddress))!;
      expect(record.stage, KnownPollStage.joined);
      expect(record.title, 'Test poll');
    },
  );

  test('requestJoin surfaces the relayer refusal as an error', () async {
    relay.registerOk = false;
    final port = adapter();
    final v = await port.fetchSnapshot();
    expect(() => port.requestJoin(v), throwsException);
  });

  group('relayBallot routes each module to its endpoint with its encoding', () {
    test('anon → /vote with the option index', () async {
      final port = adapter();
      final v = await port.fetchSnapshot();
      final receipt = await port.relayBallot(
        const SingleChoice(2),
        testProof,
        v,
        CancellationToken(),
      );
      expect(relay.calls.single, ('vote', 2, testProof));
      expect(receipt.nullifier, testProof.nullifier);
      expect(receipt.txHash, '0xtx');
      // The cast lands in the local record with the receipt.
      final record = (await knownPolls.find(testPollAddress))!;
      expect(record.stage, KnownPollStage.voted);
      expect(record.receiptCode, testProof.nullifier);
    });

    test('approval → /approval-vote with the bitmask', () async {
      final port = adapter(module: VoterModule.approval);
      final v = await port.fetchSnapshot();
      await port.relayBallot(
        Approval(BigInt.from(0x5)),
        testProof,
        v,
        CancellationToken(),
      );
      expect(relay.calls.single.$1, 'approval-vote');
      expect(relay.calls.single.$2, 0x5);
    });

    test('ranked → /ranked-vote with the packed ordering', () async {
      final port = adapter(module: VoterModule.ranked);
      final v = await port.fetchSnapshot();
      await port.relayBallot(
        Ranked([2, 0, 1]),
        testProof,
        v,
        CancellationToken(),
      );
      expect(relay.calls.single.$1, 'ranked-vote');
      expect(relay.calls.single.$2, 531);
    });

    test('quadratic → /quadratic-vote with the packed allocation', () async {
      final port = adapter(module: VoterModule.quadratic);
      final v = await port.fetchSnapshot();
      await port.relayBallot(
        Quadratic([6, 0, 8]),
        testProof,
        v,
        CancellationToken(),
      );
      expect(relay.calls.single.$1, 'quadratic-vote');
      expect(relay.calls.single.$2, 0x806);
    });

    test('survey → /survey-vote with the full answer vector', () async {
      final port = adapter(module: VoterModule.survey);
      final v = await port.fetchSnapshot();
      final answers = [BigInt.zero, BigInt.from(0x6)];
      await port.relayBallot(
        Survey(answers),
        testProof,
        v,
        CancellationToken(),
      );
      expect(relay.calls.single.$1, 'survey-vote');
      expect(relay.calls.single.$2, answers);
    });

    test(
      'relay failure throws (the machine maps it to a typed state)',
      () async {
        relay.relayOk = false;
        final port = adapter();
        final v = await port.fetchSnapshot();
        expect(
          () => port.relayBallot(
            const SingleChoice(0),
            testProof,
            v,
            CancellationToken(),
          ),
          throwsException,
        );
      },
    );
  });

  test(
    'generateProof binds the survey commitment as the wide message',
    () async {
      await identity.write('0xseed');
      final port = adapter(module: VoterModule.survey);
      final v = await port.fetchSnapshot();
      final answers = [BigInt.one, BigInt.from(5)];
      final proof = await port.generateProof(
        Survey(answers),
        v,
        CancellationToken(),
      );
      // FakeProofService echoes the wide message it was handed.
      expect(proof.message, surveyCommitment(answers).toString());
    },
  );

  test('generateProof for int-message modules uses the narrow path', () async {
    await identity.write('0xseed');
    final port = adapter();
    final v = await port.fetchSnapshot();
    final proof = await port.generateProof(
      const SingleChoice(1),
      v,
      CancellationToken(),
    );
    expect(proof, same(testProof));
  });
}
