/// Production [VoterJourneyPort] over core_chain / core_relay / core_crypto /
/// core_storage — the wallet-free path for the five proof modules.
///
/// One adapter per (poll, module): the resolver hands the poll screen the
/// on-chain module type, the screen builds this adapter, and the machine in
/// core_domain drives it. All jargon stays below this line.
library;

import 'package:core_chain/chain_reader.dart';
import 'package:core_crypto/crypto/survey_commit.dart';
import 'package:core_crypto/proof/proof_service.dart';
import 'package:core_domain/journeys/journey.dart';
import 'package:core_domain/journeys/policy.dart';
import 'package:core_domain/journeys/voter_journey.dart';
import 'package:core_domain/models/poll_snapshot.dart';
import 'package:core_domain/models/relay_proof.dart';
import 'package:core_relay/relay_client.dart';
import 'package:core_storage/identity_store.dart';

import '../data/known_polls_store.dart';
import 'ballot_encoding.dart';

/// Maps a registry module-type id to the journey's module enum, or null for
/// non-proof modules (blind, live) and unknown ids.
VoterModule? voterModuleFor(String moduleType) => switch (moduleType) {
  'anon-vote' => VoterModule.anon,
  'approval-vote' => VoterModule.approval,
  'ranked-vote' => VoterModule.ranked,
  'quadratic-vote' => VoterModule.quadratic,
  'survey-vote' => VoterModule.survey,
  _ => null,
};

class VoterPortAdapter implements VoterJourneyPort {
  final ChainReader reader;
  final RelayClient relay;
  final ProofService proofService;
  final IdentityStore identityStore;
  final String pollAddress;
  final VoterModule module;

  /// Reads the poll's R4 results policy; `null` means the poll predates R4
  /// and is treated as live-public (the pre-sealing behavior it shipped with).
  final Future<ResultsPolicy?> Function() readResultsPolicy;

  /// Best-effort local participation record (VOTE home sections). Optional so
  /// tests can omit it; failures never surface into the journey.
  final KnownPollsStore? knownPolls;
  final String pollTitle;
  final String moduleType;

  VoterPortAdapter({
    required this.reader,
    required this.relay,
    required this.proofService,
    required this.identityStore,
    required this.pollAddress,
    required this.module,
    required this.readResultsPolicy,
    this.knownPolls,
    this.pollTitle = '',
    this.moduleType = '',
  });

  @override
  Future<VoterPollView> fetchSnapshot() async {
    final state = await reader.getState(pollAddress);
    List<String> options;
    List<BigInt> results;
    if (module == VoterModule.survey) {
      // The flat IZkPoll reads are documented-degenerate on a survey
      // (question 0 only). The snapshot's option slots stand in for the
      // QUESTIONS — exactly what `Survey.isValidFor` validates against; the
      // ballot/results UI loads the real per-question structure separately.
      final count = await reader.getSurveyQuestionCount(pollAddress);
      options = List.generate(count, (q) => 'Question ${q + 1}');
      results = List.filled(count, BigInt.zero);
    } else {
      options = await reader.getOptions(pollAddress);
      results = await reader.getResults(pollAddress);
    }
    final owner = await reader.getOwner(pollAddress);
    final participants = await reader.getParticipantCount(pollAddress);
    final policy = await readResultsPolicy();
    return VoterPollView(
      snapshot: PollSnapshot(
        address: pollAddress,
        state: state,
        options: options,
        results: results,
        owner: owner,
        participantCount: participants,
      ),
      module: module,
      // Pre-R4 polls have no policy on-chain; they shipped live-public.
      resultsPolicy: policy ?? ResultsPolicy.livePublic,
    );
  }

  @override
  Future<bool> checkEligibility(VoterPollView view) async {
    final seed = await identityStore.read();
    if (seed == null || seed.isEmpty) return false;
    final commitment = await proofService.deriveCommitment(seed);
    final members = await reader.getRegisteredCommitments(pollAddress);
    return members.contains(commitment);
  }

