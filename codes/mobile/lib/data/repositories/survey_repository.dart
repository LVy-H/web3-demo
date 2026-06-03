import '../services/chain_reader.dart';

/// One question of a survey: its [type] (0 = SingleChoice, 1 = MultiSelect, the
/// on-chain `ZkSurveyVoting.QType`) and its own [options] labels. Built from the
/// per-question chain reads (`getQuestionType(q)` + `getQuestionOptions(q)`).
class SurveyQuestion {
  /// 0 = SingleChoice (`answers[q]` = chosen option index), 1 = MultiSelect
  /// (`answers[q]` = a bitmask, bit i ⇒ option i).
  final int type;

  /// This question's own option labels, in option order.
  final List<String> options;

  const SurveyQuestion({required this.type, required this.options});

  bool get isSingleChoice => type == 0;
  bool get isMultiSelect => type == 1;
}

/// A point-in-time read of a survey: phase, the ordered [questions]
/// (type + own options each), the per-question per-option tally [results]
/// (`results[q][option]`), owner, and participant count.
class SurveyStructure {
  final String address;
  final int state; // 0 reg, 1 voting, 2 ended (IZkPoll.PollState)
  final List<SurveyQuestion> questions;
  final List<List<BigInt>> results; // [q][option] => count
  final String owner;
  final BigInt participantCount;

  const SurveyStructure({
    required this.address,
    required this.state,
    required this.questions,
    required this.results,
    required this.owner,
    required this.participantCount,
  });

  int get questionCount => questions.length;
}

/// Data layer for the Phase 12d survey module (`survey-vote`). Unlike the M3/M4/
/// QV sibling repos — which reuse the flat single-question `IZkPoll` reads — a
/// survey has a NESTED structure (an ordered `Question[]`, each with its own type
/// + options + tally), so this fans out the per-question reads
/// (`getQuestionType(q)` / `getQuestionOptions(q)`) and decodes the nested
/// `getSurveyResults()` (a `uint256[][]`).
///
/// `fetchGroup` reuses the shared `getRegisteredCommitments` — `ZkSurveyVoting`
/// emits the same `VoterRegistered(uint256)` event as every other module, so the
/// group reconstruction is identical (no survey-specific event decode). The
/// registration pre-check (derive commitment / test group membership) is done in
/// the view-model exactly like the sibling modules.
///
/// ViewModels depend on this abstraction (not on [ChainReader]) so they stay
/// unit-testable with fakes.
abstract class SurveyRepository {
  /// Read the full survey structure (phase, per-question types + options, the
  /// per-question tally, owner, participant count) in one aggregate call.
  Future<SurveyStructure> fetchSurvey(String address);

  /// The survey's Semaphore group (registered identity commitments) — the member
  /// set a survey proof is built against, and the set the registration pre-check
  /// tests membership in. Same event/decode as every other module.
  Future<List<String>> fetchGroup(String address);

  /// Just the per-question tally (`results[q][option]`) — a lighter read for
  /// refreshing the results distribution without re-reading the structure.
  Future<List<List<BigInt>>> getSurveyResults(String address);
}

/// On-chain implementation backed by [ChainReader] (JSON-RPC reads). The survey
/// structure is assembled from `getQuestionCount` + the per-question
/// `getQuestionType`/`getQuestionOptions` reads, plus the nested
/// `getSurveyResults`.
class ChainSurveyRepository implements SurveyRepository {
  final ChainReader reader;
  const ChainSurveyRepository(this.reader);

  @override
  Future<List<String>> fetchGroup(String address) =>
      reader.getRegisteredCommitments(address);

  @override
  Future<List<List<BigInt>>> getSurveyResults(String address) =>
      reader.getSurveyResults(address);

  @override
  Future<SurveyStructure> fetchSurvey(String address) async {
    // First fetch the shared reads + the question count concurrently.
    final base = await Future.wait([
      reader.getState(address),
      reader.getOwner(address),
      reader.getParticipantCount(address),
      reader.getSurveyQuestionCount(address),
      reader.getSurveyResults(address),
    ]);
    final state = base[0] as int;
    final owner = base[1] as String;
    final participantCount = base[2] as BigInt;
    final count = base[3] as int;
    final results = base[4] as List<List<BigInt>>;

    // Then fan out the per-question type + options reads (one per question),
    // concurrently, and assemble the ordered question list.
    final questions = await Future.wait([
      for (var q = 0; q < count; q++)
        Future.wait([
          reader.getSurveyQuestionType(address, q),
          reader.getSurveyQuestionOptions(address, q),
        ]).then((qr) => SurveyQuestion(
              type: qr[0] as int,
              options: qr[1] as List<String>,
            )),
    ]);

    return SurveyStructure(
      address: address,
      state: state,
      questions: questions,
      results: results,
      owner: owner,
      participantCount: participantCount,
    );
  }
}
