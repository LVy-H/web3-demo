/// A full read of a blind (commit-reveal) poll plus this signer's status in it.
/// `state`: 0 = Registration, 1 = Voting, 2 = Ended.
class BlindSnapshot {
  final String address;
  final int state;
  final List<String> options;
  final List<BigInt> results; // revealed tally per option
  final BigInt participantCount;
  final String owner;
  final BigInt revealDeadline; // unix seconds; 0 until endVoting
  final bool finalized;

  // This signer's status (all false when there is no signer).
  final bool registered;
  final bool committed;
  final bool revealed;

  const BlindSnapshot({
    required this.address,
    required this.state,
    required this.options,
    required this.results,
    required this.participantCount,
    required this.owner,
    required this.revealDeadline,
    required this.finalized,
    required this.registered,
    required this.committed,
    required this.revealed,
  });

  BigInt get totalRevealed =>
      results.fold(BigInt.zero, (a, b) => a + b);

  bool isOwner(String? signer) =>
      signer != null && signer.toLowerCase() == owner.toLowerCase();
}
