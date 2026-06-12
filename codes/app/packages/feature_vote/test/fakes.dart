// Shared fakes for the port-adapter and screen tests: core service classes
// subclassed with canned answers — no network, no platform channels.
import 'package:core_chain/chain_reader.dart';
import 'package:core_chain/chain_writer.dart';
import 'package:core_domain/models/relay_proof.dart';
import 'package:core_relay/relay_client.dart';

const testPollAddress = '0x1111111111111111111111111111111111111111';

final testProof = RelayProof(
  merkleTreeDepth: 16,
  merkleTreeRoot: '111',
  nullifier: '424242424242',
  message: '0',
  scope: testPollAddress,
  points: List.filled(8, '1'),
);

class FakeChainReader extends ChainReader {
  int state = 1;
  List<String> options = const ['Alpha', 'Beta', 'Gamma'];
  List<BigInt> results = [BigInt.from(3), BigInt.from(2), BigInt.zero];
  String owner = '0x2222222222222222222222222222222222222222';
  BigInt participantCount = BigInt.from(5);
  List<String> commitments = const [];
  int surveyQuestionCount = 2;
  Map<int, int> surveyTypes = const {0: 0, 1: 1};
  Map<int, List<String>> surveyOptions = const {
    0: ['Yes', 'No'],
    1: ['Mon', 'Tue', 'Wed'],
  };

  FakeChainReader()
    : super(
        rpcUrl: 'http://localhost:1',
        izkPollAbiJson: '[]',
        registryAbiJson: '[]',
        anonVotingAbiJson: '[]',
        registryAddress: '0x0000000000000000000000000000000000000001',
      );

  @override
  Future<int> getState(String pollAddress) async => state;

  @override
  Future<List<String>> getOptions(String pollAddress) async => options;

  @override
  Future<List<BigInt>> getResults(String pollAddress) async => results;

  @override
  Future<String> getOwner(String pollAddress) async => owner;

  @override
  Future<BigInt> getParticipantCount(String pollAddress) async =>
      participantCount;

  @override
  Future<List<String>> getRegisteredCommitments(String pollAddress) async =>
      commitments;

  @override
  Future<int> getSurveyQuestionCount(String pollAddress) async =>
      surveyQuestionCount;

  @override
  Future<int> getSurveyQuestionType(String pollAddress, int q) async =>
      surveyTypes[q] ?? 0;

  @override
  Future<List<String>> getSurveyQuestionOptions(
    String pollAddress,
    int q,
  ) async => surveyOptions[q] ?? const [];

  @override
  Future<List<List<BigInt>>> getSurveyResults(String pollAddress) async => [
    for (var q = 0; q < surveyQuestionCount; q++)
      [for (final _ in surveyOptions[q] ?? const <String>[]) BigInt.one],
  ];

  // ── blind reads ──
  bool registered = false;
  bool committed = false;
  bool revealed = false;
  bool finalized = false;
  BigInt revealDeadline = BigInt.zero;

  @override
  Future<bool> isRegistered(String pollAddress, String voter) async =>
      registered;

  @override
  Future<bool> hasVoted(String pollAddress, String voter) async => committed;

  @override
  Future<bool> hasRevealed(String pollAddress, String voter) async => revealed;

  @override
  Future<bool> isFinalized(String pollAddress) async => finalized;

  @override
  Future<BigInt> getRevealDeadline(String pollAddress) async => revealDeadline;
}

class FakeRelayClient extends RelayClient {
  final calls = <(String endpoint, Object payload, RelayProof proof)>[];
  bool registerOk = true;
  bool relayOk = true;

  FakeRelayClient() : super(baseUrl: 'http://localhost:1');

  RelayResult get _result => relayOk
      ? const RelayResult(success: true, txHash: '0xtx')
      : const RelayResult(success: false, error: 'nope');

  @override
  Future<RegisterResult> registerVoter(
    String pollAddress,
    String identityCommitment,
  ) async {
    calls.add(('register', identityCommitment, testProof));
    return registerOk
        ? const RegisterResult(ok: true, txHash: '0xjoin')
        : const RegisterResult(error: 'closed');
  }

  @override
  Future<RelayResult> relayVote(
    String pollAddress,
    int vote,
    RelayProof proof,
  ) async {
    calls.add(('vote', vote, proof));
    return _result;
  }

  @override
  Future<RelayResult> relayApprovalVote(
    String pollAddress,
    int bitmask,
    RelayProof proof,
  ) async {
    calls.add(('approval-vote', bitmask, proof));
    return _result;
  }

  @override
  Future<RelayResult> relayRankedVote(
    String pollAddress,
    int packedRanking,
    RelayProof proof,
  ) async {
    calls.add(('ranked-vote', packedRanking, proof));
    return _result;
  }

  @override
  Future<RelayResult> relayQuadraticVote(
    String pollAddress,
    int packedAlloc,
    RelayProof proof,
  ) async {
    calls.add(('quadratic-vote', packedAlloc, proof));
    return _result;
  }

  @override
  Future<RelayResult> relaySurveyVote(
    String pollAddress,
    List<BigInt> answers,
    RelayProof proof,
  ) async {
    calls.add(('survey-vote', answers, proof));
    return _result;
  }
}

class FakeChainWriter extends ChainWriter {
  final sends = <(String function, List<dynamic> params)>[];

  FakeChainWriter({bool withSigner = true})
    : super(
        rpcUrl: 'http://localhost:1',
        chainId: 31337,
        // Hardhat's well-known dev key #0 — test-only signer identity.
        privateKey: withSigner
            ? '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80'
            : '',
      );

  @override
  Future<String> send({
    required String to,
    required String abiJson,
    required String abiName,
    required String function,
    List<dynamic> params = const [],
  }) async {
    sends.add((function, params));
    return '0xsent';
  }
}
