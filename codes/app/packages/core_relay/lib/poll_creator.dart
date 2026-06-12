import 'dart:typed_data';

import 'package:wallet/wallet.dart' show EthereumAddress;
import 'package:web3dart/web3dart.dart';

import 'package:core_chain/config.dart';
import 'package:core_chain/chain_writer.dart';

/// The v1 survey question types, matching the on-chain `enum QType`
/// (`SingleChoice = 0`, `MultiSelect = 1`). The [solidityValue] is the `uint8`
/// the inner `(uint8,string[])[]` ABI encoding carries for this type.
enum SurveyQType {
  singleChoice(0),
  multiSelect(1);

  const SurveyQType(this.solidityValue);

  /// The `uint8` value the contract's `QType` enum assigns to this type.
  final int solidityValue;
}

/// A single survey question for the `survey-vote` create flow: its [qType] and
/// its own ordered option labels. Mirrors the on-chain
/// `struct Question { QType qType; string[] options; }`.
class SurveyQuestion {
  const SurveyQuestion({required this.qType, required this.options});

  final SurveyQType qType;
  final List<String> options;
}

/// web3dart ABI type for the inner survey `initData` preimage:
/// `(uint8 qType, string[] options)[]` — a dynamic array of
/// `(uint8, string[])` tuples. Encoding the [SurveyQuestion]s through this type
/// reproduces Solidity's `abi.encode((uint8,string[])[])`, which is exactly what
/// `ZkSurveyVoting.initialize`'s `abi.decode(initData, (Question[]))` accepts.
final _questionsArrayType = DynamicLengthArray<List<dynamic>>(
  type: TupleType([
    const UintType(length: 8),
    DynamicLengthArray<String>(type: const StringType()),
  ]),
);

/// `abi.encode((uint8,string[])[])` of [questions] — the INNER bytes that
/// become the `bytes initData` arg of `ZkSurveyVoting.initialize`.
///
/// This is a raw `abi.encode` (NO selector), byte-identical to ethers'
/// `AbiCoder.encode(["tuple(uint8,string[])[]"], [value])` and to Solidity's
/// `abi.decode(initData, (Question[]))`. The questions array is wrapped in an
/// outer single-element [TupleType] before encoding so the leading 32-byte
/// offset word (`0x…20`) is emitted — exactly as ethers' param-tuple does and as
/// `abi.decode` requires. Encoding the bare array would instead start with the
/// array LENGTH, and every survey creation would revert `InitFailed`. The
/// cross-impl gate-2 test pins this against the frozen ethers literal.
Uint8List encodeSurveyInitData(List<SurveyQuestion> questions) {
  // Value shape: [ [qTypeInt(BigInt), [opt0, opt1, …]], … ].
  // UintType.encode requires a BigInt, not an int.
  final value = [
    for (final q in questions)
      <dynamic>[BigInt.from(q.qType.solidityValue), q.options],
  ];
  final sink = LengthTrackingByteSink();
  // Wrap in an outer tuple so the top-level dynamic array gets its offset head.
  TupleType([_questionsArrayType]).encode([value], sink);
  return sink.asBytes();
}

/// Creates polls through the local dev-signer ([ChainWriter]) — the wallet-free
/// path for local development. When [canSign] is true (DEV_PRIVATE_KEY set), the
/// Create screen can deploy without connecting a wallet, signing directly to the
/// host Hardhat node a phone wallet can't reach.
///
/// R4 (PR #108): this DIRECT-CHAIN path speaks the native R4 encodings —
/// every module `initialize` carries the trailing `uint8 resultsPolicy`
/// (default 0 = sealed-until-close) and `createPoll` picks the right overload
/// for [visibility]: 0 (default) rides the legacy 4-arg fragment whose
/// unlisted default lives IN the contract; 1 opts in via the explicit 5-arg
/// fragment. Both defaults are the PRIVATE choices. (The sponsored/relayer
/// path is different on purpose — see `sponsored_poll_creator.dart`.)
class PollCreator {
  final ChainWriter writer;
  final String registryAbiJson;
  final String anonAbiJson;
  final String approvalAbiJson;
  final String surveyVotingAbiJson;

