import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/survey_repository.dart';
import '../../../data/services/identity_store.dart';
import '../../../data/services/proof_service_factory.dart';
import '../../core/dot_grid_background.dart';
import '../../core/format.dart';
import '../../core/poll_header.dart';
import '../../core/theme.dart';
import '../../core/view_state.dart';
import '../../widgets/results_bars.dart';
import 'survey_vote_view_model.dart';

/// Survey detail (module `survey-vote`) — Dark Bauhaus. A multi-question
/// "Google-Forms" ballot: each question is answered with a RADIO group
/// (SingleChoice) or CHECKBOXES (MultiSelect) over that question's own options;
/// the voter casts ONE anonymous ballot binding the WHOLE answer vector.
///
/// Two survey-specific behaviors vs. the QV sibling:
///
/// 1. BALLOT: instead of one packed allocation, the ballot is a
///    `List<BigInt> answers` (one word per question). The Semaphore `message`
///    is a WIDE keccak
///    commitment over the whole vector (`surveyCommitment(answers)`), proven via
///    `generateVoteProofWide`. Casting is gated on EVERY question being answered.
///
/// 2. RESULTS: a survey shows a response DISTRIBUTION per question, not an
///    election winner — so it renders N `ResultsBars` (one per question), each
///    with `highlightLeader: false` (NO per-question trophy) and a neutral
///    "Responses" caption. This is the opposite of QV (which crowns the leader).
class SurveyPollScreen extends StatefulWidget {
  final String address;
  const SurveyPollScreen({super.key, required this.address});
  @override
  State<SurveyPollScreen> createState() => _SurveyPollScreenState();
}

