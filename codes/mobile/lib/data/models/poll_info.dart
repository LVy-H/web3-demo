import 'package:wallet/wallet.dart' show EthereumAddress; // web3dart 3.x moved it here

/// A poll as listed by `PollRegistry.getAllPolls()`. Mirrors the registry's
/// `PollInfo` struct and the frontend `PollInfo` interface
/// (codes/frontend/src/hooks/useRegistry.ts).
class PollInfo {
  final String pollAddress;
  final String moduleType;
  final String title;
  final String description;
  final String creator;
  final BigInt createdAt;

  const PollInfo({
    required this.pollAddress,
    required this.moduleType,
    required this.title,
    required this.description,
    required this.creator,
    required this.createdAt,
  });

  /// Build from a decoded ABI tuple `(address, string, string, string, address,
  /// uint256)` as returned by web3dart for the `getAllPolls` struct array.
  factory PollInfo.fromTuple(List<dynamic> t) => PollInfo(
        pollAddress: (t[0] as EthereumAddress).eip55With0x,
        moduleType: t[1] as String,
        title: t[2] as String,
        description: t[3] as String,
        creator: (t[4] as EthereumAddress).eip55With0x,
        createdAt: t[5] as BigInt,
      );
}
