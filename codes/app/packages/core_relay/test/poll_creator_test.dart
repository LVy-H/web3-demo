import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:core_chain/config.dart';
import 'package:core_chain/chain_writer.dart';
import 'package:core_relay/poll_creator.dart';
import 'package:wallet/wallet.dart' show EthereumAddress;
import 'package:web3dart/web3dart.dart';

/// Records the params passed to [ChainWriter.send] without touching a chain, so
/// we can assert exactly which module string each `create*Poll` forwards to
/// `PollRegistry.createPoll`. `signerAddress` returns a fixed dev address so the
/// init blob encodes (the create methods read `writer.signerAddress!`).
class _RecordingWriter extends ChainWriter {
  List<dynamic>? lastParams;
  String? lastFunction;
  String? lastTo;

  _RecordingWriter()
      : super(rpcUrl: 'http://localhost:0', chainId: 31337, privateKey: '');

  @override
  bool get canSign => true;

  @override
  String? get signerAddress =>
      '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266'; // Hardhat acct #0

  @override
  Future<String> send({
    required String to,
    required String abiJson,
    required String abiName,
    required String function,
    List<dynamic> params = const [],
  }) async {
    lastTo = to;
    lastFunction = function;
    lastParams = params;
    return '0xdeadbeef';
  }
}

String _abiArray(String path) =>
    jsonEncode(jsonDecode(File(path).readAsStringSync())['abi']);

