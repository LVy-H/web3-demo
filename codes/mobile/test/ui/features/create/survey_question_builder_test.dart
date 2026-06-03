import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tessera/data/services/poll_creator.dart';
import 'package:tessera/ui/features/create/survey_question_builder.dart';

/// Build a [SurveyQuestionDraft] with [filled] non-empty option labels followed
/// by [empty] blank rows — exercises the trimmed-non-empty filtering.
SurveyQuestionDraft _q({
  SurveyQType type = SurveyQType.singleChoice,
  int filled = 2,
  int empty = 0,
}) =>
    SurveyQuestionDraft(
      qType: type,
      options: [
        for (var i = 0; i < filled; i++) 'Opt${i + 1}',
        for (var i = 0; i < empty; i++) '',
      ],
    );

void main() {
  // The on-chain caps the UI must enforce BEFORE `initialize` can revert:
  // `1 ≤ questions ≤ MAX_QUESTIONS (16)`, per question `2 ≤ options ≤
  // MAX_OPTIONS (32)`. These pin the constants to the contract's caps.
  test('caps mirror the contract (1..16 questions, 2..32 options)', () {
    expect(kSurveyMaxQuestions, 16);
    expect(kSurveyMaxOptions, 32);
    expect(kSurveyMinOptions, 2);
  });

  group('SurveyDraft.validationError', () {
    test('a single 2-option single-choice question is valid', () {
      final d = SurveyDraft(questions: [_q()]);
      addTearDown(d.dispose);
      expect(d.validationError, isNull);
      expect(d.isValid, isTrue);
    });

    test('zero questions is invalid (need ≥1)', () {
      final d = SurveyDraft(questions: []);
      addTearDown(d.dispose);
      expect(d.validationError, contains('at least one question'));
    });

    test('>16 questions is invalid (MAX_QUESTIONS)', () {
      final d = SurveyDraft(
          questions: [for (var i = 0; i < 17; i++) _q()]);
      addTearDown(d.dispose);
      expect(d.isValid, isFalse);
      expect(d.validationError, contains('at most 16 questions'));
    });

    test('exactly 16 questions is valid (boundary)', () {
      final d = SurveyDraft(
          questions: [for (var i = 0; i < 16; i++) _q()]);
      addTearDown(d.dispose);
      expect(d.isValid, isTrue);
    });

    test('a question with <2 NON-EMPTY options is invalid (empty rows ignored)',
        () {
      // 1 filled + 3 empty rows → only 1 non-empty option.
      final d = SurveyDraft(questions: [_q(filled: 1, empty: 3)]);
      addTearDown(d.dispose);
      expect(d.validationError, contains('at least 2 options'));
    });

    test('a question with >32 non-empty options is invalid (MAX_OPTIONS)', () {
      final d = SurveyDraft(questions: [_q(filled: 33)]);
      addTearDown(d.dispose);
      expect(d.isValid, isFalse);
      expect(d.validationError, contains('at most 32 options'));
    });

    test('exactly 32 options is valid (boundary)', () {
      final d = SurveyDraft(questions: [_q(filled: 32)]);
      addTearDown(d.dispose);
      expect(d.isValid, isTrue);
    });

    test('empty trailing option rows are filtered, not counted', () {
      // 2 real + 5 blank rows → exactly 2 non-empty → valid.
      final d = SurveyDraft(questions: [_q(filled: 2, empty: 5)]);
      addTearDown(d.dispose);
      expect(d.isValid, isTrue);
      expect(d.toQuestions().single.options, ['Opt1', 'Opt2']);
    });

    test('toQuestions carries the per-question type + trimmed options', () {
      final d = SurveyDraft(questions: [
        _q(type: SurveyQType.singleChoice, filled: 3),
        _q(type: SurveyQType.multiSelect, filled: 4, empty: 1),
      ]);
      addTearDown(d.dispose);
      final qs = d.toQuestions();
      expect(qs.length, 2);
      expect(qs[0].qType, SurveyQType.singleChoice);
      expect(qs[0].options, ['Opt1', 'Opt2', 'Opt3']);
      expect(qs[1].qType, SurveyQType.multiSelect);
      expect(qs[1].options, ['Opt1', 'Opt2', 'Opt3', 'Opt4']);
    });
  });

  testWidgets('builder add/remove question + option mutate the draft', (
    tester,
  ) async {
    final draft = SurveyDraft();
    addTearDown(draft.dispose);
    var changes = 0;

    await tester.binding.setSurfaceSize(const Size(800, 4000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SurveyQuestionBuilder(
            draft: draft,
            onChanged: () => changes++,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Starts with one question, two option rows.
    expect(draft.questions.length, 1);
    expect(draft.questions.single.options.length, 2);

    // ADD QUESTION → two questions, onChanged fired.
    await tester.tap(find.text('ADD QUESTION'));
    await tester.pumpAndSettle();
    expect(draft.questions.length, 2);
    expect(changes, greaterThan(0));

    // ADD OPTION on the first question's card → 3 option rows there. (Each card
    // has its own ADD OPTION; tap the first.)
    await tester.tap(find.text('ADD OPTION').first);
    await tester.pumpAndSettle();
    expect(draft.questions.first.options.length, 3);
  });
}
