import 'package:wallet/wallet.dart'
    show EthereumAddress; // web3dart 3.x moved it here

/// A poll as listed by `PollRegistry.getAllPolls()` / `getListedPolls()` /
/// `getPollInfo(address)`. Mirrors the R4 registry's `PollInfo` struct
/// (PR #108: trailing `uint8 visibility` appended last so the leading field
/// order stays stable for positional decoders).
class PollInfo {
  /// `PollRegistry` visibility values (R4): unlisted is the DEFAULT — the
  /// poll is link/QR/code-access only and compliant directories must not
  /// present it.
  static const int visibilityUnlisted = 0;

  /// Creation-time opt-in: the poll appears in `getListedPolls()`.
  static const int visibilityListed = 1;

  final String pollAddress;
  final String moduleType;
  final String title;
  final String description;
  final String creator;
  final BigInt createdAt;

  /// Discovery privacy flag: [visibilityUnlisted] (default) or
  /// [visibilityListed]. NOT content privacy — chain data stays public; the
  /// flag only governs compliant directories (PR #108 design decision 2).
  final int visibility;

  const PollInfo({
    required this.pollAddress,
    required this.moduleType,
    required this.title,
    required this.description,
    required this.creator,
    required this.createdAt,
    this.visibility = visibilityUnlisted,
  });

  /// Build from a decoded ABI tuple `(address, string, string, string,
  /// address, uint256, uint8)` as returned by web3dart for the registry's
  /// struct returns. Tolerates a pre-R4 6-field tuple (no trailing
  /// `visibility`) by defaulting to unlisted — the contract's own default.
  factory PollInfo.fromTuple(List<dynamic> t) => PollInfo(
    pollAddress: (t[0] as EthereumAddress).eip55With0x,
    moduleType: t[1] as String,
    title: t[2] as String,
    description: t[3] as String,
    creator: (t[4] as EthereumAddress).eip55With0x,
    createdAt: t[5] as BigInt,
    visibility: t.length > 6 ? (t[6] as BigInt).toInt() : visibilityUnlisted,
  );

  /// True when the poll opted in to the public directory.
  bool get isListed => visibility == visibilityListed;
}
