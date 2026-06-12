import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:core_chain/chain_writer.dart';
import 'package:core_domain/models/poll_info.dart';
import 'package:wallet/wallet.dart' show EthereumAddress;
import 'package:web3dart/web3dart.dart';

/// R4 ABI surface, pinned against ethers (PR #108's contract changes).
///
/// Every golden hex below is the OUTPUT of ethers v6, computed once in
/// `codes/relayer` (where ethers is installed) and frozen:
///
///   node -e 'const {ethers}=require("ethers"); …encodeFunctionData(…)'
///
/// Because ethers' encoder IS the reference Solidity ABI encoding, asserting
/// web3dart's bytes equal these literals pins Dart-encode ≡ ethers ≡ what the
/// R4 contracts decode. Covers the THREE breaking changes the client must
/// absorb:
///   1. `createPoll` is OVERLOADED (web3dart's `function()` throws) — the
///      4-arg legacy fragment defaults to unlisted, the 5-arg one takes an
///      explicit `uint8 visibility`;
///   2. every module `initialize` gained a trailing `uint8 resultsPolicy`
///      (selector changed);
///   3. `PollCreated` gained a trailing `uint8 visibility` (topic0 changed)
///      and `PollInfo` a trailing `visibility` field.
void main() {
  String abiArray(String path) =>
      jsonEncode(jsonDecode(File(path).readAsStringSync())['abi']);
  String hexOf(List<int> b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

  const zero = '0x0000000000000000000000000000000000000000';
  const semaphore = '0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0';
  const owner = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266';

  late DeployedContract registry;
  late DeployedContract anon;
  setUpAll(() {
    registry = DeployedContract(
      ContractAbi.fromJson(
        abiArray('assets/abi/PollRegistry.json'),
        'PollRegistry',
      ),
      EthereumAddress.fromHex(zero),
    );
    anon = DeployedContract(
      ContractAbi.fromJson(
        abiArray('assets/abi/ZkAnonVoting.json'),
        'ZkAnonVoting',
      ),
      EthereumAddress.fromHex(zero),
    );
  });

  group('createPoll overload selection (refreshed R4 PollRegistry ABI)', () {
    test(
      'the ABI carries BOTH fragments and plain function() cannot pick one',
      () {
        final overloads = registry.abi.functions
            .where((f) => f.name == 'createPoll')
            .toList();
        expect(overloads.map((f) => f.parameters.length).toSet(), {4, 5});
        // The reason resolveOverloadedFunction exists: web3dart throws on any
        // overloaded name.
        expect(() => registry.function('createPoll'), throwsA(isA<Error>()));
      },
    );

    test('4-arg legacy fragment (PRIVATE default path) encodes the frozen '
        'ethers calldata, selector 99d50024', () {
      final fn = ChainWriter.resolveOverloadedFunction(
        registry,
        'createPoll',
        4,
      );
      final encoded = fn.encodeCall([
        'anon-vote',
        'T',
        'D',
        Uint8List.fromList([0x11, 0x22]),
      ]);
      // node -e 'const {ethers}=require("ethers");
      //   const i=new ethers.Interface(
      //     ["function createPoll(string,string,string,bytes)"]);
      //   console.log(i.encodeFunctionData(
      //     "createPoll",["anon-vote","T","D","0x1122"]))'
      const expected =
          '99d50024'
          '0000000000000000000000000000000000000000000000000000000000000080'
          '00000000000000000000000000000000000000000000000000000000000000c0'
          '0000000000000000000000000000000000000000000000000000000000000100'
          '0000000000000000000000000000000000000000000000000000000000000140'
          '0000000000000000000000000000000000000000000000000000000000000009'
          '616e6f6e2d766f74650000000000000000000000000000000000000000000000'
          '0000000000000000000000000000000000000000000000000000000000000001'
          '5400000000000000000000000000000000000000000000000000000000000000'
          '0000000000000000000000000000000000000000000000000000000000000001'
          '4400000000000000000000000000000000000000000000000000000000000000'
          '0000000000000000000000000000000000000000000000000000000000000002'
          '1122000000000000000000000000000000000000000000000000000000000000';
      expect(hexOf(encoded), expected);
    });

    test('5-arg fragment (explicit visibility opt-in) encodes the frozen '
        'ethers calldata, selector 60349aca', () {
      final fn = ChainWriter.resolveOverloadedFunction(
        registry,
        'createPoll',
        5,
      );
      final encoded = fn.encodeCall([
        'anon-vote',
        'T',
        'D',
        BigInt.one,
        Uint8List.fromList([0x11, 0x22]),
      ]);
      // node -e '… new ethers.Interface(
      //   ["function createPoll(string,string,string,uint8,bytes)"])
      //   .encodeFunctionData("createPoll",["anon-vote","T","D",1,"0x1122"])'
      const expected =
          '60349aca'
          '00000000000000000000000000000000000000000000000000000000000000a0'
          '00000000000000000000000000000000000000000000000000000000000000e0'
          '0000000000000000000000000000000000000000000000000000000000000120'
          '0000000000000000000000000000000000000000000000000000000000000001'
          '0000000000000000000000000000000000000000000000000000000000000160'
          '0000000000000000000000000000000000000000000000000000000000000009'
          '616e6f6e2d766f74650000000000000000000000000000000000000000000000'
          '0000000000000000000000000000000000000000000000000000000000000001'
          '5400000000000000000000000000000000000000000000000000000000000000'
          '0000000000000000000000000000000000000000000000000000000000000001'
          '4400000000000000000000000000000000000000000000000000000000000000'
          '0000000000000000000000000000000000000000000000000000000000000002'
          '1122000000000000000000000000000000000000000000000000000000000000';
      expect(hexOf(encoded), expected);
    });

    test(
      'a unique name resolves regardless of arg count mismatch handling',
      () {
        final fn = ChainWriter.resolveOverloadedFunction(
          registry,
          'getListedPolls',
          0,
        );
        expect(fn.name, 'getListedPolls');
      },
    );

    test('unknown name and ambiguous arity both throw ArgumentError', () {
      expect(
        () => ChainWriter.resolveOverloadedFunction(registry, 'noSuchFn', 0),
        throwsArgumentError,
      );
      expect(
        () => ChainWriter.resolveOverloadedFunction(registry, 'createPoll', 3),
        throwsArgumentError,
      );
    });
  });

  group('module initialize gained trailing uint8 resultsPolicy', () {
    test('ZkAnonVoting.initialize(semaphore, owner, options, resultsPolicy=1) '
        'encodes the frozen ethers calldata, selector 41323ccf', () {
      // node -e '… new ethers.Interface(
      //   ["function initialize(address,address,string[],uint8)"])
      //   .encodeFunctionData("initialize",[semaphore,owner,["Yes","No"],1])'
      const expected =
          '41323ccf'
          '0000000000000000000000009fe46736679d2d9a65f0992f2272de9f3c7fa6e0'
          '000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb92266'
          '0000000000000000000000000000000000000000000000000000000000000080'
          '0000000000000000000000000000000000000000000000000000000000000001'
          '0000000000000000000000000000000000000000000000000000000000000002'
          '0000000000000000000000000000000000000000000000000000000000000040'
          '0000000000000000000000000000000000000000000000000000000000000080'
          '0000000000000000000000000000000000000000000000000000000000000003'
          '5965730000000000000000000000000000000000000000000000000000000000'
          '0000000000000000000000000000000000000000000000000000000000000002'
          '4e6f000000000000000000000000000000000000000000000000000000000000';
      final encoded = anon.function('initialize').encodeCall([
        EthereumAddress.fromHex(semaphore),
        EthereumAddress.fromHex(owner),
        ['Yes', 'No'],
        BigInt.one,
      ]);
      expect(hexOf(encoded), expected);
    });

    test('sealed default (resultsPolicy=0) only flips the policy word', () {
      final sealed = hexOf(
        anon.function('initialize').encodeCall([
          EthereumAddress.fromHex(semaphore),
          EthereumAddress.fromHex(owner),
          ['Yes', 'No'],
          BigInt.zero,
        ]),
      );
      // Word 4 (the uint8 resultsPolicy) is zero; everything else matches the
      // policy=1 vector.
      expect(sealed.substring(8 + 3 * 64, 8 + 4 * 64), '0' * 64);
    });
  });

  group('PollCreated event (trailing uint8 visibility ⇒ topic0 changed)', () {
    test('refreshed ABI yields the R4 topic0', () {
      final event = registry.event('PollCreated');
      // node -e '… ethers.id(
      //   "PollCreated(address,string,string,address,uint8)")'
      expect(
        hexOf(event.signature),
        '7ac209aaa9a1f7dea658ea2e4208a42cdd4154a2225d09771eb05b50a5808fbc',
      );
    });
  });

  group('PollInfo decoder (trailing visibility field)', () {
    List<dynamic> tuple({bool withVisibility = true, int visibility = 1}) => [
      EthereumAddress.fromHex('0xd8058efe0198ae9dD7D563e1b4938Dcbc86A1F81'),
      'anon-vote',
      'Title',
      'Desc',
      EthereumAddress.fromHex(owner),
      BigInt.from(1700000000),
      if (withVisibility) BigInt.from(visibility),
    ];

    test('decodes the R4 7-field tuple including visibility', () {
      final info = PollInfo.fromTuple(tuple());
      expect(info.moduleType, 'anon-vote');
      expect(info.createdAt, BigInt.from(1700000000));
      expect(info.visibility, PollInfo.visibilityListed);
      expect(info.isListed, isTrue);
    });

    test('unlisted (0) decodes as not listed', () {
      expect(PollInfo.fromTuple(tuple(visibility: 0)).isListed, isFalse);
    });

    test('tolerates a pre-R4 6-field tuple → unlisted default', () {
      final info = PollInfo.fromTuple(tuple(withVisibility: false));
      expect(info.visibility, PollInfo.visibilityUnlisted);
      expect(info.isListed, isFalse);
    });
  });
}
