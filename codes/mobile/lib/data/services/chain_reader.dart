import 'package:http/http.dart' as http;
import 'package:wallet/wallet.dart' show EthereumAddress; // web3dart 3.x moved it here
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
  final ContractAbi? _blindAbi;
  final EthereumAddress _registryAddress;

  /// Per-call timeout so a hung RPC endpoint can't block the UI indefinitely.
  final Duration readTimeout;

  ChainReader({
    required String rpcUrl,
    required String izkPollAbiJson,
    required String registryAbiJson,
    required String anonVotingAbiJson,
    required String registryAddress,
    String? blindVotingAbiJson,
    http.Client? httpClient,
    this.readTimeout = const Duration(seconds: 10),
  })  : client = Web3Client(rpcUrl, httpClient ?? http.Client()),
        _pollAbi = ContractAbi.fromJson(izkPollAbiJson, 'IZkPoll'),
        _registryAbi = ContractAbi.fromJson(registryAbiJson, 'PollRegistry'),
        _anonAbi = ContractAbi.fromJson(anonVotingAbiJson, 'ZkAnonVoting'),
        _blindAbi = blindVotingAbiJson == null
            ? null
            : ContractAbi.fromJson(blindVotingAbiJson, 'ZkBlindVoting'),
        _registryAddress = EthereumAddress.fromHex(registryAddress);

  ContractAbi get _blind => _blindAbi ?? (throw StateError(
      'ChainReader was built without blindVotingAbiJson'));

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
    ).timeout(readTimeout);
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
    return (r.first as EthereumAddress).eip55With0x;
  }

  Future<BigInt> getParticipantCount(String pollAddress) async {
    final r = await _read(
        _pollAbi, EthereumAddress.fromHex(pollAddress), 'getParticipantCount');
    return r.first as BigInt;
  }

  /// Public receipt check: has this nullifier (decimal string) voted in the
  /// poll? Proves participation without revealing the option. Mirrors the web
  /// Verify page (`isNullifierUsed` on ZkAnonVoting).
  Future<bool> isNullifierUsed(String pollAddress, String nullifier) async {
    final r = await _read(
      _anonAbi,
      EthereumAddress.fromHex(pollAddress),
      'isNullifierUsed',
      [BigInt.parse(nullifier)],
    );
    return r.first as bool;
  }

  /// Reconstruct the Semaphore group: all `identityCommitment`s from the poll's
  /// `VoterRegistered(uint256)` events from genesis. This is what a vote proof is
  /// built against (mirrors the web client's useGroupSync). Returns decimal strings.
  Future<List<String>> getRegisteredCommitments(String pollAddress) async {
    final contract =
        DeployedContract(_anonAbi, EthereumAddress.fromHex(pollAddress));
    final event = contract.event('VoterRegistered');
    final logs = await client
        .getLogs(FilterOptions.events(
          contract: contract,
          event: event,
          fromBlock: const BlockNum.genesis(),
          toBlock: const BlockNum.current(),
        ))
        .timeout(readTimeout);
    return logs
        .map((log) {
          final decoded =
              event.decodeResults(log.topics ?? const [], log.data ?? '0x');
          return decoded.isEmpty ? null : (decoded.first as BigInt).toString();
        })
        .whereType<String>()
        .toList();
  }

  // ── ZkBlindVoting (M2) reads ────────────────────────────────────────────────

  /// Timestamp (unix seconds) after which reveals close. 0 until `endVoting`.
  Future<BigInt> getRevealDeadline(String pollAddress) async {
    final r = await _read(
        _blind, EthereumAddress.fromHex(pollAddress), 'getRevealDeadline');
    return r.first as BigInt;
  }

  Future<bool> isFinalized(String pollAddress) async {
    final r =
        await _read(_blind, EthereumAddress.fromHex(pollAddress), 'isFinalized');
    return r.first as bool;
  }

  /// Has [voter] committed a (hidden) vote in this blind poll?
  Future<bool> hasVoted(String pollAddress, String voter) async {
    final r = await _read(_blind, EthereumAddress.fromHex(pollAddress),
        'hasVoted', [EthereumAddress.fromHex(voter)]);
    return r.first as bool;
  }

  /// Has [voter] revealed their committed vote?
  Future<bool> hasRevealed(String pollAddress, String voter) async {
    final r = await _read(_blind, EthereumAddress.fromHex(pollAddress),
        'hasRevealed', [EthereumAddress.fromHex(voter)]);
    return r.first as bool;
  }

  /// Is [voter] registered to vote in this blind poll?
  Future<bool> isRegistered(String pollAddress, String voter) async {
    final r = await _read(_blind, EthereumAddress.fromHex(pollAddress),
        'isRegistered', [EthereumAddress.fromHex(voter)]);
    return r.first as bool;
  }

  // ── PollRegistry ──────────────────────────────────────────────────────────

  Future<List<PollInfo>> getAllPolls() async {
    final r = await _read(_registryAbi, _registryAddress, 'getAllPolls');
    final rows = r.first as List;
    return rows.map((row) => PollInfo.fromTuple(row as List)).toList();
  }

  void dispose() => client.dispose();
}
