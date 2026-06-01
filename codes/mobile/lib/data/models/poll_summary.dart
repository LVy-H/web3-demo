/// A cheap 2-call read of a poll for the browse list: just enough to show the
/// real lifecycle phase and live vote tally on each card, without the full
/// [PollSnapshot] (which costs 5 view calls per poll). `state`: 0 = Registration,
/// 1 = Voting, 2 = Ended — same enum as IZkPoll.PollState.
class PollSummary {
  final int state;
  final BigInt totalVotes;
  const PollSummary({required this.state, required this.totalVotes});
}