void main() {
  late _RecordingWriter writer;
  late PollCreator creator;

  setUp(() {
    writer = _RecordingWriter();
    final registryAbi = _abiArray('../core_chain/assets/abi/PollRegistry.json');
    final anonAbi = _abiArray('../core_chain/assets/abi/ZkAnonVoting.json');
    final approvalAbi = _abiArray('../core_chain/assets/abi/ZkApprovalVoting.json');
    final surveyAbi = _abiArray('../core_chain/assets/abi/ZkSurveyVoting.json');
    creator = PollCreator(
      writer: writer,
      registryAbiJson: registryAbi,
      anonAbiJson: anonAbi,
      approvalAbiJson: approvalAbi,
      surveyVotingAbiJson: surveyAbi,
    );
  });

  tearDown(() => writer.dispose());

  // Each create* method must forward its CANONICAL module string as the first
  // positional param of PollRegistry.createPoll(moduleType, title, desc, init).
  // These strings are what Browse `?module=` / the relayer / deploy.ts use.
  // R4: the DEFAULT path stays on the legacy 4-arg overload (no visibility
  // arg — unlisted is the contract's default), so params has exactly 4 slots.
  void expectModule(String module, String title) {
    expect(writer.lastFunction, 'createPoll');
    expect(writer.lastParams, isNotNull);
    expect(writer.lastParams, hasLength(4),
        reason: 'default visibility rides the legacy 4-arg overload');
    expect(writer.lastParams![0], module, reason: 'module string');
    expect(writer.lastParams![1], title, reason: 'title');
    // init blob is non-empty calldata (initialize(...) encoded).
    expect(writer.lastParams![3], isA<List<int>>());
    expect((writer.lastParams![3] as List).isNotEmpty, isTrue);
  }

  test('createAnonPoll forwards module "anon-vote"', () async {
    await creator.createAnonPoll(
        title: 'A', description: 'd', options: const ['Yes', 'No']);
    expectModule('anon-vote', 'A');
  });

  test('createApprovalPoll forwards module "approval-vote"', () async {
    await creator.createApprovalPoll(
        title: 'B', description: 'd', options: const ['Yes', 'No', 'Maybe']);
    expectModule('approval-vote', 'B');
  });

  test('createRankedPoll forwards module "ranked-vote"', () async {
    await creator.createRankedPoll(
        title: 'C', description: 'd', options: const ['Yes', 'No', 'Maybe']);
    expectModule('ranked-vote', 'C');
  });

  test('createQuadraticPoll forwards module "quadratic-vote"', () async {
    await creator.createQuadraticPoll(
        title: 'D', description: 'd', options: const ['Yes', 'No', 'Maybe']);
    expectModule('quadratic-vote', 'D');
  });

  test('createSurveyPoll forwards module "survey-vote" + wraps the inner '
      'abi.encode((uint8,string[])[]) as initialize(address,address,bytes,'
      'uint8)', () async {
    const questions = [
      SurveyQuestion(qType: SurveyQType.singleChoice, options: ['A', 'B', 'C']),
      SurveyQuestion(
          qType: SurveyQType.multiSelect, options: ['X', 'Y', 'Z', 'W']),
    ];
    await creator.createSurveyPoll(
        title: 'S', description: 'd', questions: questions);
    expectModule('survey-vote', 'S');

    // The OUTER initData must be `initialize(semaphore, owner, innerBytes)`
    // (the 4-byte selector + 2 address words + a `bytes` arg whose payload is
    // the inner abi.encode((uint8,string[])[])). Re-encode the EXPECTED
    // `initialize` call — semaphore + owner (Hardhat acct #0, the recording
    // writer's signer) + the standalone inner encoder's bytes — and assert the
    // forwarded init blob equals it byte-for-byte. That proves both the selector
    // and that the bytes arg IS the inner encoding.
    final initBlob =
        Uint8List.fromList(List<int>.from(writer.lastParams![3] as List));
    final survey = DeployedContract(
      ContractAbi.fromJson(
          _abiArray('../core_chain/assets/abi/ZkSurveyVoting.json'), 'ZkSurveyVoting'),
      EthereumAddress.fromHex('0x0000000000000000000000000000000000000000'),
    );
    final fn = survey.function('initialize');
    final expectedBlob = fn.encodeCall([
      EthereumAddress.fromHex(AppConfig.semaphoreAddress),
      EthereumAddress.fromHex(writer.signerAddress!),
      encodeSurveyInitData(questions),
      BigInt.zero, // R4 trailing resultsPolicy, sealed default
    ]);
    expect(initBlob, expectedBlob,
        reason: 'outer initData = initialize(semaphore, owner, innerBytes)');
    // The 4-byte initialize selector leads the blob (sanity on the wrap).
    expect(initBlob.sublist(0, 4), fn.selector);
  });

  test('ranked & quadratic encode the SAME calldata as approval for equal '
      'options (identical initialize ABI, only the module string differs)',
      () async {
    const opts = ['Pizza', 'Sushi', 'Tacos'];
    await creator.createApprovalPoll(
        title: 'T', description: 'd', options: opts);
    final approvalInit = List<int>.from(writer.lastParams![3] as List);

    await creator.createRankedPoll(title: 'T', description: 'd', options: opts);
    final rankedInit = List<int>.from(writer.lastParams![3] as List);

    await creator.createQuadraticPoll(
        title: 'T', description: 'd', options: opts);
    final quadraticInit = List<int>.from(writer.lastParams![3] as List);

    expect(rankedInit, approvalInit);
    expect(quadraticInit, approvalInit);
  });

  // ── R4 privacy opt-ins ────────────────────────────────────────────────────

  test('visibility=1 switches to the explicit 5-arg createPoll overload '
      '(uint8 visibility before initData)', () async {
    await creator.createAnonPoll(
        title: 'V',
        description: 'd',
        options: const ['Yes', 'No'],
        visibility: 1);
    expect(writer.lastParams, hasLength(5));
    expect(writer.lastParams![0], 'anon-vote');
    expect(writer.lastParams![3], BigInt.one, reason: 'uint8 visibility word');
    expect(writer.lastParams![4], isA<List<int>>(), reason: 'initData last');
  });

  test('resultsPolicy is appended as the trailing uint8 of initialize '
      '(R4 selector + arg, default 0)', () async {
    final anonAbi = _abiArray('../core_chain/assets/abi/ZkAnonVoting.json');
    final anon = DeployedContract(
      ContractAbi.fromJson(anonAbi, 'ZkAnonVoting'),
      EthereumAddress.fromHex('0x0000000000000000000000000000000000000000'),
    );
    Uint8List expectedInit(int policy) =>
        anon.function('initialize').encodeCall([
          EthereumAddress.fromHex(AppConfig.semaphoreAddress),
          EthereumAddress.fromHex(writer.signerAddress!),
          ['Yes', 'No'],
          BigInt.from(policy),
        ]);

    await creator.createAnonPoll(
        title: 'P', description: 'd', options: const ['Yes', 'No']);
    expect(List<int>.from(writer.lastParams![3] as List), expectedInit(0),
        reason: 'omitted resultsPolicy encodes the sealed default 0');

    await creator.createAnonPoll(
        title: 'P',
        description: 'd',
        options: const ['Yes', 'No'],
        resultsPolicy: 1);
    expect(List<int>.from(writer.lastParams![3] as List), expectedInit(1),
        reason: 'resultsPolicy=1 rides the trailing initialize arg');
  });
}