  PollCreator({
    required this.writer,
    required this.registryAbiJson,
    required this.anonAbiJson,
    required this.approvalAbiJson,
    required this.surveyVotingAbiJson,
  });

  bool get canSign => writer.canSign;
  String? get signer => writer.signerAddress;

  /// Deploy an anon-vote poll, signed by the dev key. Mirrors the wallet path's
  /// encoding: `ZkAnonVoting.initialize(semaphore, owner, options,
  /// resultsPolicy)` forwarded by `PollRegistry.createPoll('anon-vote', …)`.
  Future<String> createAnonPoll({
    required String title,
    required String description,
    required List<String> options,
    int visibility = 0,
    int resultsPolicy = 0,
  }) {
    final owner = writer.signerAddress!;
    final anon = DeployedContract(
      ContractAbi.fromJson(anonAbiJson, 'ZkAnonVoting'),
      EthereumAddress.fromHex('0x0000000000000000000000000000000000000000'),
    );
    final initData = anon.function('initialize').encodeCall([
      EthereumAddress.fromHex(AppConfig.semaphoreAddress),
      EthereumAddress.fromHex(owner),
      options,
      BigInt.from(resultsPolicy),
    ]);
    return writer.send(
      to: AppConfig.registryAddress,
      abiJson: registryAbiJson,
      abiName: 'PollRegistry',
      function: 'createPoll',
      params: _createPollParams(
        'anon-vote',
        title,
        description,
        visibility,
        initData,
      ),
    );
  }

  /// The `createPoll` positional params for [visibility]: the DEFAULT 0 stays
  /// on the legacy 4-arg overload — "unlisted by default" is the CONTRACT's
  /// job (PR #108 design decision 1), so the private path sends no flag at
  /// all. Only an explicit listing opt-in (1) selects the 5-arg overload.
  /// [ChainWriter] disambiguates the overloaded fragment by this arity.
  static List<dynamic> _createPollParams(
    String moduleType,
    String title,
    String description,
    int visibility,
    Uint8List initData,
  ) => visibility == 0
      ? [moduleType, title, description, initData]
      : [moduleType, title, description, BigInt.from(visibility), initData];

  /// Deploy an APPROVAL-vote poll (module `approval-vote`), signed by the dev
  /// key. `ZkApprovalVoting.initialize(semaphore, owner, options)` has the same
  /// shape as M1's — only the registered module string differs, which is what
  /// makes Browse navigate to `?module=approval-vote` (and the router dispatch
  /// the multi-select bitmask screen). The string is the canonical
  /// `approval-vote` from the design spec.
  Future<String> createApprovalPoll({
    required String title,
    required String description,
    required List<String> options,
    int visibility = 0,
    int resultsPolicy = 0,
  }) => _createModulePoll(
    moduleType: 'approval-vote',
    title: title,
    description: description,
    options: options,
    visibility: visibility,
    resultsPolicy: resultsPolicy,
  );

  /// Deploy a RANKED-choice poll (module `ranked-vote`), signed by the dev key.
  /// `ZkRankedVoting.initialize(semaphore, owner, options)` is byte-identical in
  /// shape to anon/approval — only the registered module string differs, which is
  /// what makes Browse navigate to `?module=ranked-vote` (and the router dispatch
  /// the instant-runoff screen). The string is the canonical `ranked-vote`.
  /// NOTE: the ranked module caps options at 8 on-chain (MAX_OPTIONS); the Create
  /// form enforces 2..8 so `initialize` can't revert with `TooManyOptions`.
  Future<String> createRankedPoll({
    required String title,
    required String description,
    required List<String> options,
    int visibility = 0,
    int resultsPolicy = 0,
  }) => _createModulePoll(
    moduleType: 'ranked-vote',
    title: title,
    description: description,
    options: options,
    visibility: visibility,
    resultsPolicy: resultsPolicy,
  );

