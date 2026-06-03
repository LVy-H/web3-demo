import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tessera/data/services/chain_writer.dart';
import 'package:tessera/data/services/poll_creator.dart';

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
    final registryAbi = _abiArray('assets/abi/PollRegistry.json');
    final anonAbi = _abiArray('assets/abi/ZkAnonVoting.json');
    final approvalAbi = _abiArray('assets/abi/ZkApprovalVoting.json');
    creator = PollCreator(
      writer: writer,
      registryAbiJson: registryAbi,
      anonAbiJson: anonAbi,
      approvalAbiJson: approvalAbi,
    );
  });

  tearDown(() => writer.dispose());

  // Each create* method must forward its CANONICAL module string as the first
  // positional param of PollRegistry.createPoll(moduleType, title, desc, init).
  // These strings are what Browse `?module=` / the relayer / deploy.ts use.
  void expectModule(String module, String title) {
    expect(writer.lastFunction, 'createPoll');
    expect(writer.lastParams, isNotNull);
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
}
