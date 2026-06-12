import 'dart:typed_data';

import 'package:wallet/wallet.dart' show EthereumAddress;
import 'package:web3dart/web3dart.dart';

import 'package:core_chain/config.dart';
import 'poll_creator.dart' show SurveyQuestion, encodeSurveyInitData;
import 'relay_client.dart';

/// Wallet-free, sponsored poll creation via the relayer — the "you don't need a
/// wallet" path. The relayer pays gas and OWNS the poll, so the module
/// `initData` is built with the relayer's address (from
/// [RelayClient.getRelayerInfo]) as `owner`. Blind-vote is excluded (the
/// relayer's sponsored allow-list rejects it).
///
/// ## R4 wire decision (documented per the R4 client migration)
///
/// UNLIKE the dev-signer path ([PollCreator]'s native R4 encodings), this path
/// keeps sending the PRE-R4 `initialize` encoding and carries the privacy
/// choices as the relayer request's top-level `resultsPolicy` / `visibility`
/// JSON fields instead. That is NOT legacy debt — it is the relayer's create
/// API contract (PR #108 decision 3):
///
///  * `appendResultsPolicyToInitData` (codes/relayer/src/relay.ts) decodes the
///    client's initData against the pre-R4 arg shapes UNCONDITIONALLY and
///    re-encodes it with the request's `resultsPolicy` appended. Sending
///    native R4 initData would get a SECOND policy byte appended — wrong
///    selector, `InitFailed`, every sponsored create dead.
///  * `validateCreatePollRequest` likewise reads the embedded `owner` word
///    assuming the pre-R4 head layout.
///
/// So the pre-R4 fragments below are pinned as the FROZEN WIRE FORMAT of the
/// sponsored create call ([_preR4FlatInitializeAbi] /
/// [_preR4SurveyInitializeAbi]) — they intentionally do NOT track core_chain's
/// refreshed R4 ABIs. Moving this path to native R4 initData requires a
/// relayer wire-version change first.
class SponsoredPollCreator {
  final RelayClient relay;

  /// Retained for wiring compatibility (the frozen R3 feature packages inject
  /// core_chain's bundled module ABIs here). NOT consulted for the wire
  /// encoding anymore: those assets are R4 now, while this path's wire format
  /// is the pinned pre-R4 fragment — see the class doc.
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
  /// `ranked-vote` / `quadratic-vote`). [visibility] / [resultsPolicy] are the
  /// R4 policy opt-ins (0|1, both default 0 = the private choices); they ride
  /// the relayer request's JSON fields, never the initData (class doc).
  Future<CreatePollResult> createFlatPoll({
    required String moduleType,
    required String title,
    required String description,
    required List<String> options,
    int visibility = 0,
    int resultsPolicy = 0,
  }) async {
    final info = await relay.getRelayerInfo();
    if (info == null) {
      return const CreatePollResult(
        error: 'The sponsoring relayer is unreachable.',
      );
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
      visibility: visibility,
      resultsPolicy: resultsPolicy,
    );
  }

  /// Create a SURVEY poll (`survey-vote`) — double-wrapped, relayer-owned.
  /// Policy flags as in [createFlatPoll].
  Future<CreatePollResult> createSurveyPoll({
    required String title,
    required String description,
    required List<SurveyQuestion> questions,
    int visibility = 0,
    int resultsPolicy = 0,
  }) async {
    final info = await relay.getRelayerInfo();
    if (info == null) {
      return const CreatePollResult(
        error: 'The sponsoring relayer is unreachable.',
      );
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
      visibility: visibility,
      resultsPolicy: resultsPolicy,
    );
  }
}

/// The PRE-R4 flat-module `initialize` fragment — the sponsored create wire
/// format (selector `0x1c7fac40` = `initialize(address,address,string[])`).
/// Frozen on purpose; see [SponsoredPollCreator]'s class doc.
const String _preR4FlatInitializeAbi =
    '[{"inputs":[{"internalType":"address","name":"_semaphore","type":"address"},'
    '{"internalType":"address","name":"_owner","type":"address"},'
    '{"internalType":"string[]","name":"_options","type":"string[]"}],'
    '"name":"initialize","outputs":[],"stateMutability":"nonpayable",'
    '"type":"function"}]';

/// The PRE-R4 survey `initialize` fragment — the sponsored create wire format
/// (selector `0xcf7a1d77` = `initialize(address,address,bytes)`). Frozen on
/// purpose; see [SponsoredPollCreator]'s class doc.
const String _preR4SurveyInitializeAbi =
    '[{"inputs":[{"internalType":"address","name":"_semaphore","type":"address"},'
    '{"internalType":"address","name":"_owner","type":"address"},'
    '{"internalType":"bytes","name":"initData","type":"bytes"}],'
    '"name":"initialize","outputs":[],"stateMutability":"nonpayable",'
    '"type":"function"}]';

/// PRE-R4 `initialize(semaphore, owner, options)` calldata for a flat module —
/// the relayer-create wire format (the relayer appends `resultsPolicy`
/// server-side). Pure + owner-parametric so every sponsored caller agrees
/// byte-for-byte (pinned by a test). [flatModuleAbiJson] is accepted for call
/// compatibility with the frozen R3 callers but no longer drives the encoding
/// (it now carries the R4 fragment, which is NOT what this wire speaks).
Uint8List encodeFlatInitData({
  required String flatModuleAbiJson,
  required String semaphore,
  required String owner,
  required List<String> options,
}) {
  final module = DeployedContract(
    ContractAbi.fromJson(_preR4FlatInitializeAbi, 'ZkFlatModulePreR4'),
    EthereumAddress.fromHex(SponsoredPollCreator._zero),
  );
  return module.function('initialize').encodeCall([
    EthereumAddress.fromHex(semaphore),
    EthereumAddress.fromHex(owner),
    options,
  ]);
}

/// PRE-R4 `initialize(semaphore, owner, bytes innerQuestions)` calldata for the
/// survey module — the OUTER wrap around [encodeSurveyInitData], in the
/// relayer-create wire format (see [encodeFlatInitData] for why the
/// [surveyVotingAbiJson] parameter no longer drives the encoding).
Uint8List encodeSurveyOuterInitData({
  required String surveyVotingAbiJson,
  required String semaphore,
  required String owner,
  required List<SurveyQuestion> questions,
}) {
  final inner = encodeSurveyInitData(questions);
  final survey = DeployedContract(
    ContractAbi.fromJson(_preR4SurveyInitializeAbi, 'ZkSurveyVotingPreR4'),
    EthereumAddress.fromHex(SponsoredPollCreator._zero),
  );
  return survey.function('initialize').encodeCall([
    EthereumAddress.fromHex(semaphore),
    EthereumAddress.fromHex(owner),
    inner,
  ]);
}
