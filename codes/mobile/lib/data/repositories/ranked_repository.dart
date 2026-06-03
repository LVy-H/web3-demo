import '../models/poll_snapshot.dart';
import '../services/chain_reader.dart';

/// Data layer for the M4 ranked-choice module (`ranked-vote`). Like the M3
/// approval repository, the on-chain READ surface is identical to M1
/// `ZkAnonVoting` — `ZkRankedVoting` is a structural sibling with the same
/// `IZkPoll` views and the same `VoterRegistered(uint256)` event — so this
/// reuses [ChainReader] as-is, with NO ranked-specific ABI for reads. The
/// ballot/cast path differs (a packed ranking, handled in the view-model +
/// relayer), not here.
///
/// `getResults()` here is the on-chain ROUND-1 FIRST-PREFERENCE tally ONLY (the
/// contract increments only the first choice). It is NOT the winner — the
/// instant-runoff winner is computed off-chain by replaying the full ballots.
/// (Reading `VoteCast(packedRanking)` events to drive the off-chain winner would
/// need a new ABI + getLogs path in [ChainReader]; that is intentionally a
/// follow-up, see the PR notes.)
///
/// ViewModels depend on this abstraction (not on [ChainReader]) so they stay
/// unit-testable with fakes.
abstract class RankedRepository {
  /// A point-in-time read of the poll (phase, options, per-option ROUND-1
  /// first-preference counts, owner, participant count).
  Future<PollSnapshot> fetchPoll(String address);

  /// The poll's Semaphore group (registered identity commitments) — the member
  /// set a ranked proof is built against, and the set the registration pre-check
  /// tests membership in.
  Future<List<String>> fetchGroup(String address);
}

/// On-chain implementation backed by [ChainReader] (JSON-RPC reads). The reads
/// are the same IZkPoll views M1 uses; only the meaning of `results` differs —
/// for ranked polls each entry is a ROUND-1 first-preference count, which the
/// screen renders clearly labelled "First-choice tally — NOT the final winner".
class ChainRankedRepository implements RankedRepository {
  final ChainReader reader;
  const ChainRankedRepository(this.reader);

  @override
  Future<List<String>> fetchGroup(String address) =>
      reader.getRegisteredCommitments(address);

  @override
  Future<PollSnapshot> fetchPoll(String address) async {
    // Independent view calls — fetch concurrently (mirrors ChainApprovalRepository).
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