  /// Deploy a QUADRATIC poll (module `quadratic-vote`), signed by the dev key.
  /// `ZkQuadraticVoting.initialize(semaphore, owner, options)` is byte-identical
  /// in shape to anon/approval — only the registered module string differs, which
  /// makes Browse navigate to `?module=quadratic-vote` (and the router dispatch
  /// the credit-allocation screen). The string is the canonical `quadratic-vote`.
  /// NOTE: the quadratic module caps options at 8 on-chain (MAX_OPTIONS); the
  /// Create form enforces 2..8 so `initialize` can't revert with `TooManyOptions`.
  Future<String> createQuadraticPoll({
    required String title,
    required String description,
    required List<String> options,
    int visibility = 0,
    int resultsPolicy = 0,
  }) => _createModulePoll(
    moduleType: 'quadratic-vote',
    title: title,
    description: description,
    options: options,
    visibility: visibility,
    resultsPolicy: resultsPolicy,
  );

  /// Deploy a SURVEY poll (module `survey-vote`), signed by the dev key.
  ///
  /// UNLIKE every other module, `ZkSurveyVoting.initialize` takes
  /// `(address semaphore, address owner, bytes initData)` — NOT a flat
  /// `string[] options`. The init blob is therefore DOUBLE-wrapped:
  ///
  /// 1. INNER bytes = `abi.encode((uint8,string[])[])` of the [questions]
  ///    ([encodeSurveyInitData]) — the raw question structure the contract
  ///    decodes via `abi.decode(initData, (Question[]))`.
  /// 2. OUTER initData = `initialize(semaphore, owner, innerBytes)` encoded with
  ///    the SURVEY ABI — wrapping the inner bytes as the `bytes initData` arg.
  ///
  /// then deployed via `PollRegistry.createPoll('survey-vote', …)`. The module
  /// string is the canonical `survey-vote` (Browse `?module=` / relayer /
  /// deploy.ts). If the inner encoding doesn't match Solidity's decode, every
  /// survey creation reverts `InitFailed`; the gate-2 cross-check pins it.
  Future<String> createSurveyPoll({
    required String title,
    required String description,
    required List<SurveyQuestion> questions,
    int visibility = 0,
    int resultsPolicy = 0,
  }) {
    final owner = writer.signerAddress!;
    final innerBytes = encodeSurveyInitData(questions);
    final survey = DeployedContract(
      ContractAbi.fromJson(surveyVotingAbiJson, 'ZkSurveyVoting'),
      EthereumAddress.fromHex('0x0000000000000000000000000000000000000000'),
    );
    final initData = survey.function('initialize').encodeCall([
      EthereumAddress.fromHex(AppConfig.semaphoreAddress),
      EthereumAddress.fromHex(owner),
      innerBytes,
      BigInt.from(resultsPolicy),
    ]);
    return writer.send(
      to: AppConfig.registryAddress,
      abiJson: registryAbiJson,
      abiName: 'PollRegistry',
      function: 'createPoll',
      params: _createPollParams(
        'survey-vote',
        title,
        description,
        visibility,
        initData,
      ),
    );
  }

  /// Shared encoder for the anon/approval/ranked/quadratic modules. They all take
  /// the same `initialize(semaphore, owner, options, resultsPolicy)` shape, so
  /// the only thing that varies between them is the canonical [moduleType]
  /// string forwarded to `PollRegistry.createPoll`. The init blob is
  /// ABI-identical across modules (`(address,address,string[],uint8)`), so
  /// reusing the approval ABI for the encode produces the same calldata the
  /// per-module ABI would — and keeps the dependency surface to the one ABI
  /// already wired into [PollCreator].
  Future<String> _createModulePoll({
    required String moduleType,
    required String title,
    required String description,
    required List<String> options,
    int visibility = 0,
    int resultsPolicy = 0,
  }) {
    final owner = writer.signerAddress!;
    final module = DeployedContract(
      ContractAbi.fromJson(approvalAbiJson, 'ZkApprovalVoting'),
      EthereumAddress.fromHex('0x0000000000000000000000000000000000000000'),
    );
    final initData = module.function('initialize').encodeCall([
      EthereumAddress.fromHex(AppConfig.semaphoreAddress),
      EthereumAddress.fromHex(owner),
      options,
      BigInt.from(resultsPolicy),
    ]);
    return writer.send(
      to: AppConfig.registryAddress,
      abiJson: registryAbiJson,
      abiName: 'PollRegistry',
      function: 'createPoll',
      params: _createPollParams(
        moduleType,
        title,
        description,
        visibility,
        initData,
      ),
    );
  }
}
