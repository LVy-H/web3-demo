import 'package:convert/convert.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:core_relay/poll_creator.dart';

/// GATE-2 ANALOG for the survey CREATE path: the INNER `initData` bytes.
///
/// `ZkSurveyVoting.initialize(address, address, bytes initData)` decodes
/// `initData` via `abi.decode(initData, (Question[]))` where
/// `struct Question { QType qType; string[] options; }`. So the inner bytes are
/// `abi.encode((uint8,string[])[])` of the questions. If the Dart encoding does
/// NOT match Solidity's decode byte-for-byte, EVERY survey creation reverts
/// `InitFailed`.
///
/// Each pinned hex below is the OUTPUT of ethers, computed ONCE and frozen:
///
///   node -e 'const {ethers}=require("ethers");console.log(
///     ethers.AbiCoder.defaultAbiCoder().encode(
///       ["tuple(uint8,string[])[]"], [VALUE]))'
///
/// run in `codes/contracts` (where ethers is installed). Because
/// ethers `AbiCoder.encode(["tuple(uint8,string[])[]"], [value])` IS Solidity's
/// `abi.encode((uint8,string[])[])`, asserting `encodeSurveyInitData(...) ==`
/// this literal pins  Dart-encode ≡ ethers ≡ Solidity-`abi.decode(...,
/// (Question[]))`. The leading `0x…20` offset word is part of that canonical
/// encoding (a single dynamic top-level value), which is why the Dart encoder
/// wraps the array in an outer tuple — encoding the bare array would start with
/// the array length and the contract decode would reject it.
void main() {
  String enc(List<SurveyQuestion> qs) => hex.encode(encodeSurveyInitData(qs));

  group('encodeSurveyInitData matches ethers abi.encode((uint8,string[])[])',
      () {
    test('sample 1 — mixed: [SingleChoice(A,B,C), MultiSelect(X,Y,Z,W)]', () {
      // node -e 'const {ethers}=require("ethers");console.log(
      //   ethers.AbiCoder.defaultAbiCoder().encode(["tuple(uint8,string[])[]"],
      //     [[[0,["A","B","C"]],[1,["X","Y","Z","W"]]]]))'
      //
      // This hex === ethers abi.encode((uint8,string[])[]) === what Solidity
      // `abi.decode(initData, (Question[]))` accepts → pins Dart ≡ Solidity.
      const expected =
          '0000000000000000000000000000000000000000000000000000000000000020'
          '0000000000000000000000000000000000000000000000000000000000000002'
          '0000000000000000000000000000000000000000000000000000000000000040'
          '00000000000000000000000000000000000000000000000000000000000001c0'
          '0000000000000000000000000000000000000000000000000000000000000000'
          '0000000000000000000000000000000000000000000000000000000000000040'
          '0000000000000000000000000000000000000000000000000000000000000003'
          '0000000000000000000000000000000000000000000000000000000000000060'
          '00000000000000000000000000000000000000000000000000000000000000a0'
          '00000000000000000000000000000000000000000000000000000000000000e0'
          '0000000000000000000000000000000000000000000000000000000000000001'
          '4100000000000000000000000000000000000000000000000000000000000000'
          '0000000000000000000000000000000000000000000000000000000000000001'
          '4200000000000000000000000000000000000000000000000000000000000000'
          '0000000000000000000000000000000000000000000000000000000000000001'
          '4300000000000000000000000000000000000000000000000000000000000000'
          '0000000000000000000000000000000000000000000000000000000000000001'
          '0000000000000000000000000000000000000000000000000000000000000040'
          '0000000000000000000000000000000000000000000000000000000000000004'
          '0000000000000000000000000000000000000000000000000000000000000080'
          '00000000000000000000000000000000000000000000000000000000000000c0'
          '0000000000000000000000000000000000000000000000000000000000000100'
          '0000000000000000000000000000000000000000000000000000000000000140'
          '0000000000000000000000000000000000000000000000000000000000000001'
          '5800000000000000000000000000000000000000000000000000000000000000'
          '0000000000000000000000000000000000000000000000000000000000000001'
          '5900000000000000000000000000000000000000000000000000000000000000'
          '0000000000000000000000000000000000000000000000000000000000000001'
          '5a00000000000000000000000000000000000000000000000000000000000000'
          '0000000000000000000000000000000000000000000000000000000000000001'
          '5700000000000000000000000000000000000000000000000000000000000000';

      final actual = enc(const [
        SurveyQuestion(
            qType: SurveyQType.singleChoice, options: ['A', 'B', 'C']),
        SurveyQuestion(
            qType: SurveyQType.multiSelect, options: ['X', 'Y', 'Z', 'W']),
      ]);
      expect(actual, expected);
      // First word is the 0x…20 offset, NOT the array length 0x…02 — the proof
      // the outer-tuple wrap emitted the leading offset head.
      expect(actual.substring(0, 64),
          '0000000000000000000000000000000000000000000000000000000000000020');
    });

    test('sample 2 — single single-choice question: [SingleChoice(Yes,No)]',
        () {
      // node -e 'const {ethers}=require("ethers");console.log(
      //   ethers.AbiCoder.defaultAbiCoder().encode(["tuple(uint8,string[])[]"],
      //     [[[0,["Yes","No"]]]]))'
      const expected =
          '0000000000000000000000000000000000000000000000000000000000000020'
          '0000000000000000000000000000000000000000000000000000000000000001'
          '0000000000000000000000000000000000000000000000000000000000000020'
          '0000000000000000000000000000000000000000000000000000000000000000'
          '0000000000000000000000000000000000000000000000000000000000000040'
          '0000000000000000000000000000000000000000000000000000000000000002'
          '0000000000000000000000000000000000000000000000000000000000000040'
          '0000000000000000000000000000000000000000000000000000000000000080'
          '0000000000000000000000000000000000000000000000000000000000000003'
          '5965730000000000000000000000000000000000000000000000000000000000'
          '0000000000000000000000000000000000000000000000000000000000000002'
          '4e6f000000000000000000000000000000000000000000000000000000000000';

      final actual = enc(const [
        SurveyQuestion(
            qType: SurveyQType.singleChoice, options: ['Yes', 'No']),
      ]);
      expect(actual, expected);
    });
  });
}
