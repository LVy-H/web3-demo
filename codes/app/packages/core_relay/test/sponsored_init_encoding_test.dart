import 'dart:convert';
import 'dart:io';

import 'package:convert/convert.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:core_relay/poll_creator.dart';
import 'package:core_relay/sponsored_poll_creator.dart';

/// Pins the SPONSORED create path's wire format to the PRE-R4 `initialize`
/// encodings — the relayer's create API contract (PR #108 decision 3, see
/// `sponsored_poll_creator.dart`'s class doc).
///
/// The relayer's `appendResultsPolicyToInitData` decodes client initData
/// against the pre-R4 shapes unconditionally and re-encodes it with the
/// request's `resultsPolicy` appended. So the client encoders here must KEEP
/// emitting the pre-R4 selectors even though core_chain's bundled ABIs are R4
/// now — these tests fail loudly if anyone "fixes" the encoders to the R4
/// fragments (which would make the shim double-append and every sponsored
/// create revert `InitFailed`).
///
/// Golden hex is frozen ethers v6 output, computed once in `codes/relayer`:
///
///   node -e 'const {ethers}=require("ethers");
///     const i=new ethers.Interface(
///       ["function initialize(address,address,string[])"]);
///     console.log(i.encodeFunctionData("initialize",
///       ["0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0",
///        "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",["Yes","No"]]))'
void main() {
  const semaphore = '0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0';
  const owner = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266';

  // The injected ABI is core_chain's CURRENT (R4) asset — exactly what the
  // production wiring passes — proving the wire format does not follow it.
  String abiArray(String path) =>
      jsonEncode(jsonDecode(File(path).readAsStringSync())['abi']);
  final r4FlatAbi = abiArray('../core_chain/assets/abi/ZkAnonVoting.json');
  final r4SurveyAbi = abiArray('../core_chain/assets/abi/ZkSurveyVoting.json');

  test('encodeFlatInitData emits the PRE-R4 selector + frozen ethers bytes '
      'even when handed the refreshed R4 module ABI', () {
    final encoded = hex.encode(
      encodeFlatInitData(
        flatModuleAbiJson: r4FlatAbi,
        semaphore: semaphore,
        owner: owner,
        options: const ['Yes', 'No'],
      ),
    );
    const expected =
        '1c7fac40' // initialize(address,address,string[])
        '0000000000000000000000009fe46736679d2d9a65f0992f2272de9f3c7fa6e0'
        '000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb92266'
        '0000000000000000000000000000000000000000000000000000000000000060'
        '0000000000000000000000000000000000000000000000000000000000000002'
        '0000000000000000000000000000000000000000000000000000000000000040'
        '0000000000000000000000000000000000000000000000000000000000000080'
        '0000000000000000000000000000000000000000000000000000000000000003'
        '5965730000000000000000000000000000000000000000000000000000000000'
        '0000000000000000000000000000000000000000000000000000000000000002'
        '4e6f000000000000000000000000000000000000000000000000000000000000';
    expect(encoded, expected);
  });

  test('encodeSurveyOuterInitData keeps the PRE-R4 survey selector cf7a1d77 '
      '(initialize(address,address,bytes)) and wraps the inner questions', () {
    final encoded = hex.encode(
      encodeSurveyOuterInitData(
        surveyVotingAbiJson: r4SurveyAbi,
        semaphore: semaphore,
        owner: owner,
        questions: const [
          SurveyQuestion(
            qType: SurveyQType.singleChoice,
            options: ['Yes', 'No'],
          ),
        ],
      ),
    );
    expect(
      encoded.substring(0, 8),
      'cf7a1d77',
      reason:
          'pre-R4 survey initialize selector — the relayer shim '
          'decodes this shape',
    );
    // The inner abi.encode((uint8,string[])[]) bytes appear verbatim inside
    // the outer bytes arg (already pinned against ethers in
    // survey_init_encoding_test.dart).
    final inner = hex.encode(
      encodeSurveyInitData(const [
        SurveyQuestion(qType: SurveyQType.singleChoice, options: ['Yes', 'No']),
      ]),
    );
    expect(encoded.contains(inner), isTrue);
  });
}