class _SurveyPollScreenState extends State<SurveyPollScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<SurveyVoteViewModel>().load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DotGridBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: Consumer<SurveyVoteViewModel>(
                builder: (context, vm, _) => switch (vm.state) {
                  ViewState.idle || ViewState.loading => const Center(
                      child: CircularProgressIndicator(color: Db.segnale),
                    ),
                  ViewState.error => _ErrorView(
                      message: vm.error ?? 'Unknown error',
                      onRetry: vm.load,
                    ),
                  ViewState.loaded => _Body(survey: vm.survey!),
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final SurveyStructure survey;
  const _Body({required this.survey});

  String get _shortAddr => shortAddr(survey.address);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(shortAddr: _shortAddr),
            const SizedBox(height: 20),
            _PhaseStrip(state: survey.state),
            const SizedBox(height: 16),
            Text(
              '${survey.participantCount} REGISTERED · ${survey.questionCount} '
              'QUESTIONS — ANSWER EACH, THEN CAST ONE ANONYMOUS BALLOT',
              style: dbLabel(size: 11, tracking: 0.1),
            ),
            const SizedBox(height: 24),
            // Results are a per-question DISTRIBUTION — always shown (every
            // phase), not just during Voting.
            _SurveyResults(survey: survey),
            const SizedBox(height: 20),
            // The answer FORM is web-only (gated on proofServiceAvailable);
            // native/desktop are read-only. Only render it during Voting.
            if (survey.state == 1) _AnswerArea(survey: survey),
            const SizedBox(height: 24),
            Text('OWNER', style: dbLabel(size: 10)),
            const SizedBox(height: 4),
            Text(
              survey.owner,
              style: dbMono(11, Db.mute, letterSpacing: 0.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String shortAddr;
  const _Header({required this.shortAddr});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 12),
        child: pollDetailHeaderRow(
          context: context,
          badgeLabel: 'ZK · SURVEY',
          badgeColor: Db.oltremare,
          shortAddr: shortAddr,
        ),
      );
}

class _PhaseStrip extends StatelessWidget {
  final int state; // 0 reg, 1 voting, 2 ended
  const _PhaseStrip({required this.state});
  static const _labels = ['REGISTRATION', 'VOTING', 'ENDED'];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border.fromBorderSide(BorderSide(color: Db.rule)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < 3; i++)
            Expanded(
              child: Container(
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: i == state
                      ? Db.segnale
                      : (i < state ? Db.slate : Db.void_),
                  border: i < 2
                      ? const Border(right: BorderSide(color: Db.rule))
                      : null,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (i < state) ...[
                        const Icon(Icons.check, size: 13, color: Db.mute),
                        const SizedBox(width: 6),
                      ] else if (i > state) ...[
                        Text(
                          '0${i + 1}',
                          style: dbMono(11, Db.muteDim, wght: 700),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        _labels[i],
                        style: dbSans(
                          11,
                          800,
                          i == state ? Db.void_ : Db.mute,
                          letterSpacing: 11 * 0.16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// N `ResultsBars` — one per question — from `getSurveyResults()[q]` zipped with
/// that question's option labels. A survey is a response DISTRIBUTION, not an
/// election, so each question passes `highlightLeader: false` (NO trophy) and a
/// neutral "Responses" caption.
class _SurveyResults extends StatelessWidget {
  final SurveyStructure survey;
  const _SurveyResults({required this.survey});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Db.slate,
        border: Border.fromBorderSide(BorderSide(color: Db.rule)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          resultsTitleRow(
              icon: Icons.bar_chart,
              title: 'SURVEY RESULTS',
              trailing: '${survey.participantCount} RESPONDENTS'),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.insights_outlined, size: 13, color: Db.oltremare),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Per-question response distribution — a survey shows how '
                  'respondents answered, not a single winner.',
                  style: dbMono(11, Db.oltremare, height: 1.4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          for (var q = 0; q < survey.questions.length; q++) ...[
            if (q > 0) ...[
              const SizedBox(height: 20),
              const Divider(height: 1, color: Db.ruleSoft),
              const SizedBox(height: 20),
            ],
            _QuestionResults(
              index: q,
              question: survey.questions[q],
              counts: q < survey.results.length
                  ? survey.results[q]
                  : const <BigInt>[],
            ),
          ],
        ],
      ),
    );
  }
}

class _QuestionResults extends StatelessWidget {
  final int index;
  final SurveyQuestion question;
  final List<BigInt> counts;
  const _QuestionResults({
    required this.index,
    required this.question,
    required this.counts,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Q${index + 1}', style: dbLabel(size: 11, tracking: 0.1)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: const BoxDecoration(
                color: Db.void_,
                border: Border.fromBorderSide(BorderSide(color: Db.rule)),
              ),
              child: Text(
                question.isMultiSelect ? 'MULTI-SELECT' : 'SINGLE CHOICE',
                style: dbLabel(size: 9, tracking: 0.12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ResultsBars(
          // A survey question is a DISTRIBUTION — never crown a per-question
          // "winner". (Opposite of QV; same no-trophy spirit as ranked, for a
          // different reason.)
          highlightLeader: false,
          emptyLabel: 'No responses yet',
          options: [
            for (var i = 0; i < question.options.length; i++)
              (
                label: question.options[i],
                count: i < counts.length ? counts[i] : BigInt.zero,
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text('Responses', style: dbLabel(size: 9, tracking: 0.12)),
      ],
    );
  }
}

// ── Answer area (web has a prover; native/desktop read-only) ─────────────────

class _AnswerArea extends StatelessWidget {
  final SurveyStructure survey;
  const _AnswerArea({required this.survey});
  @override
  Widget build(BuildContext context) {
    if (!proofServiceAvailable) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Db.slate,
          border: Border.fromBorderSide(BorderSide(color: Db.rule)),
        ),
        child: Row(
          children: [
            const Icon(Icons.lock_outline, color: Db.mute, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Voting runs in the web app (mobile coming soon). This build is read-only.',
                style: dbMono(12, Db.mute, height: 1.5),
              ),
            ),
          ],
        ),
      );
    }
    return _AnswerForm(survey: survey);
  }
}

class _AnswerForm extends StatefulWidget {
  final SurveyStructure survey;
  const _AnswerForm({required this.survey});
  @override
  State<_AnswerForm> createState() => _AnswerFormState();
}

class _AnswerFormState extends State<_AnswerForm> {
  final _seed = TextEditingController();

  bool _fromSavedIdentity = false;
  Timer? _regDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final saved = await context.read<IdentityStore>().read();
      if (!mounted || saved == null || saved.isEmpty || _seed.text.isNotEmpty) {
        return;
      }
      setState(() {
        _seed.text = saved;
        _fromSavedIdentity = true;
      });
      context.read<SurveyVoteViewModel>().checkRegistration(saved.trim());
    });
  }

  void _onSeedChanged(String value) {
    setState(() => _fromSavedIdentity = false);
    _regDebounce?.cancel();
    final seed = value.trim();
    final vm = context.read<SurveyVoteViewModel>();
    if (seed.isEmpty) {
      vm.clearRegistration();
      return;
    }
    _regDebounce = Timer(
      const Duration(milliseconds: 600),
      () => vm.checkRegistration(seed),
    );
  }

  @override
  void dispose() {
    _regDebounce?.cancel();
    _seed.dispose();
    super.dispose();
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(m, style: dbMono(12, Db.chalk)),
          backgroundColor: Db.slate,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SurveyVoteViewModel>();
    // Disable cast unless every question is answered (the contract's mandatory
    // rule), an identity is entered, and no cast is in flight.
    final canCast = vm.canCast && _seed.text.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Db.slate,
        border: Border.fromBorderSide(BorderSide(color: Db.rule)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ANSWER THE SURVEY', style: dbSectionTitle),
          const SizedBox(height: 6),
          Text(
            'Answer every question below — pick one option for single-choice, '
            'check any number for multi-select. All questions are mandatory.',
            style: dbMono(11, Db.mute, height: 1.5),
          ),
          const SizedBox(height: 16),
          for (var q = 0; q < widget.survey.questions.length; q++) ...[
            if (q > 0) const SizedBox(height: 18),
            _QuestionForm(
              index: q,
              question: widget.survey.questions[q],
              vm: vm,
            ),
          ],
          const SizedBox(height: 18),
          if (_fromSavedIdentity)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(Icons.fingerprint, size: 13, color: Db.success),
                  const SizedBox(width: 6),
                  Text(
                    'using your saved identity',
                    style: dbLabel(size: 10, color: Db.success),
                  ),
                ],
              ),
            ),
          TextField(
            controller: _seed,
            onChanged: _onSeedChanged,
            style: dbMono(13, Db.chalk),
            cursorColor: Db.segnale,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              filled: true,
              fillColor: Db.void_,
              hintText: 'paste your invite token / identity seed',
              hintStyle: dbMono(12, Db.mute),
              enabledBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: Db.rule),
              ),
              focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: Db.segnale),
              ),
            ),
          ),
          _RegistrationStatus(vm: vm, onCopy: _snack),
          const SizedBox(height: 14),
          _CastButton(
            busyLabel: switch (vm.status) {
              SurveyVoteStatus.proving => 'GENERATING PROOF…',
              SurveyVoteStatus.relaying => 'SUBMITTING…',
              _ => null,
            },
            enabled: canCast,
            onTap: canCast
                ? () => context.read<SurveyVoteViewModel>().castSurvey(
                      identitySeed: _seed.text.trim(),
                    )
                : null,
          ),
          if (vm.status == SurveyVoteStatus.success)
            _statusLine(
              Icons.check_circle,
              Db.success,
              'BALLOT COUNTED · ${vm.txHash ?? ''}',
            ),
          if (vm.status == SurveyVoteStatus.error)
            _statusLine(
              Icons.error_outline,
              Db.segnale,
              vm.castError ?? 'Ballot failed',
            ),
        ],
      ),
    );
  }

  Widget _statusLine(IconData icon, Color color, String text) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: dbMono(12, color))),
          ],
        ),
      );
}

