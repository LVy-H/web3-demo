import '../models/poll_info.dart';
import '../models/poll_snapshot.dart';
import '../models/poll_summary.dart';
import '../services/chain_reader.dart';

/// Single source of truth for poll data (MVVM data layer). ViewModels depend on
/// this abstraction, not on [ChainReader], so they're unit-testable with fakes.
abstract class PollRepository {
  Future<List<PollInfo>> fetchPolls();
  Future<PollSnapshot> fetchPoll(String address);

  /// Cheap per-poll read for the browse list: lifecycle state + total votes
  /// (2 view calls, vs the 5 of [fetchPoll]).
  Future<PollSummary> fetchSummary(String address);

  /// The poll's Semaphore group (registered identity commitments) — the member
  /// set a vote proof is built against.
  Future<List<String>> fetchGroup(String address);
}

/// On-chain implementation backed by [ChainReader] (JSON-RPC reads).
class ChainPollRepository implements PollRepository {
  final ChainReader reader;
  const ChainPollRepository(this.reader);

  @override
  Future<List<PollInfo>> fetchPolls() => reader.getAllPolls();

  @override
  Future<PollSummary> fetchSummary(String address) async {
    // Two independent view calls — fetch concurrently.
    final r = await Future.wait([
      reader.getState(address),
      reader.getResults(address),
    ]);
    final results = r[1] as List<BigInt>;
    return PollSummary(
      state: r[0] as int,
      totalVotes: results.fold(BigInt.zero, (sum, v) => sum + v),
    );
  }

  @override
  Future<List<String>> fetchGroup(String address) =>
      reader.getRegisteredCommitments(address);

  @override
  Future<PollSnapshot> fetchPoll(String address) async {
    // Independent view calls — fetch concurrently.
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
