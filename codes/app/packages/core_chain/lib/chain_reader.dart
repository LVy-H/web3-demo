import 'package:http/http.dart' as http;
import 'package:wallet/wallet.dart'
    show EthereumAddress; // web3dart 3.x moved it here
import 'package:web3dart/json_rpc.dart' show RPCError;
import 'package:web3dart/web3dart.dart';

import 'package:core_domain/models/poll_info.dart';

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
  final ContractAbi? _surveyAbi;
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
    String? surveyVotingAbiJson,
    http.Client? httpClient,
    this.readTimeout = const Duration(seconds: 10),
  }) : client = Web3Client(rpcUrl, httpClient ?? http.Client()),
       _pollAbi = ContractAbi.fromJson(izkPollAbiJson, 'IZkPoll'),
       _registryAbi = ContractAbi.fromJson(registryAbiJson, 'PollRegistry'),
       _anonAbi = ContractAbi.fromJson(anonVotingAbiJson, 'ZkAnonVoting'),
       _blindAbi = blindVotingAbiJson == null
           ? null
           : ContractAbi.fromJson(blindVotingAbiJson, 'ZkBlindVoting'),
       _surveyAbi = surveyVotingAbiJson == null
           ? null
           : ContractAbi.fromJson(surveyVotingAbiJson, 'ZkSurveyVoting'),
       _registryAddress = EthereumAddress.fromHex(registryAddress);

  ContractAbi get _blind =>
      _blindAbi ??
      (throw StateError('ChainReader was built without blindVotingAbiJson'));

  ContractAbi get _survey =>
      _surveyAbi ??
      (throw StateError('ChainReader was built without surveyVotingAbiJson'));

  Future<List<dynamic>> _read(
    ContractAbi abi,
    EthereumAddress address,
    String fn, [
    List<dynamic> params = const [],
  ]) {
    final contract = DeployedContract(abi, address);
    return client
        .call(
          contract: contract,
          function: contract.function(fn),
          params: params,
        )
        .timeout(readTimeout);
  }

  // ── IZkPoll reads ─────────────────────────────────────────────────────────

  /// Poll phase: 0 = Registration, 1 = Voting, 2 = Ended (enum PollState).
  Future<int> getState(String pollAddress) async {
    final r = await _read(
      _pollAbi,
      EthereumAddress.fromHex(pollAddress),
      'getState',
    );
    return (r.first as BigInt).toInt();
  }

  Future<List<String>> getOptions(String pollAddress) async {
    final r = await _read(
      _pollAbi,
      EthereumAddress.fromHex(pollAddress),
      'getOptions',
    );
    return (r.first as List).cast<String>();
  }

  /// Per-option vote tally.
  Future<List<BigInt>> getResults(String pollAddress) async {
    final r = await _read(
      _pollAbi,
      EthereumAddress.fromHex(pollAddress),
      'getResults',
    );
    return (r.first as List).cast<BigInt>();
  }

  Future<String> getOwner(String pollAddress) async {
    final r = await _read(
      _pollAbi,
      EthereumAddress.fromHex(pollAddress),
      'owner',
    );
    return (r.first as EthereumAddress).eip55With0x;
  }

  Future<BigInt> getParticipantCount(String pollAddress) async {
    final r = await _read(
      _pollAbi,
      EthereumAddress.fromHex(pollAddress),
      'getParticipantCount',
    );
    return r.first as BigInt;
  }

  /// The poll's R4 results policy (`IZkPoll.resultsPolicy()`): 0 =
  /// sealed-until-close (the default), 1 = live-public (creation-time
  /// opt-in). Metadata compliant clients honor — `getResults()` itself is
  /// deliberately not gated on-chain (PR #108 design decision 2). Reverts on
  /// pre-R4 polls (no such function); callers that must tolerate them catch
  /// and pick their own fallback.
  Future<int> getResultsPolicy(String pollAddress) async {
    final r = await _read(
      _pollAbi,
      EthereumAddress.fromHex(pollAddress),
      'resultsPolicy',
    );
    return (r.first as BigInt).toInt();
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
    final contract = DeployedContract(
      _anonAbi,
      EthereumAddress.fromHex(pollAddress),
    );
    final event = contract.event('VoterRegistered');
    final logs = await client
        .getLogs(
          FilterOptions.events(
            contract: contract,
            event: event,
            fromBlock: const BlockNum.genesis(),
            toBlock: const BlockNum.current(),
          ),
        )
        .timeout(readTimeout);
    return logs
        .map((log) {
          final decoded = event.decodeResults(
            log.topics ?? const [],
            log.data ?? '0x',
          );
          return decoded.isEmpty ? null : (decoded.first as BigInt).toString();
        })
        .whereType<String>()
        .toList();
  }

  // ── ZkBlindVoting (M2) reads ────────────────────────────────────────────────

  /// Timestamp (unix seconds) after which reveals close. 0 until `endVoting`.
  Future<BigInt> getRevealDeadline(String pollAddress) async {
    final r = await _read(
      _blind,
      EthereumAddress.fromHex(pollAddress),
      'getRevealDeadline',
    );
    return r.first as BigInt;
  }

  Future<bool> isFinalized(String pollAddress) async {
    final r = await _read(
      _blind,
      EthereumAddress.fromHex(pollAddress),
      'isFinalized',
    );
    return r.first as bool;
  }

  /// Has [voter] committed a (hidden) vote in this blind poll?
  Future<bool> hasVoted(String pollAddress, String voter) async {
    final r = await _read(
      _blind,
      EthereumAddress.fromHex(pollAddress),
      'hasVoted',
      [EthereumAddress.fromHex(voter)],
    );
    return r.first as bool;
  }

  /// Has [voter] revealed their committed vote?
  Future<bool> hasRevealed(String pollAddress, String voter) async {
    final r = await _read(
      _blind,
      EthereumAddress.fromHex(pollAddress),
      'hasRevealed',
      [EthereumAddress.fromHex(voter)],
    );
    return r.first as bool;
  }

  /// Is [voter] registered to vote in this blind poll?
  Future<bool> isRegistered(String pollAddress, String voter) async {
    final r = await _read(
      _blind,
      EthereumAddress.fromHex(pollAddress),
      'isRegistered',
      [EthereumAddress.fromHex(voter)],
    );
    return r.first as bool;
  }

  // ── ZkSurveyVoting (12d) reads ──────────────────────────────────────────────

  /// Number of questions in a survey (`getQuestionCount`). A survey ballot is
  /// one answer word per question, in question order.
  Future<int> getSurveyQuestionCount(String pollAddress) async {
    final r = await _read(
      _survey,
      EthereumAddress.fromHex(pollAddress),
      'getQuestionCount',
    );
    return (r.first as BigInt).toInt();
  }

  /// Question [q]'s own option labels (`getQuestionOptions(q)`).
  Future<List<String>> getSurveyQuestionOptions(
    String pollAddress,
    int q,
  ) async {
    final r = await _read(
      _survey,
      EthereumAddress.fromHex(pollAddress),
      'getQuestionOptions',
      [BigInt.from(q)],
    );
    return (r.first as List).cast<String>();
  }

  /// Question [q]'s type (`getQuestionType(q)`): 0 = SingleChoice, 1 =
  /// MultiSelect (enum `ZkSurveyVoting.QType`, an on-chain `uint8`).
  Future<int> getSurveyQuestionType(String pollAddress, int q) async {
    final r = await _read(
      _survey,
      EthereumAddress.fromHex(pollAddress),
      'getQuestionType',
      [BigInt.from(q)],
    );
    return (r.first as BigInt).toInt();
  }

  /// The full per-question tally (`getSurveyResults`): a nested `uint256[][]`
  /// where `results[q][option]` is the count for option `option` of question
  /// `q`. The survey detail screen renders one `ResultsBars` per question from
  /// this (a response DISTRIBUTION — no per-question winner).
  Future<List<List<BigInt>>> getSurveyResults(String pollAddress) async {
    final r = await _read(
      _survey,
      EthereumAddress.fromHex(pollAddress),
      'getSurveyResults',
    );
    // Decode the nested uint256[][]: each row is a question's per-option counts.
    return (r.first as List)
        .map((row) => (row as List).cast<BigInt>())
        .toList();
  }

  // ── PollRegistry ──────────────────────────────────────────────────────────

  /// EVERY poll the registry knows, listed or not. Owner/ops surface — R4's
  /// privacy default means public directories must use [getListedPolls]
  /// instead (the registry NatSpec says the same).
  Future<List<PollInfo>> getAllPolls() async {
    final r = await _read(_registryAbi, _registryAddress, 'getAllPolls');
    final rows = r.first as List;
    return rows.map((row) => PollInfo.fromTuple(row as List)).toList();
  }

  /// The public directory: only polls whose creator explicitly opted in to
  /// listing (`visibility = 1`) at creation time (R4 `getListedPolls()`).
  Future<List<PollInfo>> getListedPolls() async {
    final r = await _read(_registryAbi, _registryAddress, 'getListedPolls');
    final rows = r.first as List;
    return rows.map((row) => PollInfo.fromTuple(row as List)).toList();
  }

  /// Link-access resolution (R4 `getPollInfo(address)`): an UNLISTED poll's
  /// info stays fetchable by whoever holds its address — the link IS the
  /// capability. Returns null when the address isn't a registered poll
  /// (the contract reverts `UnknownPoll`).
  Future<PollInfo?> getPollInfo(String pollAddress) async {
    try {
      final r = await _read(_registryAbi, _registryAddress, 'getPollInfo', [
        EthereumAddress.fromHex(pollAddress),
      ]);
      return PollInfo.fromTuple(r.first as List);
    } on RPCError {
      return null; // UnknownPoll revert: not registered here
    }
  }

  void dispose() => client.dispose();
}