/// One question's answer control: a RADIO group (SingleChoice) or CHECKBOXES
/// (MultiSelect) over that question's options, with the question label.
class _QuestionForm extends StatelessWidget {
  final int index;
  final SurveyQuestion question;
  final SurveyVoteViewModel vm;
  const _QuestionForm({
    required this.index,
    required this.question,
    required this.vm,
  });

  @override
  Widget build(BuildContext context) {
    final answered = vm.isAnswered(index);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Db.void_,
        border: Border.all(color: answered ? Db.success : Db.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Q${index + 1}', style: dbLabel(size: 11, tracking: 0.1)),
              const SizedBox(width: 8),
              Text(
                question.isMultiSelect
                    ? 'CHECK ANY THAT APPLY'
                    : 'PICK ONE',
                style: dbLabel(size: 9, tracking: 0.12),
              ),
              const Spacer(),
              if (answered)
                const Icon(Icons.check_circle, size: 14, color: Db.success),
            ],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < question.options.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            if (question.isMultiSelect)
              _MultiOption(
                label: question.options[i],
                color: Db.optionColor(i),
                checked: vm.multiSelections[index].contains(i),
                onTap: vm.isBusy ? null : () => vm.toggleMulti(index, i),
              )
            else
              _SingleOption(
                label: question.options[i],
                color: Db.optionColor(i),
                selected: vm.singleSelections[index] == i,
                onTap: vm.isBusy ? null : () => vm.selectSingle(index, i),
              ),
          ],
        ],
      ),
    );
  }
}

