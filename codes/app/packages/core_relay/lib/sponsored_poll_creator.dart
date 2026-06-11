import 'dart:typed_data';

import 'package:wallet/wallet.dart' show EthereumAddress;
import 'package:web3dart/web3dart.dart';

import 'package:core_chain/config.dart';
import 'poll_creator.dart' show SurveyQuestion, encodeSurveyInitData;
import 'relay_client.dart';

/// Wallet-free, sponsored poll creation via the relayer — the "you don't need a
/// wallet" path. The relayer pays gas and OWNS the poll, so the module
/// `initData` is built with the relayer's address (from
/// [RelayClient.getRelayerInfo]) as `owner`. Mirrors [PollCreator]'s per-module
/// encoding; the only difference is the owner. Blind-vote is excluded (the
/// relayer's sponsored allow-list rejects it).
///
/// The flat modules (anon / approval / ranked / quadratic) share the
/// `initialize(address semaphore, address owner, string[] options)` shape, so a
/// single ABI encodes byte-identical calldata for all of them (only the module
/// string forwarded to `createPoll` differs). Survey is double-wrapped.
class SponsoredPollCreator {
  final RelayClient relay;

  /// Any flat `(address,address,string[])` module ABI — its `initialize` selector
  /// + encoding are identical across anon/approval/ranked/quadratic.
  final String flatModuleAbiJson;
  final String surveyVotingAbiJson;

  SponsoredPollCreator({
    required this.relay,
    required this.flatModuleAbiJson,
    required this.surveyVotingAbiJson,
  });

  static const _zero = '0x0000000000000000000000000000000000000000';

  static String hexOf(Uint8List b) =>
      '0x${b.map((x) => x.toRadixString(16).padLeft(2, '0')).join()}';

  /// Whether sponsored creation is reachable right now (the relayer answers
  /// `/info` with an owner + registry). Null when unreachable / unconfigured.
  Future<RelayerInfo?> probe() => relay.getRelayerInfo();

  /// Create a flat-options module poll (`anon-vote` / `approval-vote` /
  /// `ranked-vote` / `quadratic-vote`).
  Future<CreatePollResult> createFlatPoll({
    required String moduleType,
    required String title,
    required String description,
    required List<String> options,
  }) async {
    final info = await relay.getRelayerInfo();
    if (info == null) {
      return const CreatePollResult(
          error: 'The sponsoring relayer is unreachable.');
    }
    final initData = encodeFlatInitData(
      flatModuleAbiJson: flatModuleAbiJson,
      semaphore: AppConfig.semaphoreAddress,
      owner: info.relayer,
      options: options,
    );
    return relay.createPoll(
      moduleType: moduleType,
      title: title,
      description: description,
      initDataHex: hexOf(initData),
    );
  }

  /// Create a SURVEY poll (`survey-vote`) — double-wrapped, relayer-owned.
  Future<CreatePollResult> createSurveyPoll({
    required String title,
    required String description,
    required List<SurveyQuestion> questions,
  }) async {
    final info = await relay.getRelayerInfo();
    if (info == null) {
      return const CreatePollResult(
          error: 'The sponsoring relayer is unreachable.');
    }
    final initData = encodeSurveyOuterInitData(
      surveyVotingAbiJson: surveyVotingAbiJson,
      semaphore: AppConfig.semaphoreAddress,
      owner: info.relayer,
      questions: questions,
    );
    return relay.createPoll(
      moduleType: 'survey-vote',
      title: title,
      description: description,
      initDataHex: hexOf(initData),
    );
  }
}

/// `initialize(semaphore, owner, options)` calldata for a flat module. Pure +
/// owner-parametric so both the dev-signer and the sponsored path agree
/// byte-for-byte (pinned by a test).
Uint8List encodeFlatInitData({
  required String flatModuleAbiJson,
  required String semaphore,
  required String owner,
  required List<String> options,
}) {
  final module = DeployedContract(
    ContractAbi.fromJson(flatModuleAbiJson, 'ZkApprovalVoting'),
    EthereumAddress.fromHex(SponsoredPollCreator._zero),
  );
  return module.function('initialize').encodeCall([
    EthereumAddress.fromHex(semaphore),
    EthereumAddress.fromHex(owner),
    options,
  ]);
}

/// `initialize(semaphore, owner, bytes innerQuestions)` calldata for the survey
/// module — the OUTER wrap around [encodeSurveyInitData].
Uint8List encodeSurveyOuterInitData({
  required String surveyVotingAbiJson,
  required String semaphore,
  required String owner,
  required List<SurveyQuestion> questions,
}) {
  final inner = encodeSurveyInitData(questions);
  final survey = DeployedContract(
    ContractAbi.fromJson(surveyVotingAbiJson, 'ZkSurveyVoting'),
    EthereumAddress.fromHex(SponsoredPollCreator._zero),
  );
  return survey.function('initialize').encodeCall([
    EthereumAddress.fromHex(semaphore),
    EthereumAddress.fromHex(owner),
    inner,
  ]);
}
