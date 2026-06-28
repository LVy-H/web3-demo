/// Server-backed [VoterJourneyPort] over the Phase-2 REST API
/// (`codes/server`) — the OPEN-BALLOT voter path. Mirrors [VoterPortAdapter]
/// but talks to the self-hosted bulletin-board server (Decisions + Ballots)
/// instead of the chain/relayer + ZK prover.
///
/// OPEN BALLOTS CARRY NO ZK PROOF. The whole point of the open-ballot path is
/// that the server is the integrity anchor (signed receipt chain), not a
/// Semaphore group. So:
///   - [checkEligibility] is always `true` (open mode: anyone with the link
///     can cast; the server enforces decision-closed / max-participants).
///   - [requestJoin] is a no-op (there is no group to join).
///   - [generateProof] returns a trivial PLACEHOLDER [RelayProof] — it does
///     NOT call any ProofService (which throws on unsupported platforms). The
///     placeholder satisfies the journey machine's `proving → cast` shape; its
///     fields are never sent to the server (the cast carries only the payload).
///   - [relayBallot] maps the [BallotSpec] to the server payload union, derives
///     a per-(voter, decision) idempotency key, POSTs `/ballots`, and maps the
///     server receipt to a [VoterReceipt].
///
/// Receipt mapping (PRAGMATIC SHORTCUT): the server receipt is
/// `{ballotHash, logPosition, runningRoot, serverSig}`; [VoterReceipt] is
/// `{nullifier, txHash}`. We map `nullifier := ballotHash` (the voter's stable
/// "this is my ballot" mark) and `txHash := runningRoot` (the chain head the
/// cast advanced to — the verifiable anchor). TODO: a proper `ServerReceipt`
/// model (carrying logPosition + serverSig) is the clean fix; [VoterReceipt]
/// is reused here so the kept screens render unchanged.
library;

import 'package:core_crypto/crypto/idempotency_key.dart';
import 'package:core_domain/journeys/journey.dart';
import 'package:core_domain/journeys/policy.dart';
import 'package:core_domain/journeys/voter_journey.dart';
import 'package:core_domain/models/poll_snapshot.dart';
import 'package:core_domain/models/relay_proof.dart';
import 'package:core_relay/server_client.dart';
import 'package:core_storage/identity_store.dart';

/// Maps a server `method` string to the voter journey's module enum, or null
/// for an unknown method.
VoterModule? voterModuleForServerMethod(String method) => switch (method) {
  'single' => VoterModule.anon,
  'approval' => VoterModule.approval,
  'ranked' => VoterModule.ranked,
  'quadratic' => VoterModule.quadratic,
  'survey' => VoterModule.survey,
  _ => null,
};

/// Server decision `state` string → [PollSnapshot.state] int
/// (0=registration/pre, 1=voting, 2=ended): draft→0, open→1, everything
/// terminal (closed | challenge | published | cancelled)→2.
int voterPhaseForState(String state) => switch (state) {
  'draft' => 0,
  'open' => 1,
  _ => 2,
};

/// The placeholder proof open ballots carry — open ballots have NO ZK proof,
/// so this never reaches the server (the cast sends only the payload). It
/// exists only to satisfy the journey machine's proving→cast state shape.
const RelayProof openBallotPlaceholderProof = RelayProof(
  merkleTreeDepth: 0,
  merkleTreeRoot: '0',
  nullifier: '0',
  message: '0',
  scope: '0',
  points: <String>[],
);

class ServerVoterPortAdapter implements VoterJourneyPort {
  final ServerClient client;
  final IdentityStore identityStore;

  /// The decision id (the open-ballot server's analogue of a poll address).
  final String decisionId;

  /// Resolved-on-chain analogue: the server's `method`, mapped to the journey
  /// module the host screen already resolved.
  final VoterModule module;

  ServerVoterPortAdapter({
    required this.client,
    required this.identityStore,
    required this.decisionId,
    required this.module,
  });

  @override
  Future<VoterPollView> fetchSnapshot() async {
    final d = await client.getDecision(decisionId);
    final opts = d['options'];
    final options = opts is List
        ? opts.map((e) => e.toString()).toList()
        : <String>[];
    final state = d['state'] is String ? d['state'] as String : 'draft';
    final turnout = _asBigInt(d['turnout']);
    // Open ballots are individually published (the receipt chain), but the
    // per-option tally is the /results read, not part of the snapshot; the
    // ballot/results UI loads it separately. Snapshot results stay zeroed.
    final results = List<BigInt>.filled(options.length, BigInt.zero);
    // Open-ballot decisions are 'live' or 'sealed' on the server; the journey
    // policy is livePublic only when the server says 'live', else sealed.
    final policy = d['resultsPolicy'] == 'live'
        ? ResultsPolicy.livePublic
        : ResultsPolicy.sealedUntilClose;
    return VoterPollView(
      snapshot: PollSnapshot(
        address: decisionId,
        state: voterPhaseForState(state),
        options: options,
        results: results,
        // Open mode has no on-chain owner; the convener id isn't public.
        owner: '',
        participantCount: turnout,
      ),
      module: module,
      resultsPolicy: policy,
    );
  }

