import 'format.dart';

/// How the current user relates to a poll's owner — drives the "RUN BY" label
/// and the permissions explainer's wording.
enum PollOwnerKind {
  /// The relayer owns it (a wallet-free sponsored poll) — no single person runs it.
  sponsored,

  /// The current user owns it (created with their own signer/wallet).
  you,

  /// A specific other address created it.
  other,
}

/// A meaningful ownership descriptor for a poll. [label] is display-ready;
/// [address] is the raw owner for copy/verify.
class PollOwner {
  final PollOwnerKind kind;
  final String label;
  final String address;
  const PollOwner(this.kind, this.label, this.address);
}

/// Resolve a poll's raw owner address into a meaningful label — the inverse of
/// the wallet-free confusion where every sponsored poll shows the same relayer
/// hex string. Pure (case-insensitive address compare) so it's unit-tested.
PollOwner pollOwner({
  required String owner,
  String? relayerAddress,
  String? myAddress,
}) {
  String norm(String? a) => (a ?? '').trim().toLowerCase();
  final o = norm(owner);
  if (o.isNotEmpty && norm(relayerAddress) == o) {
    return PollOwner(PollOwnerKind.sponsored, 'Sponsored · relayer-run', owner);
  }
  if (o.isNotEmpty && myAddress != null && norm(myAddress) == o) {
    return PollOwner(PollOwnerKind.you, 'You', owner);
  }
  return PollOwner(PollOwnerKind.other, shortAddr(owner), owner);
}
