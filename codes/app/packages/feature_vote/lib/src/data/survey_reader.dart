/// Survey structure reads for the questionnaire ballot and results.
///
/// A survey is the one module whose ballot can't be rendered from the flat
/// `IZkPoll` snapshot: it has an ordered question list, each with its own
/// type (pick-one vs pick-any) and option labels. This fans out the
/// per-question chain reads, mirroring the proven legacy survey repository.
library;

import 'package:core_chain/chain_reader.dart';

/// One survey question: its kind and its own option labels.
class SurveyQuestion {
  /// 0 = pick one (`answers[q]` = chosen option index),
  /// 1 = pick any (`answers[q]` = a bitmask, bit i ⇒ option i).
  final int type;
  final List<String> options;

  const SurveyQuestion({required this.type, required this.options});

  bool get isSingleChoice => type == 0;
}

/// The full survey structure plus (when present) the per-question tally.
class SurveyDetails {
  final List<SurveyQuestion> questions;

  /// `results[q][option]` — empty when not requested.
  final List<List<BigInt>> results;

  const SurveyDetails({required this.questions, this.results = const []});

  int get questionCount => questions.length;
}

/// Loads a survey's questions (and optionally its tally) via [ChainReader].
class SurveyReader {
  final ChainReader reader;
  final String pollAddress;

  const SurveyReader({required this.reader, required this.pollAddress});

  Future<SurveyDetails> load({bool withResults = false}) async {
    final count = await reader.getSurveyQuestionCount(pollAddress);
    final questions = <SurveyQuestion>[];
    for (var q = 0; q < count; q++) {
      questions.add(
        SurveyQuestion(
          type: await reader.getSurveyQuestionType(pollAddress, q),
          options: await reader.getSurveyQuestionOptions(pollAddress, q),
        ),
      );
    }
    final results = withResults
        ? await reader.getSurveyResults(pollAddress)
        : const <List<BigInt>>[];
    return SurveyDetails(questions: questions, results: results);
  }
}
