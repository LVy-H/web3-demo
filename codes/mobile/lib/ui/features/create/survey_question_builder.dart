import 'package:flutter/material.dart';

import '../../../data/services/poll_creator.dart';
import '../../core/theme.dart';

/// On-chain caps for the `survey-vote` module, mirrored client-side so the form
/// can gate the deploy button BEFORE `initialize` would revert:
/// `1 ≤ questions ≤ MAX_QUESTIONS (16)` and, per question,
/// `2 ≤ options ≤ MAX_OPTIONS (32)`.
const int kSurveyMaxQuestions = 16;
const int kSurveyMaxOptions = 32;
const int kSurveyMinOptions = 2;

/// A single editable question in the survey draft. Owns its option-text
/// controllers + its [SurveyQType], and disposes the controllers it created.
class SurveyQuestionDraft {
  SurveyQuestionDraft({
    this.qType = SurveyQType.singleChoice,
    List<String>? options,
  }) : options = [
          for (final o in options ?? const ['', ''])
            TextEditingController(text: o),
        ];

  SurveyQType qType;
  final List<TextEditingController> options;

  /// The trimmed, non-empty option labels — what actually deploys on-chain.
  List<String> get filledOptions =>
      options.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();

  void dispose() {
    for (final c in options) {
      c.dispose();
    }
  }
}

/// The whole survey-draft state: an ordered list of [SurveyQuestionDraft]s. The
/// Create screen owns one of these so `_create()` can read the questions out
/// (via [toQuestions]); the [SurveyQuestionBuilder] widget edits it in place and
/// calls `onChanged` so the parent re-evaluates the deploy gate.
class SurveyDraft {
  SurveyDraft({List<SurveyQuestionDraft>? questions})
      : questions = questions ?? [SurveyQuestionDraft()];

  final List<SurveyQuestionDraft> questions;

  /// The questions as [SurveyQuestion]s (trimmed, non-empty options) for the
  /// `createSurveyPoll` inner encoder. Call only when [isValid] is true.
  List<SurveyQuestion> toQuestions() => [
        for (final q in questions)
          SurveyQuestion(qType: q.qType, options: q.filledOptions),
      ];

  /// True when the draft satisfies the on-chain caps the contract enforces:
  /// `1 ≤ questions ≤ 16` and every question has `2 ≤ non-empty options ≤ 32`.
  /// This is the survey's OWN validation — the flat anon/approval/ranked/
  /// quadratic option-count guard does NOT apply here.
  bool get isValid => validationError == null;

  /// A human hint for WHY the draft can't deploy yet, or null when it's valid.
  /// Surfaced under the builder so the user sees why the button is disabled.
  String? get validationError {
    if (questions.isEmpty) return 'Add at least one question.';
    if (questions.length > kSurveyMaxQuestions) {
      return 'A survey allows at most $kSurveyMaxQuestions questions — '
          'remove ${questions.length - kSurveyMaxQuestions}.';
    }
    for (var i = 0; i < questions.length; i++) {
      final n = questions[i].filledOptions.length;
      if (n < kSurveyMinOptions) {
        return 'Question ${i + 1} needs at least $kSurveyMinOptions options.';
      }
      if (n > kSurveyMaxOptions) {
        return 'Question ${i + 1} allows at most $kSurveyMaxOptions options — '
            'remove ${n - kSurveyMaxOptions}.';
      }
    }
    return null;
  }

  void dispose() {
    for (final q in questions) {
      q.dispose();
    }
  }
}

/// The survey question-builder: a repeating list of questions, each with a
/// single-choice / multi-select type toggle and an editable option list
/// (add/remove rows). Add/remove whole questions. Edits a [SurveyDraft] in place
/// and calls [onChanged] after every mutation so the parent re-evaluates the
/// deploy gate (the draft holds the controllers; this widget is stateless about
/// content — it just renders + mutates the draft).
class SurveyQuestionBuilder extends StatelessWidget {
  const SurveyQuestionBuilder({
    super.key,
    required this.draft,
    required this.onChanged,
  });

