import '../models/poll_snapshot.dart';
import '../services/chain_reader.dart';

/// Data layer for the M5 quadratic-voting module (`quadratic-vote`). Like the
/// M3 approval / M4 ranked repositories, the on-chain READ surface is identical
/// to M1 `ZkAnonVoting` — `ZkQuadraticVoting` is a structural sibling with the
/// same `IZkPoll` views and the same `VoterRegistered(uint256)` event — so this
/// reuses [ChainReader] as-is, with NO quadratic-specific ABI for reads. The
/// ballot/cast path differs (a packed allocation, handled in the view-model +
/// relayer), not here.
///
/// `getResults()` here IS the authoritative outcome (contrast M4 ranked, where
/// it is only a round-1 first-preference count): each entry is the on-chain SUM
/// of the votes `vᵢ` allocated to that option across all ballots, and the option
/// with the highest entry is the winner — there is NO off-chain replay.
///
/// ViewModels depend on this abstraction (not on [ChainReader]) so they stay
/// unit-testable with fakes.
abstract class QuadraticRepository {
  /// A point-in-time read of the poll (phase, options, AUTHORITATIVE per-option
  /// vote sums, owner, participant count).
  Future<PollSnapshot> fetchPoll(String address);

  /// The poll's Semaphore group (registered identity commitments) — the member
  /// set a quadratic proof is built against, and the set the registration
  /// pre-check tests membership in.
  Future<List<String>> fetchGroup(String address);
}

/// On-chain implementation backed by [ChainReader] (JSON-RPC reads). The reads
/// are the same IZkPoll views M1 uses; only the meaning of `results` differs —
/// for quadratic polls each entry is the authoritative per-option vote sum, and
/// the screen renders it as the final tally with the leader crowned.
class ChainQuadraticRepository implements QuadraticRepository {
  final ChainReader reader;
  const ChainQuadraticRepository(this.reader);

  @override
  Future<List<String>> fetchGroup(String address) =>
      reader.getRegisteredCommitments(address);

  @override
  Future<PollSnapshot> fetchPoll(String address) async {
    // Independent view calls — fetch concurrently (mirrors ChainRankedRepository).
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
