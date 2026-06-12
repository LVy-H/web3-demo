import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'package:core_chain/chain_reader.dart';
import 'package:core_chain/chain_writer.dart';
import 'package:wallet/wallet.dart' show EthereumAddress;
import 'package:web3dart/web3dart.dart';

/// Integration test: proves the local dev-signer can SIGN + BROADCAST a real
/// transaction to the host Hardhat node — the foundation of M2 voting actually
/// landing on desktop. R4: creates a blind-vote poll through the OVERLOADED
/// `PollRegistry.createPoll` with the module's R4 `initialize` (trailing
/// `uint8 resultsPolicy`), reads it back from `getAllPolls`, and checks the
/// R4 privacy defaults round-trip (unlisted + sealed-until-close). Also
/// exercises the explicit 5-arg visibility opt-in end-to-end.
///
/// Requires the local stack (./dev-stack.sh up) with R4 contracts. Skips when
/// unreachable.
void main() {
  // Hardhat account #1 (well-known dev key; NEVER a real key). Distinct from the
  // relayer's account #0 to avoid nonce contention.
  const devKey =
      '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d';

  final fixtureFile = File('test/fixtures/local_chain.json');
  if (!fixtureFile.existsSync()) {
    test('chain writer (no fixture)', () {
      markTestSkipped('run dev-stack.sh up to generate local_chain.json');
    }, skip: true);
    return;
  }
  final fixture =
      jsonDecode(fixtureFile.readAsStringSync()) as Map<String, dynamic>;
  final rpc = fixture['rpcUrl'] as String;
  final registry = fixture['registry'] as String;
  final semaphore = fixture['semaphore'] as String;

  String abiArray(String path) =>
      jsonEncode(jsonDecode(File(path).readAsStringSync())['abi']);
  final registryAbi = abiArray('assets/abi/PollRegistry.json');
  final blindAbi = abiArray('assets/abi/ZkBlindVoting.json');
  final anonAbi = abiArray('assets/abi/ZkAnonVoting.json');

  Future<bool> nodeUp() async {
    try {
      final res = await http
          .post(
            Uri.parse(rpc),
            headers: {'content-type': 'application/json'},
            body: '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}',
          )
          .timeout(const Duration(seconds: 3));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  ChainReader buildReader() => ChainReader(
    rpcUrl: rpc,
    izkPollAbiJson: abiArray('assets/abi/IZkPoll.json'),
    registryAbiJson: registryAbi,
    anonVotingAbiJson: anonAbi,
    registryAddress: registry,
  );

  test('dev-signer creates a blind-vote poll that lands on-chain', () async {
    if (!await nodeUp()) {
      markTestSkipped('local node not reachable at $rpc');
      return;
    }
    final writer = ChainWriter(rpcUrl: rpc, chainId: 31337, privateKey: devKey);
    addTearDown(writer.dispose);
    expect(writer.canSign, isTrue);

    // Encode ZkBlindVoting.initialize(owner, options, revealDuration,
    // resultsPolicy) as the module init calldata — R4 appended the trailing
    // uint8 (0 = sealed-until-close, the default).
    final blind = DeployedContract(
      ContractAbi.fromJson(blindAbi, 'ZkBlindVoting'),
      EthereumAddress.fromHex('0x0000000000000000000000000000000000000000'),
    );
    final initData = blind.function('initialize').encodeCall([
      EthereumAddress.fromHex(writer.signerAddress!),
      ['Yes', 'No', 'Abstain'],
      BigInt.from(3600),
      BigInt.zero,
    ]);

    // PRIVATE default path: the legacy 4-arg createPoll overload (no
    // visibility arg — unlisted is the CONTRACT's default). ChainWriter must
    // disambiguate the overloaded name by arity.
    final title = 'Blind Demo Poll ${DateTime.now().millisecondsSinceEpoch}';
    final hash = await writer.send(
      to: registry,
      abiJson: registryAbi,
      abiName: 'PollRegistry',
      function: 'createPoll',
      params: ['blind-vote', title, 'commit-reveal test', initData],
    );
    expect(hash, startsWith('0x'));

    // Read it back: the poll exists in the registry with the R4 privacy
    // defaults — unlisted (visibility 0) and absent from the public
    // directory.
    final reader = buildReader();
    addTearDown(reader.dispose);
    final polls = await reader.getAllPolls();
    final created = polls.where((p) => p.title == title).toList();
    expect(
      created,
      hasLength(1),
      reason: 'the blind poll we just created is in getAllPolls',
    );
    expect(created.single.moduleType, 'blind-vote');
    expect(
      created.single.visibility,
      0,
      reason: '4-arg createPoll defaults to unlisted IN the contract',
    );
    final listed = await reader.getListedPolls();
    expect(
      listed.where((p) => p.title == title),
      isEmpty,
      reason: 'unlisted polls must not appear in the public directory',
    );

    // Sealed-until-close round-trips through the IZkPoll surface.
    expect(
      await reader.getResultsPolicy(created.single.pollAddress),
      0,
      reason: 'trailing resultsPolicy=0 was accepted by R4 initialize',
    );

    // Link-access model: the unlisted poll's info stays fetchable by address.
    final info = await reader.getPollInfo(created.single.pollAddress);
    expect(info?.title, title);
    expect(info?.visibility, 0);
  });

  test('explicit 5-arg createPoll(visibility=1) lists the poll', () async {
    if (!await nodeUp()) {
      markTestSkipped('local node not reachable at $rpc');
      return;
    }
    final writer = ChainWriter(rpcUrl: rpc, chainId: 31337, privateKey: devKey);
    addTearDown(writer.dispose);

    final anon = DeployedContract(
      ContractAbi.fromJson(anonAbi, 'ZkAnonVoting'),
      EthereumAddress.fromHex('0x0000000000000000000000000000000000000000'),
    );
    final initData = anon.function('initialize').encodeCall([
      EthereumAddress.fromHex(semaphore),
      EthereumAddress.fromHex(writer.signerAddress!),
      ['Yes', 'No'],
      BigInt.one, // live-public results: the explicit opt-in
    ]);

    final title = 'Listed Anon Poll ${DateTime.now().millisecondsSinceEpoch}';
    await writer.send(
      to: registry,
      abiJson: registryAbi,
      abiName: 'PollRegistry',
      function: 'createPoll',
      params: [
        'anon-vote',
        title,
        'visibility opt-in test',
        BigInt.one,
        initData,
      ],
    );

    final reader = buildReader();
    addTearDown(reader.dispose);
    final listed = await reader.getListedPolls();
    final mine = listed.where((p) => p.title == title).toList();
    expect(
      mine,
      hasLength(1),
      reason: 'the 5-arg overload with visibility=1 reaches the directory',
    );
    expect(mine.single.visibility, 1);
    expect(mine.single.isListed, isTrue);
    expect(
      await reader.getResultsPolicy(mine.single.pollAddress),
      1,
      reason: 'trailing resultsPolicy=1 round-trips',
    );
  });
}
