/// The CREATE flow (spec §4.2 organizer journey, §5 privacy defaults),
/// machine-driven: this widget renders the [OrganizerJourneyMachine]'s
/// current state — draft form → deploying → created (distribute) — and
/// dispatches only the events the current state allows.
///
/// Privacy is BY DESIGN here, not a settings screen: the two §5 opt-ins
/// ("list publicly", "show live results") are switches that start OFF, and
/// an untouched form deploys an unlisted, sealed-until-close poll.
library;

import 'dart:async';

import 'package:core_domain/journeys/capabilities.dart';
import 'package:core_domain/journeys/journey.dart';
import 'package:core_domain/journeys/organizer_journey.dart';
import 'package:core_domain/journeys/policy.dart';
import 'package:design_system/dot_grid_background.dart';
import 'package:design_system/theme.dart';
import 'package:feature_join/feature_join.dart' show shareLinkForPoll;
import 'package:flutter/material.dart';

import '../home/organizer_poll_card.dart';
import '../module_names.dart';
import '../organize_copy.dart';
import '../share/distribute_sheet.dart';

class CreateFlowView extends StatefulWidget {
  static const Key deployButtonKey = Key('create-deploy');
  static const Key disabledReasonKey = Key('create-disabled-reason');
  static const Key titleFieldKey = Key('create-title');
  static const Key listedToggleKey = Key('toggle-listed');
  static const Key liveResultsToggleKey = Key('toggle-live-results');
  static const Key doneButtonKey = Key('create-done');

  final OrganizerJourneyPort port;
  final Capabilities capabilities;

  /// Called from the created state's "GO TO YOUR POLLS" exit.
  final void Function(String pollAddress) onDone;

  const CreateFlowView({
    super.key,
    required this.port,
    required this.capabilities,
    required this.onDone,
  });

  @override
  State<CreateFlowView> createState() => _CreateFlowViewState();
}

class _CreateFlowViewState extends State<CreateFlowView> {
  late final OrganizerJourneyMachine _machine = OrganizerJourneyMachine(
    port: widget.port,
    capabilities: widget.capabilities,
  );
  StreamSubscription<OrganizerState>? _sub;

  // ── form state (pushed into the machine's draft on every edit) ──────────
  //
  // The picker chooses one of the FIVE deployable ballot types ([_ballotType],
  // never blindVote). Sealed/commit-reveal creation is intentionally NOT offered
  // here — RelayOrganizerPort.deployPoll refuses blindVote (the relayer's
  // sponsored allow-list excludes it), so a sealing control would be a ghost.
  // See module_names.dart; tracked for R5 (sealed-ballots).
  OrganizerModule _ballotType = recommendedBallotType;

  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final List<TextEditingController> _options = [
    TextEditingController(),
    TextEditingController(),
  ];
  final List<_QuestionDraft> _questions = [];

  // Spec §5 opt-ins — DEFAULT OFF (private defaults).
  bool _listed = false;
  bool _liveResults = false;

  @override
  void initState() {
    super.initState();
    _sub = _machine.states.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _machine.dispose();
    _title.dispose();
    _description.dispose();
    for (final c in _options) {
      c.dispose();
    }
    for (final q in _questions) {
      q.dispose();
    }
    super.dispose();
  }

  OrganizerPollSpec _spec() => OrganizerPollSpec(
    module: _ballotType,
    title: _title.text,
    description: _description.text,
    options: [for (final c in _options) c.text],
    questions: [
      for (final q in _questions)
        SurveyQuestionSpec(
          prompt: q.prompt.text,
          options: [for (final c in q.options) c.text],
        ),
    ],
    visibility: _listed ? PollVisibility.listed : PollVisibility.unlisted,
    resultsPolicy: _liveResults
        ? ResultsPolicy.livePublic
        : ResultsPolicy.sealedUntilClose,
    // Blind/commit-reveal is never created here (the relayer refuses it), so
    // there is never a reveal window to set. See R5 (sealed-ballots).
    revealWindow: null,
  );

