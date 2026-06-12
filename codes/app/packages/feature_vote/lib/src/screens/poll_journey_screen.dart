/// The proof-module poll surface: a thin renderer of the
/// [VoterJourneyMachine]'s current state (spec §4.2 — screens are journey
/// states, not feature pages).
///
/// EXACTLY one primary action per state; disabled actions always show their
/// reason; success auto-advances through receipt to the results (visible or
/// sealed per policy) — the voter is *taken* to their receipt, never left on
/// a stale form.
library;

import 'dart:async';

import 'package:core_domain/journeys/journey.dart';
import 'package:core_domain/journeys/policy.dart';
import 'package:core_domain/journeys/voter_journey.dart';
import 'package:design_system/theme.dart';
import 'package:design_system/widgets/results_bars.dart';
import 'package:flutter/material.dart';

import '../data/survey_reader.dart';
import '../widgets/ballots/ballots.dart';
import '../widgets/vote_chrome.dart';

class PollJourneyScreen extends StatefulWidget {
  final VoterJourneyMachine machine;
  final String title;

  /// Jargon-free poll-kind label ("PICK ONE", "RANK THEM", …).
  final String kindLabel;

  /// Survey structure loader (questionnaire polls only).
  final Future<SurveyDetails> Function()? loadSurveyDetails;

  /// Survey structure + tally loader (questionnaire results only).
  final Future<SurveyDetails> Function()? loadSurveyResults;

  /// Opens the receipt verifier with the receipt code.
  final void Function(String receiptCode)? onVerifyReceipt;

  /// Links "your voting pass" copy to the You space.
  final VoidCallback? onOpenIdentity;

  const PollJourneyScreen({
    super.key,
    required this.machine,
    required this.title,
    required this.kindLabel,
    this.loadSurveyDetails,
    this.loadSurveyResults,
    this.onVerifyReceipt,
    this.onOpenIdentity,
  });

  static const successKey = Key('vote-success-panel');
  static const refreshKey = Key('poll-refresh-action');

  @override
  State<PollJourneyScreen> createState() => _PollJourneyScreenState();
}

class _PollJourneyScreenState extends State<PollJourneyScreen> {
  StreamSubscription<VoterState>? _sub;

  /// The receipt, captured when the cast lands so the results screen can keep
  /// showing it after the machine moves past the receipt states.
  VoterReceipt? _receipt;

  /// Whether the ballot's LOCAL selection is currently a valid spec (the
  /// machine only stores valid drafts; this also covers "deselected back to
  /// empty", which the machine cannot represent).
  bool _draftValid = false;

  Future<SurveyDetails>? _surveyDetails;
  Future<SurveyDetails>? _surveyResults;

  VoterJourneyMachine get machine => widget.machine;