/// A radio-style option row for a SingleChoice question.
class _SingleOption extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;
  const _SingleOption({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.12) : Db.slate,
            border: Border.all(
              color: selected ? color : Db.rule,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 18,
                color: selected ? color : Db.mute,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: dbSans(14, selected ? 700 : 600, Db.chalk),
                ),
              ),
            ],
          ),
        ),
      );
}

/// A checkbox-style option row for a MultiSelect question.
class _MultiOption extends StatelessWidget {
  final String label;
  final Color color;
  final bool checked;
  final VoidCallback? onTap;
  const _MultiOption({
    required this.label,
    required this.color,
    required this.checked,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: checked ? color.withValues(alpha: 0.12) : Db.slate,
            border: Border.all(
              color: checked ? color : Db.rule,
              width: checked ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                checked ? Icons.check_box : Icons.check_box_outline_blank,
                size: 18,
                color: checked ? color : Db.mute,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: dbSans(14, checked ? 700 : 600, Db.chalk),
                ),
              ),
            ],
          ),
        ),
      );
}

// Proactive registration status (identical pattern to the sibling modules).
class _RegistrationStatus extends StatelessWidget {
  final SurveyVoteViewModel vm;
  final void Function(String) onCopy;
  const _RegistrationStatus({required this.vm, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    if (vm.checkingRegistration) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          children: [
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2, color: Db.mute),
            ),
            const SizedBox(width: 10),
            Text('checking…', style: dbMono(11, Db.mute)),
          ],
        ),
      );
    }
    if (vm.isRegistered == true) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Db.success.withValues(alpha: 0.10),
            border: Border.all(color: Db.success),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check, size: 14, color: Db.success),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Registered — ready to vote',
                  style: dbMono(11, Db.success, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (vm.isRegistered == false && vm.myCommitment != null) {
      final commitment = vm.myCommitment!;
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: const BoxDecoration(
            color: Db.slate,
            border: Border(left: BorderSide(color: Db.amber, width: 3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.error_outline, size: 16, color: Db.amber),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Not registered in this survey. Share your identity '
                      'commitment with the organizer to be added:',
                      style: dbMono(11, Db.chalkDim, height: 1.4),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SelectableText(
                commitment,
                style: dbMono(11, Db.chalk, height: 1.4),
              ),
              const SizedBox(height: 10),
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: commitment));
                  onCopy('Commitment copied to clipboard.');
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: const BoxDecoration(
                    color: Db.void_,
                    border: Border.fromBorderSide(BorderSide(color: Db.rule)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.copy_outlined,
                        size: 14,
                        color: Db.chalkDim,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        'COPY',
                        style: dbLabel(size: 10, color: Db.chalkDim),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _CastButton extends StatelessWidget {
  final bool enabled;
  final String? busyLabel;
  final VoidCallback? onTap;
  const _CastButton({
    required this.enabled,
    this.busyLabel,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final label = busyLabel ??
        (enabled
            ? 'CAST SURVEY BALLOT →'
            : '[ ANSWER EVERY QUESTION ]');
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? Db.segnale : Db.void_,
          border: Border.all(color: enabled ? Db.segnale : Db.rule),
        ),
        child: Text(
          label,
          style: dbSans(
            13,
            800,
            enabled ? Db.void_ : Db.mute,
            letterSpacing: 13 * 0.12,
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, color: Db.segnale, size: 40),
              const SizedBox(height: 12),
              Text(
                "COULDN'T LOAD THIS SURVEY",
                style: dbLabel(size: 12, color: Db.chalk),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: dbMono(12, Db.mute),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: onRetry,
                style: OutlinedButton.styleFrom(
                  shape: const RoundedRectangleBorder(),
                  side: const BorderSide(color: Db.rule),
                ),
                child:
                    Text('RETRY', style: dbLabel(size: 11, color: Db.chalk)),
              ),
            ],
          ),
        ),
      );
}