  /// Push the current form into the machine's draft (legal from the draft
  /// only — edits during deploy are absorbed by the read-only overlay).
  void _sync() {
    if (_machine.state is OrganizerDraft) {
      _machine.advance(OrganizerDraftUpdated(_spec()));
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = _machine.state;
    return Scaffold(
      appBar: AppBar(title: Text('CREATE', style: dbSectionTitle)),
      body: DotGridBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: switch (state) {
                OrganizerCreated created => _createdView(created),
                OrganizerDeployFailed failed => _failedView(failed),
                _ => _formView(state),
              },
            ),
          ),
        ),
      ),
    );
  }

  // ── draft / deploying ────────────────────────────────────────────────────

  Widget _formView(OrganizerState state) {
    final deploying = state is OrganizerDeployInProgress;
    final action = state.nextAction;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 96),
      children: [
        AbsorbPointer(
          absorbing: deploying,
          child: Opacity(
            opacity: deploying ? 0.6 : 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label('HOW PEOPLE VOTE'),
                const SizedBox(height: 10),
                _modulePicker(),
                const SizedBox(height: 24),
                _label('WHAT IT IS'),
                const SizedBox(height: 10),
                _field(
                  key: CreateFlowView.titleFieldKey,
                  controller: _title,
                  hint: 'Title — what are people deciding?',
                ),
                const SizedBox(height: 10),
                _field(
                  controller: _description,
                  hint: 'Description (optional)',
                  maxLines: 3,
                ),
                const SizedBox(height: 24),
                if (_ballotType.usesQuestions)
                  _questionBuilder()
                else
                  _optionsBuilder(),
                const SizedBox(height: 24),
                _privacyPanel(),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        if (action != null)
          FilledButton(
            key: CreateFlowView.deployButtonKey,
            style: FilledButton.styleFrom(
              backgroundColor: Db.segnale,
              foregroundColor: Db.void_,
              disabledBackgroundColor: Db.slate4,
              disabledForegroundColor: Db.mute,
              shape: const RoundedRectangleBorder(),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: (deploying || !action.enabled) ? null : _deploy,
            child: deploying
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        organizeCopy('action.organizer.deploying'),
                        style: dbMono(13, Db.chalk),
                      ),
                    ],
                  )
                : Text(
                    organizeCopy(action.labelKey),
                    style: dbMono(13, action.enabled ? Db.void_ : Db.mute),
                  ),
          ),
        if (!deploying && action?.disabledReasonKey != null) ...[
          const SizedBox(height: 10),
          Text(
            organizeCopy(action!.disabledReasonKey!),
            key: CreateFlowView.disabledReasonKey,
            style: dbSans(12, 400, Db.mute, height: 1.5),
          ),
        ],
      ],
    );
  }

  void _deploy() {
    _machine.advance(const OrganizerDeployRequested());
    setState(() {});
  }

  /// Goal-grouped ballot-type picker: one section per [BallotGroup], every
  /// card always showing its one-line differentiator so an organizer can
  /// compare before choosing (spec 2026-06-13). "Pick one" comes pre-selected.
  Widget _modulePicker() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var g = 0; g < BallotGroup.values.length; g++) ...[
        if (g > 0) const SizedBox(height: 16),
        _label(BallotGroup.values[g].label),
        const SizedBox(height: 8),
        for (final module in BallotGroup.values[g].modules) ...[
          _ballotCard(module),
          const SizedBox(height: 8),
        ],
      ],
    ],
  );

  Widget _ballotCard(OrganizerModule module) {
    final selected = module == _ballotType;
    final badge = isRecommendedBallot(module)
        ? 'Recommended'
        : (isAdvancedBallot(module) ? 'Advanced' : null);
    return InkWell(
      key: Key('ballot-${module.wireName}'),
      onTap: () => _selectBallot(module),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? Db.slate2 : null,
          border: Border.all(color: selected ? Db.segnale : Db.rule),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1, right: 10),
              child: Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 16,
                color: selected ? Db.segnale : Db.mute,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          moduleDisplayName(module),
                          style: dbMono(13, selected ? Db.chalk : Db.chalkDim),
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        _badge(badge),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    moduleBlurb(module),
                    style: dbSans(12, 400, Db.chalkDim, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(border: Border.all(color: Db.segnale)),
    child: Text(text.toUpperCase(), style: dbMono(9, Db.segnale)),
  );

  void _selectBallot(OrganizerModule module) {
    _ballotType = module;
    if (module.usesQuestions && _questions.isEmpty) {
      _questions.add(_QuestionDraft());
    }
    _sync();
  }

  Widget _optionsBuilder() {
    final capped = _ballotType.capsOptionsAtEight && _options.length >= 8;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('ANSWER OPTIONS'),
        const SizedBox(height: 10),
        for (var i = 0; i < _options.length; i++) ...[
          Row(
            children: [
              Expanded(
                child: _field(
                  key: Key('create-option-$i'),
                  controller: _options[i],
                  hint: 'Option ${i + 1}',
                ),
              ),
              if (_options.length > 2)
                IconButton(
                  key: Key('remove-option-$i'),
                  tooltip: 'Remove option ${i + 1}',
                  onPressed: () {
                    _options.removeAt(i).dispose();
                    _sync();
                  },
                  icon: Icon(
                    Icons.close,
                    size: 16,
                    color: Db.mute,
                    semanticLabel: 'Remove option ${i + 1}',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        if (!capped)
          OutlinedButton(
            key: const Key('create-add-option'),
            onPressed: () {
              _options.add(TextEditingController());
              _sync();
            },
            child: Text('+ ADD OPTION', style: dbMono(11, Db.chalkDim)),
          )
        else
          Text(
            'This poll type holds up to 8 options.',
            style: dbSans(11, 400, Db.mute),
          ),
      ],
    );
  }

  Widget _questionBuilder() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _label('QUESTIONS'),
      const SizedBox(height: 10),
      for (var q = 0; q < _questions.length; q++) ...[
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Db.slate3,
            border: Border.all(color: Db.rule),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text('QUESTION ${q + 1}', style: dbLabel())),
                  if (_questions.length > 1)
                    IconButton(
                      key: Key('remove-question-$q'),
                      tooltip: 'Remove question ${q + 1}',
                      onPressed: () {
                        _questions.removeAt(q).dispose();
                        _sync();
                      },
                      icon: Icon(
                        Icons.close,
                        size: 16,
                        color: Db.mute,
                        semanticLabel: 'Remove question ${q + 1}',
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              _field(
                key: Key('question-$q-prompt'),
                controller: _questions[q].prompt,
                hint: 'What do you want to ask?',
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < _questions[q].options.length; i++) ...[
                Row(
                  children: [
                    Expanded(
                      child: _field(
                        key: Key('question-$q-option-$i'),
                        controller: _questions[q].options[i],
                        hint: 'Answer ${i + 1}',
                      ),
                    ),
                    if (_questions[q].options.length > 2)
                      IconButton(
                        key: Key('remove-question-$q-option-$i'),
                        tooltip:
                            'Remove answer ${i + 1} from question ${q + 1}',
                        onPressed: () {
                          _questions[q].options.removeAt(i).dispose();
                          _sync();
                        },
                        icon: Icon(
                          Icons.close,
                          size: 16,
                          color: Db.mute,
                          semanticLabel:
                              'Remove answer ${i + 1} from question ${q + 1}',
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              OutlinedButton(
                key: Key('question-$q-add-option'),
                onPressed: () {
                  _questions[q].options.add(TextEditingController());
                  _sync();
                },
                child: Text('+ ADD ANSWER', style: dbMono(11, Db.chalkDim)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
      OutlinedButton(
        key: const Key('create-add-question'),
        onPressed: () {
          _questions.add(_QuestionDraft());
          _sync();
        },
        child: Text('+ ADD QUESTION', style: dbMono(11, Db.chalkDim)),
      ),
    ],
  );

  /// Spec §5: the two opt-ins, OFF by default, each saying what the private
  /// default means in one line.
  Widget _privacyPanel() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Db.slate3,
      border: Border.all(color: Db.rule),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('PRIVACY'),
        const SizedBox(height: 4),
        _toggleRow(
          key: CreateFlowView.listedToggleKey,
          title: 'List publicly in the app directory',
          explanation:
              'Off: only people you share the link, QR, or code with can '
              'find this poll.',
          value: _listed,
          onChanged: (value) {
            _listed = value;
            _sync();
          },
        ),
        const SizedBox(height: 4),
        _toggleRow(
          key: CreateFlowView.liveResultsToggleKey,
          title: 'Show live results while voting',
          explanation:
              'Off: nobody — including you — sees the tally until voting '
              'closes.',
          value: _liveResults,
          onChanged: (value) {
            _liveResults = value;
            _sync();
          },
        ),
      ],
    ),
  );

  Widget _toggleRow({
    required Key key,
    required String title,
    required String explanation,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            Text(title, style: dbSans(13, 600, Db.chalk)),
            const SizedBox(height: 3),
            Text(explanation, style: dbSans(11, 400, Db.chalkDim, height: 1.4)),
          ],
        ),
      ),
      Switch(
        key: key,
        value: value,
        activeThumbColor: Db.segnale,
        onChanged: onChanged,
      ),
    ],
  );

  // ── deploy failed ────────────────────────────────────────────────────────

  Widget _failedView(OrganizerDeployFailed failed) {
    final cause = failed.cause;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Db.slate3,
            border: Border.all(color: Db.segnale),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                organizeCopy(failed.messageKey),
                style: dbSans(13, 500, Db.chalk, height: 1.5),
              ),
              if (cause != null) ...[
                const SizedBox(height: 8),
                Text(
                  '$cause',
                  key: const Key('create-failed-cause'),
                  style: dbSans(12, 400, Db.chalkDim, height: 1.5),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('create-retry'),
          style: FilledButton.styleFrom(
            backgroundColor: Db.segnale,
            foregroundColor: Db.void_,
            shape: const RoundedRectangleBorder(),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: () {
            _machine.advance(const Retry());
            setState(() {});
          },
          child: Text(
            organizeCopy('action.retry'),
            style: dbMono(12, Db.void_),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          key: const Key('create-edit'),
          onPressed: () {
            _machine.advance(OrganizerDraftUpdated(_spec()));
            setState(() {});
          },
          child: Text('KEEP EDITING', style: dbMono(12, Db.chalk)),
        ),
      ],
    );
  }

  // ── created ──────────────────────────────────────────────────────────────

  Widget _createdView(OrganizerCreated created) => ListView(
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
    children: [
      Text('YOUR POLL IS READY', style: dbSectionTitle),
      const SizedBox(height: 16),
      OrganizerPollCard(
        state: created,
        title: created.spec.title,
        onAction: () => _distribute(created),
        onDistribute: () => _distribute(created),
      ),
      const SizedBox(height: 8),
      OutlinedButton(
        key: CreateFlowView.doneButtonKey,
        onPressed: () => widget.onDone(created.pollAddress),
        child: Text('GO TO YOUR POLLS', style: dbMono(12, Db.chalk)),
      ),
    ],
  );

  void _distribute(OrganizerCreated created) {
    DistributeSheet.show(
      context,
      shareLink: shareLinkForPoll(
        created.pollAddress,
        module: created.spec.module.wireName,
      ),
      nfcAvailable: created.shareTargets.contains(ShareTarget.nfc),
    );
  }

  // ── shared bits ──────────────────────────────────────────────────────────

  Widget _label(String text) => Text(text, style: dbLabel());

  Widget _field({
    Key? key,
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
  }) => TextField(
    key: key,
    controller: controller,
    maxLines: maxLines,
    style: dbSans(14, 400, Db.chalk),
    onChanged: (_) => _sync(),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: dbSans(13, 400, Db.mute),
      filled: true,
      fillColor: Db.slate3,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      enabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: Db.rule),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: Db.segnale),
      ),
    ),
  );
}

class _QuestionDraft {
  final TextEditingController prompt = TextEditingController();
  final List<TextEditingController> options = [
    TextEditingController(),
    TextEditingController(),
  ];

  void dispose() {
    prompt.dispose();
    for (final c in options) {
      c.dispose();
    }
  }
}
