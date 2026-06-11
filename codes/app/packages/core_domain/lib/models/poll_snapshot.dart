/// A point-in-time read of a single poll's on-chain state, assembled from the
/// IZkPoll view calls. `state`: 0 = Registration, 1 = Voting, 2 = Ended.
class PollSnapshot {
  final String address;
  final int state;
  final List<String> options;
  final List<BigInt> results;
  final String owner;
  final BigInt participantCount;

  const PollSnapshot({
    required this.address,
    required this.state,
    required this.options,
    required this.results,
    required this.owner,
    required this.participantCount,
  });

  String get phaseLabel => switch (state) {
        0 => 'Registration',
        1 => 'Voting',
        2 => 'Ended',
        _ => 'Unknown',
      };

  BigInt get totalVotes =>
      results.fold(BigInt.zero, (sum, v) => sum + v);
}