  final SurveyDraft draft;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < draft.questions.length; i++) ...[
          if (i > 0) const SizedBox(height: 18),
          _questionCard(i),
        ],
        const SizedBox(height: 12),
        _addQuestionButton(),
      ],
    );
  }

  Widget _questionCard(int qi) {
    final q = draft.questions[qi];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Db.slate3,
        border: Border.all(color: Db.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('QUESTION ${qi + 1}',
                style: dbLabel(size: 10, tracking: 0.16)),
            const Spacer(),
            if (draft.questions.length > 1)
              IconButton(
                key: ValueKey('remove-question-$qi'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.delete_outline, size: 18, color: Db.mute),
                onPressed: () {
                  draft.questions.removeAt(qi).dispose();
                  onChanged();
                },
              ),
          ]),
          const SizedBox(height: 12),
          _typeToggle(q),
          const SizedBox(height: 14),
          Text('OPTIONS', style: dbLabel(size: 9, tracking: 0.16)),
          const SizedBox(height: 8),
          for (var oi = 0; oi < q.options.length; oi++) _optionRow(q, qi, oi),
          const SizedBox(height: 4),
          _addOptionButton(q),
        ],
      ),
    );
  }

  Widget _typeToggle(SurveyQuestionDraft q) {
    return Row(children: [
      _typeChip(
        q: q,
        type: SurveyQType.singleChoice,
        label: 'Single choice',
        icon: Icons.radio_button_checked,
      ),
      const SizedBox(width: 8),
      _typeChip(
        q: q,
        type: SurveyQType.multiSelect,
        label: 'Multi-select',
        icon: Icons.check_box,
      ),
    ]);
  }

  Widget _typeChip({
    required SurveyQuestionDraft q,
    required SurveyQType type,
    required String label,
    required IconData icon,
  }) {
    final selected = q.qType == type;
    return Expanded(
      child: InkWell(
        onTap: () {
          if (q.qType != type) {
            q.qType = type;
            onChanged();
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
          decoration: BoxDecoration(
            color: selected ? Db.segnale.withValues(alpha: 0.10) : Db.slate,
            border: Border.all(
                color: selected ? Db.segnale : Db.rule,
                width: selected ? 2 : 1),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 14, color: selected ? Db.segnale : Db.mute),
            const SizedBox(width: 8),
            Text(label,
                style: dbSans(12, 700, selected ? Db.chalk : Db.mute)),
          ]),
        ),
      ),
    );
  }

  Widget _optionRow(SurveyQuestionDraft q, int qi, int oi) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Text('0${oi + 1}', style: dbMono(12, Db.mute, wght: 700)),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              key: ValueKey('q$qi-opt$oi'),
              controller: q.options[oi],
              onChanged: (_) => onChanged(),
              style: dbSans(13, 600, Db.chalk),
              cursorColor: Db.segnale,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: Db.slate,
                hintText: 'Option ${oi + 1}',
                hintStyle: dbSans(12, 400, Db.muteDim),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                enabledBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(color: Db.rule)),
                focusedBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(color: Db.segnale)),
              ),
            ),
          ),
          if (q.options.length > kSurveyMinOptions)
            IconButton(
              key: ValueKey('remove-q$qi-opt$oi'),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: const Icon(Icons.close, size: 15, color: Db.mute),
              onPressed: () {
                q.options.removeAt(oi).dispose();
                onChanged();
              },
            ),
        ]),
      );

  Widget _addOptionButton(SurveyQuestionDraft q) => Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          // Don't grow past the on-chain MAX_OPTIONS cap.
          onPressed: q.options.length >= kSurveyMaxOptions
              ? null
              : () {
                  q.options.add(TextEditingController());
                  onChanged();
                },
          icon: const Icon(Icons.add, size: 14, color: Db.chalkDim),
          label: Text('ADD OPTION',
              style: dbLabel(size: 10, color: Db.chalkDim)),
        ),
      );

  Widget _addQuestionButton() => Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          // Don't grow past the on-chain MAX_QUESTIONS cap.
          onPressed: draft.questions.length >= kSurveyMaxQuestions
              ? null
              : () {
                  draft.questions.add(SurveyQuestionDraft());
                  onChanged();
                },
          icon: const Icon(Icons.add_circle_outline,
              size: 16, color: Db.segnale),
          label: Text('ADD QUESTION',
              style: dbLabel(size: 11, color: Db.segnale)),
        ),
      );
}