  @override
  Future<void> requestJoin(VoterPollView view) async {
    // Spec §3 principle 6: the voting pass is created lazily on first need —
    // never a prerequisite screen.
    var seed = await identityStore.read();
    if (seed == null || seed.isEmpty) {
      seed = generateIdentitySeed();
      await identityStore.write(seed);
    }
    final commitment = await proofService.deriveCommitment(seed);
    final result = await relay.registerVoter(pollAddress, commitment);
    if (!result.ok) {
      throw Exception(result.error ?? 'join failed');
    }
    await _record(KnownPollStage.joined);
  }

  @override
  Future<RelayProof> generateProof(
    BallotSpec spec,
    VoterPollView view,
    CancellationToken cancellation,
  ) async {
    final seed = await identityStore.read();
    if (seed == null || seed.isEmpty) {
      throw StateError('no identity on this device');
    }
    final members = await reader.getRegisteredCommitments(pollAddress);
    if (cancellation.isCancelled) {
      throw StateError('cancelled');
    }
    if (spec case Survey(:final answers)) {
      // Wide path: the message is a 248-bit keccak commitment that cannot
      // fit an int; the contract recomputes and binds it from calldata.
      return proofService.generateVoteProofWide(
        identitySeed: seed,
        memberCommitments: members,
        message: surveyCommitment(answers).toString(),
        scope: pollAddress,
      );
    }
    return proofService.generateVoteProof(
      identitySeed: seed,
      memberCommitments: members,
      message: encodeBallotMessage(spec),
      scope: pollAddress,
    );
  }

  @override
  Future<VoterReceipt> relayBallot(
    BallotSpec spec,
    RelayProof proof,
    VoterPollView view,
    CancellationToken cancellation,
  ) async {
    final result = await switch (spec) {
      SingleChoice(:final optionIndex) => relay.relayVote(
        pollAddress,
        optionIndex,
        proof,
      ),
      Approval(:final bitmask) => relay.relayApprovalVote(
        pollAddress,
        bitmask.toInt(),
        proof,
      ),
      Ranked(:final ordering) => relay.relayRankedVote(
        pollAddress,
        packRanking(ordering),
        proof,
      ),
      Quadratic(:final alloc) => relay.relayQuadraticVote(
        pollAddress,
        packAlloc(alloc),
        proof,
      ),
      Survey(:final answers) => relay.relaySurveyVote(
        pollAddress,
        answers,
        proof,
      ),
    };
    if (!result.success) {
      throw Exception(result.error ?? 'vote relay failed');
    }
    final receipt = VoterReceipt(
      nullifier: proof.nullifier,
      txHash: result.txHash ?? '',
    );
    await _record(
      KnownPollStage.voted,
      receiptCode: receipt.nullifier,
      receiptTx: receipt.txHash,
    );
    return receipt;
  }

  Future<void> _record(
    KnownPollStage stage, {
    String? receiptCode,
    String? receiptTx,
  }) async {
    final store = knownPolls;
    if (store == null) return;
    try {
      await store.upsert(
        KnownPoll(
          address: pollAddress,
          title: pollTitle,
          moduleType: moduleType,
          stage: stage,
          joinedAtMs: DateTime.now().millisecondsSinceEpoch,
          receiptCode: receiptCode,
          receiptTx: receiptTx,
        ),
      );
    } catch (_) {
      // Local bookkeeping only — never let it break a join or a cast.
    }
  }
}

/// The int `message` a non-survey ballot binds into its proof — exactly what
/// the matching relayer endpoint and contract verify.
int encodeBallotMessage(BallotSpec spec) => switch (spec) {
  SingleChoice(:final optionIndex) => optionIndex,
  Approval(:final bitmask) => bitmask.toInt(),
  Ranked(:final ordering) => packRanking(ordering),
  Quadratic(:final alloc) => packAlloc(alloc),
  Survey() => throw ArgumentError(
    'survey messages are wide — use surveyCommitment()',
  ),
};