  @override
  void initState() {
    super.initState();
    _draftValid = switch (machine.state) {
      VoterBallotOpen(:final draft) => draft != null,
      _ => false,
    };
    _sub = machine.states.listen(_onState);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onState(VoterState state) {
    if (!mounted) return;
    switch (state) {
      case VoterCastSucceeded(:final receipt, :final refreshed):
        _receipt = receipt;
        // The machine owns post-cast freshness; once refreshed, walk straight
        // through the receipt acknowledgment — the UI shows receipt+results
        // together (no extra tap to find your receipt).
        if (refreshed) {
          unawaited(machine.advance(const VoterReceiptAcknowledged()));
        }
      case VoterReceiptSaved(:final receipt):
        _receipt = receipt;
        unawaited(machine.advance(const VoterResultsRequested()));
      case VoterBallotOpen(:final draft):
        if (draft != null) _draftValid = true;
      default:
        break;
    }
    setState(() {});
  }

  void _advance(JourneyEvent event) => unawaited(machine.advance(event));

  bool get _canRefresh => switch (machine.state) {
    VoterNotEligible() ||
    VoterJoinPending() ||
    VoterWaitingForOpen() ||
    VoterBallotOpen() => true,
    _ => false,
  };

  @override
  Widget build(BuildContext context) {
    final state = machine.state;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        actions: [
          if (_canRefresh)
            IconButton(
              key: PollJourneyScreen.refreshKey,
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh, size: 20, color: Db.mute),
              onPressed: () => _advance(const Refresh()),
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            children: [_header(), const SizedBox(height: 18), ..._body(state)],
          ),
        ),
      ),
      // The ONE primary action stays pinned — never scrolled out of reach.
      bottomNavigationBar: switch (_footerAction(state)) {
        null => null,
        final action => SafeArea(
          minimum: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: action,
            ),
          ),
        ),
      },
    );
  }

  /// The pinned primary action for [state], or null when the state's action
  /// is passive progress already shown in the body (or there is none).
  Widget? _footerAction(VoterState state) => switch (state) {
    VoterProvingInProgress() => PrimaryActionButton(
      action: state.nextAction!,
      onPressed: () => _advance(const VoterProvingCancelled()),
    ),
    VoterNotEligible(:final nextAction, :final canRequestJoin) =>
      PrimaryActionButton(
        action: nextAction!,
        onPressed: canRequestJoin
            ? () => _advance(const VoterRequestJoin())
            : null,
      ),
    VoterJoinPending(:final nextAction) => PrimaryActionButton(
      action: nextAction!,
      onPressed: () => _advance(const Refresh()),
    ),
    VoterWaitingForOpen(:final nextAction) => PrimaryActionButton(
      action: nextAction!,
      onPressed: null,
    ),
    VoterBallotOpen() => PrimaryActionButton(
      action: _draftValid
          ? const NextAction(
              labelKey: 'action.castVote',
              type: NextActionType.submit,
            )
          : const NextAction(
              labelKey: 'action.castVote',
              type: NextActionType.submit,
              disabledReasonKey: 'reason.noSelection',
            ),
      onPressed: _draftValid
          ? () => _advance(const VoterBallotSubmitted())
          : null,
    ),
    _ => null,
  };

  Widget _header() {
    final view = _viewOf(machine.state);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.kindLabel, style: dbLabel(size: 10, color: Db.segnale)),
        const SizedBox(height: 6),
        Text(
          widget.title.isEmpty ? 'VOTE' : widget.title,
          style: dbSans(28, 800, Db.chalk, height: 1.05),
        ),
        if (view != null) ...[
          const SizedBox(height: 16),
          PhaseStrip(phase: view.phase),
          const SizedBox(height: 10),
          Text(
            '${view.snapshot.participantCount} JOINED',
            style: dbLabel(size: 10, tracking: 0.1),
          ),
        ],
      ],
    );
  }

  VoterPollView? _viewOf(VoterState state) => switch (state) {
    VoterEligibilityChecking(:final view) ||
    VoterNotEligible(:final view) ||
    VoterJoinInProgress(:final view) ||
    VoterJoinFailed(:final view) ||
    VoterJoinPending(:final view) ||
    VoterRegistrationStillPending(:final view) ||
    VoterWaitingForOpen(:final view) ||
    VoterBallotOpen(:final view) ||
    VoterProvingInProgress(:final view) ||
    VoterProofFailed(:final view) ||
    VoterCastInProgress(:final view) ||
    VoterRelayFailed(:final view) ||
    VoterCastSucceeded(:final view) ||
    VoterReceiptSaved(:final view) ||
    VoterResultsSealed(:final view) ||
    VoterResultsVisible(:final view) => view,
    _ => null,
  };

  List<Widget> _body(VoterState state) => switch (state) {
    VoterLoading() => const [ProgressPanel(title: 'LOADING THIS VOTE…')],
    VoterEligibilityChecking() => const [
      ProgressPanel(title: 'CHECKING YOUR ACCESS…'),
    ],
    VoterJoinInProgress() => const [
      ProgressPanel(
        title: 'JOINING…',
        detail: 'Adding you to this vote. This can take a few seconds.',
      ),
    ],
    VoterProvingInProgress() => const [
      ProgressPanel(
        title: 'PREPARING YOUR PRIVATE VOTE…',
        detail:
            'This usually takes about 10 seconds — keep the app open. '
            'Your choice stays on this device until it’s protected.',
      ),
    ],
    VoterCastInProgress() => const [ProgressPanel(title: 'SENDING YOUR VOTE…')],
    VoterNotEligible() => [
      VotePanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'YOU’RE NOT PART OF THIS VOTE YET',
              style: dbSans(13, 800, Db.chalk, letterSpacing: 0.8),
            ),
            const SizedBox(height: 6),
            Text(
              'Ask to join and you’ll be added automatically. Joining sets '
              'up your voting pass on this device — nothing else to do.',
              style: dbMono(11, Db.mute, height: 1.6),
            ),
            if (widget.onOpenIdentity != null) ...[
              const SizedBox(height: 10),
              InkWell(
                onTap: widget.onOpenIdentity,
                child: Text(
                  'About your voting pass  ›',
                  style: dbLabel(size: 10, color: Db.segnale),
                ),
              ),
            ],
          ],
        ),
      ),
    ],
    VoterJoinPending() => [
      VotePanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'YOU’RE BEING ADDED',
              style: dbSans(13, 800, Db.chalk, letterSpacing: 0.8),
            ),
            const SizedBox(height: 6),
            Text(
              'Your join was accepted and is being confirmed. '
              'Check again in a moment.',
              style: dbMono(11, Db.mute, height: 1.6),
            ),
          ],
        ),
      ),
    ],
    VoterWaitingForOpen(:final view) => [
      VotePanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'YOU’RE IN',
              style: dbSans(13, 800, Db.success, letterSpacing: 0.8),
            ),
            const SizedBox(height: 6),
            Text(
              view.phase == 0
                  ? 'Voting hasn’t opened yet. Come back when it does — '
                        'use refresh to check.'
                  : 'Voting is open, but not from this device.',
              style: dbMono(11, Db.mute, height: 1.6),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _resultsArea(view),
    ],
    VoterBallotOpen(:final view) => [
      VoteSectionLabel(_ballotPrompt(view.module)),
      _ballot(view, state),
      const SizedBox(height: 8),
      _resultsArea(view),
    ],
    VoterCastSucceeded(:final refreshed) => [
      _successPanel(),
      if (!refreshed) ...[
        const SizedBox(height: 16),
        const ProgressPanel(title: 'UPDATING RESULTS…'),
      ],
    ],
    VoterReceiptSaved() => [
      _successPanel(),
      const SizedBox(height: 16),
      _receiptPanel(),
    ],
    VoterResultsSealed() => [
      if (_receipt != null) ...[
        _successPanel(),
        const SizedBox(height: 16),
        _receiptPanel(),
        const SizedBox(height: 16),
      ],
      const SealedResultsPanel(),
    ],
    VoterResultsVisible(:final view) => [
      if (_receipt != null) ...[
        _successPanel(),
        const SizedBox(height: 16),
        _receiptPanel(),
        const SizedBox(height: 16),
      ],
      _resultsCard(view),
    ],
    // Every error state names its recovery; render message + the way out.
    final JourneyErrorState error => [
      ErrorPanel(
        messageKey: error.messageKey,
        retryLabel: error.recoveryEvent is Refresh
            ? 'CHECK AGAIN'
            : 'TRY AGAIN',
        onRetry: () => _advance(error.recoveryEvent),
      ),
    ],
  };

  String _ballotPrompt(VoterModule module) => switch (module) {
    VoterModule.anon => 'PICK ONE OPTION',
    VoterModule.approval => 'APPROVE ANY YOU SUPPORT',
    VoterModule.ranked => 'PUT THEM IN YOUR ORDER',
    VoterModule.quadratic => 'SPLIT YOUR 100 POINTS',
    VoterModule.survey => 'ANSWER EVERY QUESTION',
  };

  Widget _ballot(VoterPollView view, VoterBallotOpen state) {
    void onChanged(BallotSpec? spec) {
      if (spec == null) {
        setState(() => _draftValid = false);
      } else {
        _advance(VoterBallotEdited(spec));
      }
    }

    switch (view.module) {
      case VoterModule.anon:
        return SingleChoiceBallot(
          key: const ValueKey('ballot'),
          options: view.snapshot.options,
          initial: state.draft as SingleChoice?,
          onChanged: onChanged,
        );
      case VoterModule.approval:
        return ApprovalBallot(
          key: const ValueKey('ballot'),
          options: view.snapshot.options,
          initial: state.draft as Approval?,
          onChanged: onChanged,
        );
      case VoterModule.ranked:
        return RankedBallot(
          key: const ValueKey('ballot'),
          options: view.snapshot.options,
          initial: state.draft as Ranked?,
          onChanged: onChanged,
        );
      case VoterModule.quadratic:
        return QuadraticBallot(
          key: const ValueKey('ballot'),
          options: view.snapshot.options,
          initial: state.draft as Quadratic?,
          onChanged: onChanged,
        );
      case VoterModule.survey:
        _surveyDetails ??= widget.loadSurveyDetails?.call();
        if (_surveyDetails == null) {
          return const ProgressPanel(title: 'LOADING QUESTIONS…');
        }
        return FutureBuilder<SurveyDetails>(
          key: const ValueKey('ballot'),
          future: _surveyDetails,
          builder: (context, snap) {
            final details = snap.data;
            if (details == null) {
              return const ProgressPanel(title: 'LOADING QUESTIONS…');
            }
            return SurveyBallot(details: details, onChanged: onChanged);
          },
        );
    }
  }

  /// The results area shown NEXT TO a live ballot/waiting room. Sealed polls
  /// show the sealed panel here instead of any tally — even though the chain
  /// data is technically readable (spec §3 principle 2).
  Widget _resultsArea(VoterPollView view) {
    if (view.phase == 1 &&
        view.resultsPolicy == ResultsPolicy.sealedUntilClose) {
      return const SealedResultsPanel();
    }
    if (view.phase == 0) return const SizedBox.shrink();
    return _resultsCard(view);
  }

  Widget _resultsCard(VoterPollView view) {
    if (view.module == VoterModule.survey) {
      _surveyResults ??= widget.loadSurveyResults?.call();
      final future = _surveyResults;
      if (future == null) return const SizedBox.shrink();
      return FutureBuilder<SurveyDetails>(
        future: future,
        builder: (context, snap) {
          final details = snap.data;
          if (details == null) {
            return const ProgressPanel(title: 'LOADING RESULTS…');
          }
          return VotePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const VoteSectionLabel('RESULTS'),
                for (var q = 0; q < details.questionCount; q++) ...[
                  if (q > 0) const SizedBox(height: 20),
                  Text('QUESTION ${q + 1}', style: dbLabel(size: 9)),
                  const SizedBox(height: 10),
                  ResultsBars(
                    options: [
                      for (
                        var i = 0;
                        i < details.questions[q].options.length;
                        i++
                      )
                        (
                          label: details.questions[q].options[i],
                          count:
                              q < details.results.length &&
                                  i < details.results[q].length
                              ? details.results[q][i]
                              : BigInt.zero,
                        ),
                    ],
                    // A response DISTRIBUTION, never a winner.
                    highlightLeader: false,
                  ),
                ],
              ],
            ),
          );
        },
      );
    }
    final snapshot = view.snapshot;
    return VotePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const VoteSectionLabel('RESULTS'),
              const Spacer(),
              Text(
                '${snapshot.totalVotes} VOTES',
                style: dbLabel(size: 9, tracking: 0.1),
              ),
            ],
          ),
          ResultsBars(
            options: [
              for (var i = 0; i < snapshot.options.length; i++)
                (
                  label: snapshot.options[i],
                  count: i < snapshot.results.length
                      ? snapshot.results[i]
                      : BigInt.zero,
                ),
            ],
            // Ranked bars are first preferences only — the leader is NOT the
            // outcome, so no crown.
            highlightLeader: view.module != VoterModule.ranked,
          ),
        ],
      ),
    );
  }

  Widget _successPanel() => VotePanel(
    key: PollJourneyScreen.successKey,
    child: Row(
      children: [
        const Icon(Icons.check_circle_outline, size: 20, color: Db.success),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'YOUR VOTE IS IN',
            style: dbSans(14, 800, Db.success, letterSpacing: 1),
          ),
        ),
      ],
    ),
  );

  Widget _receiptPanel() {
    final receipt = _receipt;
    if (receipt == null) return const SizedBox.shrink();
    final onVerify = widget.onVerifyReceipt;
    return ReceiptPanel(
      code: receipt.nullifier,
      onVerify: onVerify == null ? null : () => onVerify(receipt.nullifier),
    );
  }
}
