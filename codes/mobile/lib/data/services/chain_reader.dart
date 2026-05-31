import 'package:http/http.dart' as http;
import 'package:web3dart/web3dart.dart';

import '../models/poll_info.dart';

/// Read-only on-chain access via JSON-RPC `eth_call` + web3dart's ABI codec.
///
/// Covers the IZkPoll read surface the recurring-member app needs (poll phase,
/// options, tally, owner, participant count) plus `PollRegistry.getAllPolls()`.
/// Reads are NOT affected by the local MockSemaphoreVerifier — only proof
/// verification is — so these decode correctly against local Hardhat.
///
/// Construct with the ABI JSON *arrays* (extract `.abi` from the hardhat
/// artifacts) so the loading mechanism (assets/file) stays out of this class.
class ChainReader {
  final Web3Client client;
  final ContractAbi _pollAbi;
  final ContractAbi _registryAbi;
  final ContractAbi _anonAbi;
  final EthereumAddress _registryAddress;

  ChainReader({
    required String rpcUrl,
    required String izkPollAbiJson,
    required String registryAbiJson,
    required String anonVotingAbiJson,
    required String registryAddress,
    http.Client? httpClient,
  })  : client = Web3Client(rpcUrl, httpClient ?? http.Client()),
        _pollAbi = ContractAbi.fromJson(izkPollAbiJson, 'IZkPoll'),
        _registryAbi = ContractAbi.fromJson(registryAbiJson, 'PollRegistry'),
        _anonAbi = ContractAbi.fromJson(anonVotingAbiJson, 'ZkAnonVoting'),
        _registryAddress = EthereumAddress.fromHex(registryAddress);

  Future<List<dynamic>> _read(
    ContractAbi abi,
    EthereumAddress address,
    String fn, [
    List<dynamic> params = const [],
  ]) {
    final contract = DeployedContract(abi, address);
    return client.call(
      contract: contract,
      function: contract.function(fn),
      params: params,
    );
  }

  // ── IZkPoll reads ─────────────────────────────────────────────────────────

  /// Poll phase: 0 = Registration, 1 = Voting, 2 = Ended (enum PollState).
  Future<int> getState(String pollAddress) async {
    final r = await _read(_pollAbi, EthereumAddress.fromHex(pollAddress), 'getState');
    return (r.first as BigInt).toInt();
  }

  Future<List<String>> getOptions(String pollAddress) async {
    final r = await _read(_pollAbi, EthereumAddress.fromHex(pollAddress), 'getOptions');
    return (r.first as List).cast<String>();
  }

  /// Per-option vote tally.
  Future<List<BigInt>> getResults(String pollAddress) async {
    final r = await _read(_pollAbi, EthereumAddress.fromHex(pollAddress), 'getResults');
    return (r.first as List).cast<BigInt>();
  }

  Future<String> getOwner(String pollAddress) async {
    final r = await _read(_pollAbi, EthereumAddress.fromHex(pollAddress), 'owner');
    return (r.first as EthereumAddress).hexEip55;
  }

  Future<BigInt> getParticipantCount(String pollAddress) async {
    final r = await _read(
        _pollAbi, EthereumAddress.fromHex(pollAddress), 'getParticipantCount');
    return r.first as BigInt;
  }

  /// Reconstruct the Semaphore group: all `identityCommitment`s from the poll's
  /// `VoterRegistered(uint256)` events from genesis. This is what a vote proof is
  /// built against (mirrors the web client's useGroupSync). Returns decimal strings.
  Future<List<String>> getRegisteredCommitments(String pollAddress) async {
    final contract =
        DeployedContract(_anonAbi, EthereumAddress.fromHex(pollAddress));
    final event = contract.event('VoterRegistered');
    final logs = await client.getLogs(FilterOptions.events(
      contract: contract,
      event: event,
      fromBlock: const BlockNum.genesis(),
      toBlock: const BlockNum.current(),
    ));
    return logs.map((log) {
      final decoded = event.decodeResults(log.topics ?? const [], log.data ?? '0x');
      return (decoded.first as BigInt).toString();
    }).toList();
  }

  // ── PollRegistry ──────────────────────────────────────────────────────────

  Future<List<PollInfo>> getAllPolls() async {
    final r = await _read(_registryAbi, _registryAddress, 'getAllPolls');
    final rows = r.first as List;
    return rows.map((row) => PollInfo.fromTuple(row as List)).toList();
  }

  void dispose() => client.dispose();
}
