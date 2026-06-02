import '../models/poll_snapshot.dart';
import '../services/chain_reader.dart';

/// Data layer for the M3 approval-vote module (`approval-vote`). The on-chain
/// read surface is identical to M1 `ZkAnonVoting` — `ZkApprovalVoting` is a
/// structural sibling with the same `IZkPoll` views and the same
/// `VoterRegistered(uint256)` event — so this reuses [ChainReader] as-is (no
/// approval-specific ABI needed for reads). The only behavioral difference lives
/// in the ballot/cast path (a bitmask, handled in the view-model + relayer), not
/// here.
///
/// ViewModels depend on this abstraction (not on [ChainReader]) so they stay
/// unit-testable with fakes.
abstract class ApprovalRepository {
  /// A point-in-time read of the poll (phase, options, per-option approvals,
  /// owner, participant count).
  Future<PollSnapshot> fetchPoll(String address);

  /// The poll's Semaphore group (registered identity commitments) — the member
  /// set an approval proof is built against, and the set the registration
  /// pre-check tests membership in.
  Future<List<String>> fetchGroup(String address);
}

/// On-chain implementation backed by [ChainReader] (JSON-RPC reads). The reads
/// are the same IZkPoll views M1 uses; only the meaning of `results` differs —
/// for approval polls each entry is an APPROVAL count, so the per-option counts
/// can sum past the voter count (a voter approving 3 options adds 3 across the
/// tally). The screen divides by `participantCount` (voters), not the sum.
class ChainApprovalRepository implements ApprovalRepository {
  final ChainReader reader;
  const ChainApprovalRepository(this.reader);

  @override
  Future<List<String>> fetchGroup(String address) =>
      reader.getRegisteredCommitments(address);

  @override
  Future<PollSnapshot> fetchPoll(String address) async {
    // Independent view calls — fetch concurrently (mirrors ChainPollRepository).
    final results = await Future.wait([
      reader.getState(address),
      reader.getOptions(address),
      reader.getResults(address),
      reader.getOwner(address),
      reader.getParticipantCount(address),
    ]);
    return PollSnapshot(
      address: address,
      state: results[0] as int,
      options: results[1] as List<String>,
      results: results[2] as List<BigInt>,
      owner: results[3] as String,
      participantCount: results[4] as BigInt,
    );
  }
}