  @override
  Future<bool> checkEligibility(VoterPollView view) async {
    // Open mode: anyone with the link can cast. The server enforces the real
    // gates (decision-closed, max-participants) at cast time.
    return true;
  }

  @override
  Future<void> requestJoin(VoterPollView view) async {
    // Open mode: no group to join. Ensure a local identity seed exists so the
    // idempotency key is stable for this device (lazy create — spec §3).
    final seed = await identityStore.read();
    if (seed == null || seed.isEmpty) {
      await identityStore.write(generateIdentitySeed());
    }
  }

  @override
  Future<RelayProof> generateProof(
    BallotSpec spec,
    VoterPollView view,
    CancellationToken cancellation,
  ) async {
    // Open ballots carry NO ZK proof. Return the trivial placeholder WITHOUT
    // touching any ProofService (which throws on platforms that can't prove) —
    // the placeholder is never sent; the cast carries only the payload.
    return openBallotPlaceholderProof;
  }

  @override
  Future<VoterReceipt> relayBallot(
    BallotSpec spec,
    RelayProof proof,
    VoterPollView view,
    CancellationToken cancellation,
  ) async {
    // Stable per-(voter, decision) key so a retry by the same voter dedupes to
    // one ballot (the server returns the same receipt on an identical retry).
    var seed = await identityStore.read();
    if (seed == null || seed.isEmpty) {
      seed = generateIdentitySeed();
      await identityStore.write(seed);
    }
    final idempotencyKey = ballotIdempotencyKey(
      identitySeed: seed,
      decisionId: decisionId,
    );

    final Map<String, dynamic> response;
    try {
      response = await client.castBallot(
        decisionId: decisionId,
        payload: _payloadFor(spec),
        idempotencyKey: idempotencyKey,
      );
    } on ServerException catch (e) {
      // Surface server semantics as the journey's relay failure cause — the
      // copy distinguishes closed / full / generic so the UI can react.
      if (e.isDecisionClosed) {
        throw Exception('Voting has closed — this ballot was not counted.');
      }
      if (e.isMaxParticipants) {
        throw Exception('This decision is full — the cap has been reached.');
      }
      throw Exception(e.message);
    }

    final receipt = response['receipt'];
    if (receipt is! Map) {
      throw Exception('The server did not return a receipt.');
    }
    final ballotHash = receipt['ballotHash']?.toString() ?? '';
    final runningRoot = receipt['runningRoot']?.toString() ?? '';
    // PRAGMATIC: VoterReceipt has no server-receipt fields, so map
    // nullifier := ballotHash (the voter's ballot mark) and
    // txHash := runningRoot (the anchored chain head). TODO: a ServerReceipt
    // model carrying logPosition + serverSig is the clean fix.
    return VoterReceipt(nullifier: ballotHash, txHash: runningRoot);
  }

  /// Map a typed [BallotSpec] to the server's ballot payload union.
  static Map<String, dynamic> _payloadFor(BallotSpec spec) => switch (spec) {
    SingleChoice(:final optionIndex) => {
      'kind': 'single',
      'choice': optionIndex,
    },
    Approval(:final bitmask) => {
      'kind': 'approval',
      'choices': _bitmaskToIndices(bitmask),
    },
    Ranked(:final ordering) => {'kind': 'ranked', 'ranking': ordering},
    Quadratic(:final alloc) => {'kind': 'quadratic', 'votes': alloc},
    Survey(:final answers) => {
      'kind': 'survey',
      // The open-ballot survey method is a multi-select index list (like
      // approval); a non-zero answer word selects that question's option.
      'choices': [
        for (var i = 0; i < answers.length; i++)
          if (answers[i] > BigInt.zero) i,
      ],
    },
  };

  /// Approval ballots travel as a bitmask in the journey; the server wants the
  /// explicit list of approved option indices.
  static List<int> _bitmaskToIndices(BigInt bitmask) {
    final indices = <int>[];
    var bit = 0;
    var remaining = bitmask;
    while (remaining > BigInt.zero) {
      if (remaining.isOdd) indices.add(bit);
      remaining = remaining >> 1;
      bit++;
    }
    return indices;
  }

  static BigInt _asBigInt(Object? v) => switch (v) {
    int() => BigInt.from(v),
    num() => BigInt.from(v.toInt()),
    String() => BigInt.tryParse(v) ?? BigInt.zero,
    _ => BigInt.zero,
  };
}
