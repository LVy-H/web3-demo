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
  final EthereumAddress _registryAddress;

  ChainReader({
    required String rpcUrl,
    required String izkPollAbiJson,
    required String registryAbiJson,
    required String registryAddress,
    http.Client? httpClient,
  })  : client = Web3Client(rpcUrl, httpClient ?? http.Client()),
        _pollAbi = ContractAbi.fromJson(izkPollAbiJson, 'IZkPoll'),
        _registryAbi = ContractAbi.fromJson(registryAbiJson, 'PollRegistry'),
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

  // ── PollRegistry ──────────────────────────────────────────────────────────

  Future<List<PollInfo>> getAllPolls() async {
    final r = await _read(_registryAbi, _registryAddress, 'getAllPolls');
    final rows = r.first as List;
    return rows.map((row) => PollInfo.fromTuple(row as List)).toList();
  }

  void dispose() => client.dispose();
}
