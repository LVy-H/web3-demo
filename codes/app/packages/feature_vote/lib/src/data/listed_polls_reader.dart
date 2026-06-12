/// R4 registry reads the pre-R4 core_chain reader cannot do yet:
/// `getListedPolls()` (the opt-in public directory) and the per-poll
/// `resultsPolicy()` (sealed-until-close vs live-public).
///
/// The R4 PollRegistry ABI is INJECTED as a string by the app shell (which
/// owns the asset copy at `apps/tessera/assets/abi/PollRegistry.json`) — no
/// asset path is hardcoded here, so the package stays testable and the app
/// keeps one source of truth for the ABI. When R3/R4 refreshes core_chain's
/// packaged ABI set, fold these reads into ChainReader and delete this file.
library;

// web3dart (and the wallet package's EthereumAddress) reach feature_vote ONLY
// through core_chain — a declared dependency whose public API already exposes
// Web3Client (`ChainReader.client`), which callers inject here. feature_vote's
// pubspec is frozen by the R3 file-ownership rule; declare both directly when
// the freeze lifts.
// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';

import 'package:wallet/wallet.dart' show EthereumAddress;
import 'package:web3dart/web3dart.dart';

import 'package:core_domain/journeys/policy.dart';

/// One row of the public directory (a poll that opted in to being listed).
class ListedPoll {
  final String address;
  final String moduleType;
  final String title;
  final String description;

  const ListedPoll({
    required this.address,
    required this.moduleType,
    required this.title,
    required this.description,
  });
}

/// Accepts either a bare ABI array string or a full hardhat artifact
/// (`{"abi": [...]}`) and returns the bare array string web3dart wants.
String _abiArray(String abiJson) {
  final decoded = jsonDecode(abiJson);
  return jsonEncode(decoded is Map ? decoded['abi'] : decoded);
}

/// Reads the R4 registry surface over an injected [Web3Client] (production:
/// `ChainReader.client`, so the app keeps one RPC connection).
class ListedPollsReader {
  final Web3Client client;
  final EthereumAddress _registry;
  final ContractAbi _abi;
  final Duration timeout;

  ListedPollsReader({
    required String registryAbiJson,
    required this.client,
    required String registryAddress,
    this.timeout = const Duration(seconds: 10),
  }) : _abi = ContractAbi.fromJson(_abiArray(registryAbiJson), 'PollRegistry'),
       _registry = EthereumAddress.fromHex(registryAddress);

  /// The publicly listed polls (`getListedPolls()`), newest first.
  Future<List<ListedPoll>> fetchListed() async {
    final contract = DeployedContract(_abi, _registry);
    final result = await client
        .call(
          contract: contract,
          function: contract.function('getListedPolls'),
          params: const [],
        )
        .timeout(timeout);
    final rows = (result.first as List).cast<List<dynamic>>();
    return [
      for (final row in rows.reversed)
        ListedPoll(
          address: (row[0] as EthereumAddress).eip55With0x,
          moduleType: row[1] as String,
          title: row[2] as String,
          description: row[3] as String,
        ),
    ];
  }
}

/// Minimal ABI for the R4 `resultsPolicy()` view every R4 poll exposes
/// (`uint8`: 0 = sealed-until-close, 1 = live-public). Pre-R4 polls don't
/// have the function — the call reverts and reads back as `null`.
const String _resultsPolicyAbi =
    '[{"inputs":[],"name":"resultsPolicy","outputs":[{"internalType":"uint8",'
    '"name":"","type":"uint8"}],"stateMutability":"view","type":"function"}]';

/// Reads a poll's results policy via the R4 surface where available.
class ResultsPolicyReader {
  final Web3Client client;
  final Duration timeout;
  final ContractAbi _abi = ContractAbi.fromJson(_resultsPolicyAbi, 'IZkPollR4');

  ResultsPolicyReader({
    required this.client,
    this.timeout = const Duration(seconds: 10),
  });

  /// The poll's policy, or `null` when the poll predates R4 (no
  /// `resultsPolicy()` — callers treat that as live-public for compat with
  /// polls created before sealed-by-default existed).
  Future<ResultsPolicy?> read(String pollAddress) async {
    try {
      final contract = DeployedContract(
        _abi,
        EthereumAddress.fromHex(pollAddress),
      );
      final result = await client
          .call(
            contract: contract,
            function: contract.function('resultsPolicy'),
            params: const [],
          )
          .timeout(timeout);
      final value = (result.first as BigInt).toInt();
      return value == 1
          ? ResultsPolicy.livePublic
          : ResultsPolicy.sealedUntilClose;
    } catch (_) {
      return null; // pre-R4 poll (or unreadable): caller decides the fallback
    }
  }
}
