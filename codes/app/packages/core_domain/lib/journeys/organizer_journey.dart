/// Organizer journey — R2e (Revolution spec §4.1–4.2 ORGANIZE space, §5
/// privacy defaults).
///
/// ```
/// draft → deployInProgress → created (distribute: QR/link/code/NFC)
///       → registrationOpen (roster via Refresh) → votingOpen (turnout ONLY)
///       → closed → published (results)
/// ```
///
/// Design decisions this machine enforces (vs. the legacy
/// `create_screen.dart` / `blind_poll_screen.dart` flows):
///
/// - **Created ≠ live.** The legacy flow ended at "poll created" and the
///   organizer assumed voters could already find it — they could not (and by
///   design now never can: new polls are **unlisted**, spec §5). The
///   [OrganizerCreated] state's one next action is DISTRIBUTE, and advancing
///   is the explicit [OrganizerOpenRegistration] "announce" step.
/// - **Creation needs a signer path, honestly surfaced.** Sponsored relayer
///   creation is the preferred path; dev-signer/wallet only when actually
///   usable ([Capabilities]). With no path the draft's action is disabled
///   with `reason.organizer.noSignerPath` — never a cryptic
///   "set DEV_PRIVATE_KEY" string.
/// - **Privacy defaults come from policy.dart.** An untouched draft is
///   `PollVisibility.unlisted` + `ResultsPolicy.sealedUntilClose`. Under the
///   sealed policy even the organizer sees **turnout, not tallies**, until
///   close ([OrganizerDeployedState.tallyVisible]) — by design there is no
///   organizer override mid-poll (the spec cannot be edited after deploy).
/// - **Blind owner actions are ordered transitions.** startVoting /
///   endVoting / (reveal window) / finalize are explicit events with guards;
///   out-of-order requests throw [JourneyViolation].
/// - **Small groups warn.** votingOpen/closed expose
///   `smallGroupWarning` when the roster is below [MinRosterPolicy.threshold]
///   (spec §5: "under N voters, results can identify people").
///
/// Effects go through the abstract [OrganizerJourneyPort]; this file has no
/// chain/relayer imports (core_domain stays pure Dart).
library;

import 'dart:async' show unawaited;

import 'capabilities.dart';
import 'journey.dart';
import 'policy.dart';

// ---------------------------------------------------------------------------
// Poll spec (the draft form data)
// ---------------------------------------------------------------------------

/// The module types an organizer can deploy. [wireName] is the canonical
/// module-type string used on the wire (registry / sponsored create).
enum OrganizerModule {
  anonVote('anon-vote'),
  approvalVote('approval-vote'),
  rankedVote('ranked-vote'),
  quadraticVote('quadratic-vote'),
  surveyVote('survey-vote'),

  /// Commit–reveal ("sealed-until-reveal") module: needs a reveal window at
  /// creation and the owner-side finalize step after the window elapses.
  blindVote('blind-vote');

  final String wireName;

  const OrganizerModule(this.wireName);

  /// Survey builds per-question option lists, not the flat options list.
  bool get usesQuestions => this == surveyVote;

  /// Ranked + quadratic pack per-option nibbles into a 32-bit word on-chain
  /// (`MAX_OPTIONS == 8`); the draft must not exceed it or initialize
  /// reverts with `TooManyOptions`.
  bool get capsOptionsAtEight => this == rankedVote || this == quadraticVote;
}

/// One survey question in a [OrganizerModule.surveyVote] draft.
final class SurveyQuestionSpec {
  final String prompt;
  final List<String> options;

  const SurveyQuestionSpec({required this.prompt, required this.options});
}

/// The complete creation-time poll specification, including the spec §5
/// privacy choices. Defaults are the product contract from policy.dart:
/// **unlisted** + **sealedUntilClose** — an untouched draft is private.
final class OrganizerPollSpec {
  final OrganizerModule module;
  final String title;
  final String description;

  /// Answer options for every module except survey (which uses [questions]).
  final List<String> options;

  /// Survey questions (only read when [module] is [OrganizerModule.surveyVote]).
  final List<SurveyQuestionSpec> questions;

  /// Spec §5: discoverable only by link/QR/code unless explicitly listed.
  final PollVisibility visibility;

  /// Spec §5: no tally while voting is open unless explicitly live-public.
  final ResultsPolicy resultsPolicy;

  /// Reveal window for the blind module (required there, ignored elsewhere).
  final Duration? revealWindow;

  const OrganizerPollSpec({
    this.module = OrganizerModule.anonVote,
    this.title = '',
    this.description = '',
    this.options = const [],
    this.questions = const [],
    this.visibility = PollVisibility.defaultVisibility,
    this.resultsPolicy = ResultsPolicy.defaultPolicy,
    this.revealWindow,
  });

  /// Whether the draft can be deployed. Mirrors the legacy form gates:
  /// non-empty title; ≥2 non-empty options (≤8 for ranked/quadratic);
  /// survey needs ≥1 question each with ≥2 non-empty options; blind needs a
  /// reveal window.
  bool get isComplete {
    if (title.trim().isEmpty) return false;
    if (module == OrganizerModule.blindVote && revealWindow == null) {
      return false;
    }
    if (module.usesQuestions) {
      if (questions.isEmpty) return false;
      for (final question in questions) {
        if (question.prompt.trim().isEmpty) return false;
        if (question.options.length < 2 ||
            question.options.any((o) => o.trim().isEmpty)) {
          return false;
        }
      }
      return true;
    }
    if (options.length < 2) return false;
    if (options.any((o) => o.trim().isEmpty)) return false;
    if (module.capsOptionsAtEight && options.length > 8) return false;
    return true;
  }

  OrganizerPollSpec copyWith({
    OrganizerModule? module,
    String? title,
    String? description,
    List<String>? options,
    List<SurveyQuestionSpec>? questions,
    PollVisibility? visibility,
    ResultsPolicy? resultsPolicy,
    Duration? revealWindow,
  }) {
    return OrganizerPollSpec(
      module: module ?? this.module,
      title: title ?? this.title,
      description: description ?? this.description,
      options: options ?? this.options,
      questions: questions ?? this.questions,
      visibility: visibility ?? this.visibility,
      resultsPolicy: resultsPolicy ?? this.resultsPolicy,
      revealWindow: revealWindow ?? this.revealWindow,
    );
  }
}

// ---------------------------------------------------------------------------
// Policies & value objects owned by this journey
// ---------------------------------------------------------------------------

/// Threshold for the spec §5 small-group deanonymization warning: below
/// [threshold] registered voters, results can identify people. Injected into
/// [OrganizerJourneyMachine]; the default is the product default.
final class MinRosterPolicy {
  final int threshold;

  const MinRosterPolicy({this.threshold = 5});
}

/// How the created poll can be handed to voters. QR/link/code are always
/// available (displaying a QR needs no hardware — `canScanQr` is the *voter*
/// camera capability); NFC only when the organizer device has the hardware.
enum ShareTarget { qr, link, code, nfc }

/// The blind-module owner lifecycle actions (organizer-side transitions).
enum OrganizerPhaseAction { startVoting, endVoting, finalize }

/// Published tallies, keyed by option label (survey results use
/// `"question:option"` keys; richer shapes adapt in upper layers).
final class OrganizerResults {
  final Map<String, int> tallies;

  const OrganizerResults(this.tallies);
}

// ---------------------------------------------------------------------------
// Port (effects boundary — implemented over chain/relayer in upper layers)
// ---------------------------------------------------------------------------

/// Everything the organizer journey needs from the outside world. Pure
/// abstraction: implementations live in upper layers (core_chain/core_relay);
/// tests use fakes.
abstract interface class OrganizerJourneyPort {
  /// Deploys the poll described by [spec] — including its [PollVisibility]
  /// and [ResultsPolicy], which are part of the creation payload (spec §5) —
  /// and returns the poll address.
  Future<String> deployPoll(OrganizerPollSpec spec);

  /// Number of registered voters.
  Future<int> fetchRoster(String pollAddress);

  /// Number of cast votes (turnout — never tallies; while voting is open
  /// the sealed policy means even the organizer sees only this number).
  Future<int> fetchTurnout(String pollAddress);

  Future<void> startVoting(String pollAddress);

  Future<void> endVoting(String pollAddress);

  /// Blind module only: finalizes revealed results after the reveal window.
  Future<void> finalize(String pollAddress);

  Future<OrganizerResults> fetchResults(String pollAddress);
}

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------

/// Sealed root: switches over [OrganizerState] are exhaustive.
sealed class OrganizerState extends JourneyState {
  const OrganizerState();
}

/// The creation form. Holds the working [OrganizerPollSpec]; an untouched
/// draft already carries the privacy defaults (unlisted + sealedUntilClose).
///
/// The one next action is deploy — disabled with an honest reason when this
/// device/configuration has no way to create a poll
/// (`reason.organizer.noSignerPath`) or the form is not yet complete
/// (`reason.organizer.draftIncomplete`).
final class OrganizerDraft extends OrganizerState {
  final OrganizerPollSpec spec;

  /// Whether any create path exists: sponsored relayer (preferred), dev
  /// signer, or a usable wallet — see [OrganizerJourneyMachine.hasSignerPath].
  final bool signerPathAvailable;

  const OrganizerDraft({required this.spec, required this.signerPathAvailable});

  @override
  String get id => 'organizer.draft';

  @override
  NextAction? get nextAction => NextAction(
    labelKey: 'action.organizer.deployPoll',
    type: NextActionType.submit,
    disabledReasonKey: !signerPathAvailable
        ? 'reason.organizer.noSignerPath'
        : (spec.isComplete ? null : 'reason.organizer.draftIncomplete'),
  );
}

/// Deploying the poll via [OrganizerJourneyPort.deployPoll].
final class OrganizerDeployInProgress extends OrganizerState
    with EffectInProgress {
  final OrganizerPollSpec spec;
  final bool signerPathAvailable;

  @override
  final CancellationToken cancellation;

  OrganizerDeployInProgress({
    required this.spec,
    required this.signerPathAvailable,
    required this.cancellation,
  });

  @override
  String get id => 'organizer.deployInProgress';

  @override
  NextAction? get nextAction => const NextAction(
    labelKey: 'action.organizer.deploying',
    type: NextActionType.wait,
  );
}

/// Deploy failed. Recoverable via [Retry] (re-deploys the same spec) or
/// [OrganizerDraftUpdated] (back to the form to edit first).
final class OrganizerDeployFailed extends OrganizerState
    with JourneyErrorState {
  final OrganizerPollSpec spec;
  final bool signerPathAvailable;

  @override
  final Object? cause;

  const OrganizerDeployFailed({
    required this.spec,
    required this.signerPathAvailable,
    required this.cause,
  });

  @override
  String get id => 'organizer.deployFailed';

  @override
  String get messageKey => 'error.organizer.deployFailed';

  @override
  JourneyEvent get recoveryEvent => const Retry();
}

/// Base for every state with a deployed poll. Centralizes the spec §5
/// results gate: under [ResultsPolicy.sealedUntilClose] **nobody — including
/// the organizer — sees tallies until the poll is closed**; there is no
/// mid-poll override (the spec is immutable after deploy).
sealed class OrganizerDeployedState extends OrganizerState {
  final String pollAddress;
  final OrganizerPollSpec spec;

  const OrganizerDeployedState({required this.pollAddress, required this.spec});

  /// Whether voting has ended from this state's point of view.
  bool get phaseClosed => false;

  /// Whether tallies may be shown to the organizer right now. Turnout is
  /// always visible; tallies only when live-public or after close.
  bool get tallyVisible =>
      spec.resultsPolicy == ResultsPolicy.livePublic || phaseClosed;
}

/// Poll deployed. **It starts unlisted** ([noticeKey] documents this): no
/// voter can find it until the organizer shares it — so the one next action
/// is DISTRIBUTE, and moving on is the explicit announce step
/// ([OrganizerOpenRegistration]). This turns the legacy "creator thinks the
/// poll is live, voters can't register" confusion into a guided step.
final class OrganizerCreated extends OrganizerDeployedState {
  /// Share channels available on this device (QR/link/code always; NFC only
  /// with hardware) — computed from [Capabilities] at transition time.
  final List<ShareTarget> shareTargets;

  const OrganizerCreated({
    required super.pollAddress,
    required super.spec,
    required this.shareTargets,
  });

  @override
  String get id => 'organizer.created';

  /// Copy key for the created screen's visibility notice. The unlisted key
  /// must tell the organizer: "your poll is private — only people you share
  /// it with can find it" (spec §5 default).
  String get noticeKey => spec.visibility == PollVisibility.unlisted
      ? 'notice.organizer.createdUnlisted'
      : 'notice.organizer.createdListed';

  @override
  NextAction? get nextAction => const NextAction(
    labelKey: 'action.organizer.distribute',
    type: NextActionType.submit,
  );
}

/// Registration is open and announced. Shows the live roster count
/// (refreshed via [Refresh] → [OrganizerJourneyPort.fetchRoster]); the next
/// action is starting the vote.
final class OrganizerRegistrationOpen extends OrganizerDeployedState
    with EffectInProgress {
  /// Registered voters, or `null` before the first fetch lands.
  final int? rosterCount;

  /// True while a roster fetch for this entry is in flight.
  final bool fetchPending;

  @override
  final CancellationToken cancellation;

  OrganizerRegistrationOpen({
    required super.pollAddress,
    required super.spec,
    required this.rosterCount,
    required this.fetchPending,
    required this.cancellation,
  });

  @override
  String get id => 'organizer.registrationOpen';

  @override
  NextAction? get nextAction => const NextAction(
    labelKey: 'action.organizer.startVoting',
    type: NextActionType.submit,
  );
}

/// Owner startVoting transaction in flight.
final class OrganizerStartVotingInProgress extends OrganizerDeployedState
    with EffectInProgress {
  final int? rosterCount;

  @override
  final CancellationToken cancellation;

  OrganizerStartVotingInProgress({
    required super.pollAddress,
    required super.spec,
    required this.rosterCount,
    required this.cancellation,
  });

  @override
  String get id => 'organizer.startVotingInProgress';

  @override
  NextAction? get nextAction => const NextAction(
    labelKey: 'action.organizer.startingVoting',
    type: NextActionType.wait,
  );
}

/// Voting is open. The dashboard shows **turnout only** — under the sealed
/// default [tallyVisible] is false until close, for the organizer too.
final class OrganizerVotingOpen extends OrganizerDeployedState
    with EffectInProgress {
  final int? rosterCount;

  /// Cast votes, or `null` before the first fetch lands.
  final int? turnout;

  /// Spec §5: with fewer than [MinRosterPolicy.threshold] registered voters,
  /// results can identify people. Computed when voting starts.
  final bool smallGroupWarning;

  final bool fetchPending;

  @override
  final CancellationToken cancellation;

  OrganizerVotingOpen({
    required super.pollAddress,
    required super.spec,
    required this.rosterCount,
    required this.turnout,
    required this.smallGroupWarning,
    required this.fetchPending,
    required this.cancellation,
  });

  @override
  String get id => 'organizer.votingOpen';

  @override
  NextAction? get nextAction => const NextAction(
    labelKey: 'action.organizer.endVoting',
    type: NextActionType.submit,
  );
}

/// Owner endVoting transaction in flight.
final class OrganizerEndVotingInProgress extends OrganizerDeployedState
    with EffectInProgress {
  final int? rosterCount;
  final int? turnout;
  final bool smallGroupWarning;

  @override
  final CancellationToken cancellation;

  OrganizerEndVotingInProgress({
    required super.pollAddress,
    required super.spec,
    required this.rosterCount,
    required this.turnout,
    required this.smallGroupWarning,
    required this.cancellation,
  });

  @override
  String get id => 'organizer.endVotingInProgress';

  @override
  NextAction? get nextAction => const NextAction(
    labelKey: 'action.organizer.endingVoting',
    type: NextActionType.wait,
  );
}

/// Voting has ended. Tallies are now visible ([tallyVisible] true even under
/// the sealed policy). For the blind module this is also the reveal-window
/// monitor: [Refresh] re-reads the (revealed) turnout, [Timeout] marks the
/// window elapsed, and only then is finalize enabled — finalizing early
/// would cut off voters who have not revealed yet.
final class OrganizerClosed extends OrganizerDeployedState
    with EffectInProgress {
  final int? rosterCount;
  final int? turnout;
  final bool smallGroupWarning;

  /// Blind module: whether the owner-side finalize already ran.
  final bool finalized;

  /// Blind module: whether the reveal window has elapsed ([Timeout]).
  /// Always true for non-blind modules.
  final bool revealWindowElapsed;

  final bool fetchPending;

  @override
  final CancellationToken cancellation;

  OrganizerClosed({
    required super.pollAddress,
    required super.spec,
    required this.rosterCount,
    required this.turnout,
    required this.smallGroupWarning,
    required this.finalized,
    required this.revealWindowElapsed,
    required this.fetchPending,
    required this.cancellation,
  });

  @override
  String get id => 'organizer.closed';

  @override
  bool get phaseClosed => true;

  @override
  NextAction? get nextAction {
    if (spec.module == OrganizerModule.blindVote && !finalized) {
      return NextAction(
        labelKey: 'action.organizer.finalize',
        type: NextActionType.submit,
        disabledReasonKey: revealWindowElapsed
            ? null
            : 'reason.organizer.revealWindowOpen',
      );
    }
    return const NextAction(
      labelKey: 'action.organizer.publishResults',
      type: NextActionType.submit,
    );
  }
}

/// Blind-module finalize transaction in flight.
final class OrganizerFinalizeInProgress extends OrganizerDeployedState
    with EffectInProgress {
  final int? rosterCount;
  final int? turnout;
  final bool smallGroupWarning;

  @override
  final CancellationToken cancellation;

  OrganizerFinalizeInProgress({
    required super.pollAddress,
    required super.spec,
    required this.rosterCount,
    required this.turnout,
    required this.smallGroupWarning,
    required this.cancellation,
  });

  @override
  String get id => 'organizer.finalizeInProgress';

  @override
  bool get phaseClosed => true;

  @override
  NextAction? get nextAction => const NextAction(
    labelKey: 'action.organizer.finalizing',
    type: NextActionType.wait,
  );
}

/// A phase action (start/end/finalize) failed; [Retry] re-attempts the same
/// action with full context retained.
final class OrganizerPhaseActionFailed extends OrganizerDeployedState
    with JourneyErrorState {
  final OrganizerPhaseAction action;
  final int? rosterCount;
  final int? turnout;
  final bool smallGroupWarning;

  @override
  final Object? cause;

  const OrganizerPhaseActionFailed({
    required super.pollAddress,
    required super.spec,
    required this.action,
    required this.rosterCount,
    required this.turnout,
    required this.smallGroupWarning,
    required this.cause,
  });

  @override
  String get id => 'organizer.phaseActionFailed';

  @override
  bool get phaseClosed => action == OrganizerPhaseAction.finalize;

  @override
  String get messageKey => switch (action) {
    OrganizerPhaseAction.startVoting => 'error.organizer.startVotingFailed',
    OrganizerPhaseAction.endVoting => 'error.organizer.endVotingFailed',
    OrganizerPhaseAction.finalize => 'error.organizer.finalizeFailed',
  };

  @override
  JourneyEvent get recoveryEvent => const Retry();
}

/// Fetching final results for publication.
final class OrganizerPublishInProgress extends OrganizerDeployedState
    with EffectInProgress {
  final int? turnout;
  final bool smallGroupWarning;

  @override
  final CancellationToken cancellation;

  OrganizerPublishInProgress({
    required super.pollAddress,
    required super.spec,
    required this.turnout,
    required this.smallGroupWarning,
    required this.cancellation,
  });

  @override
  String get id => 'organizer.publishInProgress';

  @override
  bool get phaseClosed => true;

  @override
  NextAction? get nextAction => const NextAction(
    labelKey: 'action.organizer.publishing',
    type: NextActionType.wait,
  );
}

/// Results fetch failed; [Retry] refetches.
final class OrganizerPublishFailed extends OrganizerDeployedState
    with JourneyErrorState {
  final int? turnout;
  final bool smallGroupWarning;

  @override
  final Object? cause;

  const OrganizerPublishFailed({
    required super.pollAddress,
    required super.spec,
    required this.turnout,
    required this.smallGroupWarning,
    required this.cause,
  });

  @override
  String get id => 'organizer.publishFailed';

  @override
  bool get phaseClosed => true;

  @override
  String get messageKey => 'error.organizer.publishFailed';

  @override
  JourneyEvent get recoveryEvent => const Retry();
}

/// Terminal: results are live. ([smallGroupWarning] is carried through so
/// the published view can keep the honesty banner.)
final class OrganizerPublished extends OrganizerDeployedState {
  final OrganizerResults results;
  final int? turnout;
  final bool smallGroupWarning;

  const OrganizerPublished({
    required super.pollAddress,
    required super.spec,
    required this.results,
    required this.turnout,
    required this.smallGroupWarning,
  });

  @override
  String get id => 'organizer.published';

  @override
  bool get phaseClosed => true;

  @override
  bool get isTerminal => true;

  @override
  NextAction? get nextAction => null;
}

// ---------------------------------------------------------------------------
// Events (user/system-facing)
// ---------------------------------------------------------------------------

/// Form edit: replaces the draft spec (also legal from a deploy failure to
/// go back and edit).
final class OrganizerDraftUpdated extends JourneyEvent {
  final OrganizerPollSpec spec;

  const OrganizerDraftUpdated(this.spec);
}

/// Deploy the draft. Guarded on a signer path and a complete spec.
final class OrganizerDeployRequested extends JourneyEvent {
  const OrganizerDeployRequested();
}

/// The explicit announce step after distributing: the organizer confirms the
/// poll has been shared and moves to monitoring registration.
final class OrganizerOpenRegistration extends JourneyEvent {
  const OrganizerOpenRegistration();
}

/// Owner action: open the voting phase.
final class OrganizerStartVotingRequested extends JourneyEvent {
  const OrganizerStartVotingRequested();
}

/// Owner action: close the voting phase.
final class OrganizerEndVotingRequested extends JourneyEvent {
  const OrganizerEndVotingRequested();
}

/// Owner action (blind module): finalize revealed results. Guarded: only
/// after the reveal window elapsed ([Timeout]) and only once.
final class OrganizerFinalizeRequested extends JourneyEvent {
  const OrganizerFinalizeRequested();
}

/// Publish: fetch and show final results. Guarded: blind polls must be
/// finalized first.
final class OrganizerPublishRequested extends JourneyEvent {
  const OrganizerPublishRequested();
}

// ---------------------------------------------------------------------------
// Events (internal effect completions)
// ---------------------------------------------------------------------------

final class _DeploySucceeded extends JourneyEvent {
  final String pollAddress;

  const _DeploySucceeded(this.pollAddress);
}

final class _DeployFailed extends JourneyEvent {
  final Object cause;

  const _DeployFailed(this.cause);
}

final class _RosterFetched extends JourneyEvent {
  final int count;

  const _RosterFetched(this.count);
}

/// Roster refresh failed: keep the last known count (the dashboard shows
/// stale data over a dead end; the organizer can Refresh again).
final class _RosterFetchFailed extends JourneyEvent {
  const _RosterFetchFailed();
}

final class _TurnoutFetched extends JourneyEvent {
  final int count;

  const _TurnoutFetched(this.count);
}

final class _TurnoutFetchFailed extends JourneyEvent {
  const _TurnoutFetchFailed();
}

final class _PhaseActionSucceeded extends JourneyEvent {
  const _PhaseActionSucceeded();
}

final class _PhaseActionFailed extends JourneyEvent {
  final Object cause;

  const _PhaseActionFailed(this.cause);
}

final class _ResultsFetched extends JourneyEvent {
  final OrganizerResults results;

  const _ResultsFetched(this.results);
}

final class _ResultsFetchFailed extends JourneyEvent {
  final Object cause;

  const _ResultsFetchFailed(this.cause);
}

// ---------------------------------------------------------------------------
// Machine
// ---------------------------------------------------------------------------

/// The organizer journey state machine. Pure orchestration: all effects go
/// through [port]; [capabilities] and [minRoster] are injected, never probed.
final class OrganizerJourneyMachine extends JourneyMachine<OrganizerState> {
  final OrganizerJourneyPort port;
  final Capabilities capabilities;
  final MinRosterPolicy minRoster;

  OrganizerJourneyMachine({
    required this.port,
    required this.capabilities,
    this.minRoster = const MinRosterPolicy(),
    OrganizerPollSpec initialSpec = const OrganizerPollSpec(),
  }) : super(
         OrganizerDraft(
           spec: initialSpec,
           signerPathAvailable: hasSignerPath(capabilities),
         ),
       );

  /// Any way to create a poll: sponsored relayer (the preferred, wallet-free
  /// path — spec §4.3), a configured dev signer, or a usable wallet flow.
  static bool hasSignerPath(Capabilities capabilities) =>
      capabilities.relayerAvailable ||
      capabilities.canSign ||
      capabilities.canUseWallet;

  bool _smallGroup(int? rosterCount) =>
      rosterCount != null && rosterCount < minRoster.threshold;

  List<ShareTarget> _shareTargets() => [
    ShareTarget.qr,
    ShareTarget.link,
    ShareTarget.code,
    if (capabilities.hasNfc) ShareTarget.nfc,
  ];

  @override
  late final List<JourneyTransition<OrganizerState>> transitions = [
    // -- draft & deploy ------------------------------------------------
    JourneyTransition(
      from: OrganizerDraft,
      on: OrganizerDraftUpdated,
      to: (state, event) => OrganizerDraft(
        spec: (event as OrganizerDraftUpdated).spec,
        signerPathAvailable: (state as OrganizerDraft).signerPathAvailable,
      ),
    ),
    JourneyTransition(
      from: OrganizerDraft,
      on: OrganizerDeployRequested,
      guard: (state, event) {
        final draft = state as OrganizerDraft;
        return draft.signerPathAvailable && draft.spec.isComplete;
      },
      to: (state, event) => OrganizerDeployInProgress(
        spec: (state as OrganizerDraft).spec,
        signerPathAvailable: true,
        cancellation: CancellationToken(),
      ),
    ),
    JourneyTransition(
      from: OrganizerDeployInProgress,
      on: _DeploySucceeded,
      to: (state, event) => OrganizerCreated(
        pollAddress: (event as _DeploySucceeded).pollAddress,
        spec: (state as OrganizerDeployInProgress).spec,
        shareTargets: _shareTargets(),
      ),
    ),
    JourneyTransition(
      from: OrganizerDeployInProgress,
      on: _DeployFailed,
      to: (state, event) {
        final deploying = state as OrganizerDeployInProgress;
        return OrganizerDeployFailed(
          spec: deploying.spec,
          signerPathAvailable: deploying.signerPathAvailable,
          cause: (event as _DeployFailed).cause,
        );
      },
    ),
    JourneyTransition(
      from: OrganizerDeployFailed,
      on: Retry,
      to: (state, event) {
        final failed = state as OrganizerDeployFailed;
        return OrganizerDeployInProgress(
          spec: failed.spec,
          signerPathAvailable: failed.signerPathAvailable,
          cancellation: CancellationToken(),
        );
      },
    ),
    JourneyTransition(
      from: OrganizerDeployFailed,
      on: OrganizerDraftUpdated,
      to: (state, event) => OrganizerDraft(
        spec: (event as OrganizerDraftUpdated).spec,
        signerPathAvailable:
            (state as OrganizerDeployFailed).signerPathAvailable,
      ),
    ),
    // -- created → distribute → registration ---------------------------
    JourneyTransition(
      from: OrganizerCreated,
      on: OrganizerOpenRegistration,
      to: (state, event) {
        final created = state as OrganizerCreated;
        return OrganizerRegistrationOpen(
          pollAddress: created.pollAddress,
          spec: created.spec,
          rosterCount: null,
          fetchPending: true,
          cancellation: CancellationToken(),
        );
      },
    ),
    // -- registrationOpen ----------------------------------------------
    JourneyTransition(
      from: OrganizerRegistrationOpen,
      on: Refresh,
      to: (state, event) {
        final open = state as OrganizerRegistrationOpen;
        return OrganizerRegistrationOpen(
          pollAddress: open.pollAddress,
          spec: open.spec,
          rosterCount: open.rosterCount,
          fetchPending: true,
          cancellation: CancellationToken(),
        );
      },
    ),
    JourneyTransition(
      from: OrganizerRegistrationOpen,
      on: _RosterFetched,
      to: (state, event) {
        final open = state as OrganizerRegistrationOpen;
        return OrganizerRegistrationOpen(
          pollAddress: open.pollAddress,
          spec: open.spec,
          rosterCount: (event as _RosterFetched).count,
          fetchPending: false,
          cancellation: CancellationToken(),
        );
      },
    ),
    JourneyTransition(
      from: OrganizerRegistrationOpen,
      on: _RosterFetchFailed,
      to: (state, event) {
        final open = state as OrganizerRegistrationOpen;
        return OrganizerRegistrationOpen(
          pollAddress: open.pollAddress,
          spec: open.spec,
          rosterCount: open.rosterCount,
          fetchPending: false,
          cancellation: CancellationToken(),
        );
      },
    ),
    JourneyTransition(
      from: OrganizerRegistrationOpen,
      on: OrganizerStartVotingRequested,
      to: (state, event) {
        final open = state as OrganizerRegistrationOpen;
        return OrganizerStartVotingInProgress(
          pollAddress: open.pollAddress,
          spec: open.spec,
          rosterCount: open.rosterCount,
          cancellation: CancellationToken(),
        );
      },
    ),
    // Phase truth is external: another owner device may have advanced the
    // poll. Guards keep only forward moves legal.
    JourneyTransition(
      from: OrganizerRegistrationOpen,
      on: ExternalPhaseChanged,
      guard: (state, event) => (event as ExternalPhaseChanged).phase == 1,
      to: (state, event) {
        final open = state as OrganizerRegistrationOpen;
        return OrganizerVotingOpen(
          pollAddress: open.pollAddress,
          spec: open.spec,
          rosterCount: open.rosterCount,
          turnout: null,
          smallGroupWarning: _smallGroup(open.rosterCount),
          fetchPending: true,
          cancellation: CancellationToken(),
        );
      },
    ),
    JourneyTransition(
      from: OrganizerRegistrationOpen,
      on: ExternalPhaseChanged,
      guard: (state, event) => (event as ExternalPhaseChanged).phase == 2,
      to: (state, event) {
        final open = state as OrganizerRegistrationOpen;
        return OrganizerClosed(
          pollAddress: open.pollAddress,
          spec: open.spec,
          rosterCount: open.rosterCount,
          turnout: null,
          smallGroupWarning: _smallGroup(open.rosterCount),
          finalized: false,
          revealWindowElapsed: open.spec.module != OrganizerModule.blindVote,
          fetchPending: true,
          cancellation: CancellationToken(),
        );
      },
    ),
    // -- startVoting effect --------------------------------------------
    JourneyTransition(
      from: OrganizerStartVotingInProgress,
      on: _PhaseActionSucceeded,
      to: (state, event) {
        final starting = state as OrganizerStartVotingInProgress;
        return OrganizerVotingOpen(
          pollAddress: starting.pollAddress,
          spec: starting.spec,
          rosterCount: starting.rosterCount,
          turnout: null,
          smallGroupWarning: _smallGroup(starting.rosterCount),
          fetchPending: true,
          cancellation: CancellationToken(),
        );
      },
    ),
    JourneyTransition(
      from: OrganizerStartVotingInProgress,
      on: _PhaseActionFailed,
      to: (state, event) {
        final starting = state as OrganizerStartVotingInProgress;
        return OrganizerPhaseActionFailed(
          pollAddress: starting.pollAddress,
          spec: starting.spec,
          action: OrganizerPhaseAction.startVoting,
          rosterCount: starting.rosterCount,
          turnout: null,
          smallGroupWarning: _smallGroup(starting.rosterCount),
          cause: (event as _PhaseActionFailed).cause,
        );
      },
    ),
    // -- votingOpen ------------------------------------------------------
    JourneyTransition(
      from: OrganizerVotingOpen,
      on: Refresh,
      to: (state, event) {
        final voting = state as OrganizerVotingOpen;
        return OrganizerVotingOpen(
          pollAddress: voting.pollAddress,
          spec: voting.spec,
          rosterCount: voting.rosterCount,
          turnout: voting.turnout,
          smallGroupWarning: voting.smallGroupWarning,
          fetchPending: true,
          cancellation: CancellationToken(),
        );
      },
    ),
    JourneyTransition(
      from: OrganizerVotingOpen,
      on: _TurnoutFetched,
      to: (state, event) {
        final voting = state as OrganizerVotingOpen;
        return OrganizerVotingOpen(
          pollAddress: voting.pollAddress,
          spec: voting.spec,
          rosterCount: voting.rosterCount,
          turnout: (event as _TurnoutFetched).count,
          smallGroupWarning: voting.smallGroupWarning,
          fetchPending: false,
          cancellation: CancellationToken(),
        );
      },
    ),
    JourneyTransition(
      from: OrganizerVotingOpen,
      on: _TurnoutFetchFailed,
      to: (state, event) {
        final voting = state as OrganizerVotingOpen;
        return OrganizerVotingOpen(
          pollAddress: voting.pollAddress,
          spec: voting.spec,
          rosterCount: voting.rosterCount,
          turnout: voting.turnout,
          smallGroupWarning: voting.smallGroupWarning,
          fetchPending: false,
          cancellation: CancellationToken(),
        );
      },
    ),
    JourneyTransition(
      from: OrganizerVotingOpen,
      on: OrganizerEndVotingRequested,
      to: (state, event) {
        final voting = state as OrganizerVotingOpen;
        return OrganizerEndVotingInProgress(
          pollAddress: voting.pollAddress,
          spec: voting.spec,
          rosterCount: voting.rosterCount,
          turnout: voting.turnout,
          smallGroupWarning: voting.smallGroupWarning,
          cancellation: CancellationToken(),
        );
      },
    ),
    JourneyTransition(
      from: OrganizerVotingOpen,
      on: ExternalPhaseChanged,
      guard: (state, event) => (event as ExternalPhaseChanged).phase == 2,
      to: (state, event) {
        final voting = state as OrganizerVotingOpen;
        return OrganizerClosed(
          pollAddress: voting.pollAddress,
          spec: voting.spec,
          rosterCount: voting.rosterCount,
          turnout: voting.turnout,
          smallGroupWarning: voting.smallGroupWarning,
          finalized: false,
          revealWindowElapsed: voting.spec.module != OrganizerModule.blindVote,
          fetchPending: true,
          cancellation: CancellationToken(),
        );
      },
    ),
    // -- endVoting effect ----------------------------------------------
    JourneyTransition(
      from: OrganizerEndVotingInProgress,
      on: _PhaseActionSucceeded,
      to: (state, event) {
        final ending = state as OrganizerEndVotingInProgress;
        return OrganizerClosed(
          pollAddress: ending.pollAddress,
          spec: ending.spec,
          rosterCount: ending.rosterCount,
          turnout: ending.turnout,
          smallGroupWarning: ending.smallGroupWarning,
          finalized: false,
          revealWindowElapsed: ending.spec.module != OrganizerModule.blindVote,
          fetchPending: false,
          cancellation: CancellationToken(),
        );
      },
    ),
    JourneyTransition(
      from: OrganizerEndVotingInProgress,
      on: _PhaseActionFailed,
      to: (state, event) {
        final ending = state as OrganizerEndVotingInProgress;
        return OrganizerPhaseActionFailed(
          pollAddress: ending.pollAddress,
          spec: ending.spec,
          action: OrganizerPhaseAction.endVoting,
          rosterCount: ending.rosterCount,
          turnout: ending.turnout,
          smallGroupWarning: ending.smallGroupWarning,
          cause: (event as _PhaseActionFailed).cause,
        );
      },
    ),
    // -- closed (reveal-window monitor for blind) -----------------------
    JourneyTransition(
      from: OrganizerClosed,
      on: Refresh,
      to: (state, event) {
        final closed = state as OrganizerClosed;
        return _closedCopy(closed, fetchPending: true);
      },
    ),
    JourneyTransition(
      from: OrganizerClosed,
      on: _TurnoutFetched,
      to: (state, event) {
        final closed = state as OrganizerClosed;
        return _closedCopy(
          closed,
          turnout: (event as _TurnoutFetched).count,
          fetchPending: false,
        );
      },
    ),
    JourneyTransition(
      from: OrganizerClosed,
      on: _TurnoutFetchFailed,
      to: (state, event) =>
          _closedCopy(state as OrganizerClosed, fetchPending: false),
    ),
    JourneyTransition(
      from: OrganizerClosed,
      on: Timeout,
      guard: (state, event) {
        final closed = state as OrganizerClosed;
        return closed.spec.module == OrganizerModule.blindVote &&
            !closed.revealWindowElapsed;
      },
      to: (state, event) =>
          _closedCopy(state as OrganizerClosed, revealWindowElapsed: true),
    ),
    JourneyTransition(
      from: OrganizerClosed,
      on: OrganizerFinalizeRequested,
      guard: (state, event) {
        final closed = state as OrganizerClosed;
        return closed.spec.module == OrganizerModule.blindVote &&
            !closed.finalized &&
            closed.revealWindowElapsed;
      },
      to: (state, event) {
        final closed = state as OrganizerClosed;
        return OrganizerFinalizeInProgress(
          pollAddress: closed.pollAddress,
          spec: closed.spec,
          rosterCount: closed.rosterCount,
          turnout: closed.turnout,
          smallGroupWarning: closed.smallGroupWarning,
          cancellation: CancellationToken(),
        );
      },
    ),
    JourneyTransition(
      from: OrganizerClosed,
      on: OrganizerPublishRequested,
      guard: (state, event) {
        final closed = state as OrganizerClosed;
        return closed.spec.module != OrganizerModule.blindVote ||
            closed.finalized;
      },
      to: (state, event) {
        final closed = state as OrganizerClosed;
        return OrganizerPublishInProgress(
          pollAddress: closed.pollAddress,
          spec: closed.spec,
          turnout: closed.turnout,
          smallGroupWarning: closed.smallGroupWarning,
          cancellation: CancellationToken(),
        );
      },
    ),
    // -- finalize effect -------------------------------------------------
    JourneyTransition(
      from: OrganizerFinalizeInProgress,
      on: _PhaseActionSucceeded,
      to: (state, event) {
        final finalizing = state as OrganizerFinalizeInProgress;
        return OrganizerClosed(
          pollAddress: finalizing.pollAddress,
          spec: finalizing.spec,
          rosterCount: finalizing.rosterCount,
          turnout: finalizing.turnout,
          smallGroupWarning: finalizing.smallGroupWarning,
          finalized: true,
          revealWindowElapsed: true,
          fetchPending: false,
          cancellation: CancellationToken(),
        );
      },
    ),
    JourneyTransition(
      from: OrganizerFinalizeInProgress,
      on: _PhaseActionFailed,
      to: (state, event) {
        final finalizing = state as OrganizerFinalizeInProgress;
        return OrganizerPhaseActionFailed(
          pollAddress: finalizing.pollAddress,
          spec: finalizing.spec,
          action: OrganizerPhaseAction.finalize,
          rosterCount: finalizing.rosterCount,
          turnout: finalizing.turnout,
          smallGroupWarning: finalizing.smallGroupWarning,
          cause: (event as _PhaseActionFailed).cause,
        );
      },
    ),
    // -- phase-action retry ----------------------------------------------
    JourneyTransition(
      from: OrganizerPhaseActionFailed,
      on: Retry,
      to: (state, event) {
        final failed = state as OrganizerPhaseActionFailed;
        return switch (failed.action) {
          OrganizerPhaseAction.startVoting => OrganizerStartVotingInProgress(
            pollAddress: failed.pollAddress,
            spec: failed.spec,
            rosterCount: failed.rosterCount,
            cancellation: CancellationToken(),
          ),
          OrganizerPhaseAction.endVoting => OrganizerEndVotingInProgress(
            pollAddress: failed.pollAddress,
            spec: failed.spec,
            rosterCount: failed.rosterCount,
            turnout: failed.turnout,
            smallGroupWarning: failed.smallGroupWarning,
            cancellation: CancellationToken(),
          ),
          OrganizerPhaseAction.finalize => OrganizerFinalizeInProgress(
            pollAddress: failed.pollAddress,
            spec: failed.spec,
            rosterCount: failed.rosterCount,
            turnout: failed.turnout,
            smallGroupWarning: failed.smallGroupWarning,
            cancellation: CancellationToken(),
          ),
        };
      },
    ),
    // -- publish -----------------------------------------------------------
    JourneyTransition(
      from: OrganizerPublishInProgress,
      on: _ResultsFetched,
      to: (state, event) {
        final publishing = state as OrganizerPublishInProgress;
        return OrganizerPublished(
          pollAddress: publishing.pollAddress,
          spec: publishing.spec,
          results: (event as _ResultsFetched).results,
          turnout: publishing.turnout,
          smallGroupWarning: publishing.smallGroupWarning,
        );
      },
    ),
    JourneyTransition(
      from: OrganizerPublishInProgress,
      on: _ResultsFetchFailed,
      to: (state, event) {
        final publishing = state as OrganizerPublishInProgress;
        return OrganizerPublishFailed(
          pollAddress: publishing.pollAddress,
          spec: publishing.spec,
          turnout: publishing.turnout,
          smallGroupWarning: publishing.smallGroupWarning,
          cause: (event as _ResultsFetchFailed).cause,
        );
      },
    ),
    JourneyTransition(
      from: OrganizerPublishFailed,
      on: Retry,
      to: (state, event) {
        final failed = state as OrganizerPublishFailed;
        return OrganizerPublishInProgress(
          pollAddress: failed.pollAddress,
          spec: failed.spec,
          turnout: failed.turnout,
          smallGroupWarning: failed.smallGroupWarning,
          cancellation: CancellationToken(),
        );
      },
    ),
  ];

  static OrganizerClosed _closedCopy(
    OrganizerClosed closed, {
    int? turnout,
    bool? finalized,
    bool? revealWindowElapsed,
    bool? fetchPending,
  }) {
    return OrganizerClosed(
      pollAddress: closed.pollAddress,
      spec: closed.spec,
      rosterCount: closed.rosterCount,
      turnout: turnout ?? closed.turnout,
      smallGroupWarning: closed.smallGroupWarning,
      finalized: finalized ?? closed.finalized,
      revealWindowElapsed: revealWindowElapsed ?? closed.revealWindowElapsed,
      fetchPending: fetchPending ?? closed.fetchPending,
      cancellation: CancellationToken(),
    );
  }

  @override
  void onEnter(OrganizerState previous, OrganizerState next) {
    switch (next) {
      case OrganizerDeployInProgress deploying:
        unawaited(_deploy(deploying));
      case OrganizerRegistrationOpen open when open.fetchPending:
        unawaited(_fetchRoster(open));
      case OrganizerVotingOpen voting when voting.fetchPending:
        unawaited(_fetchTurnout(voting.pollAddress, voting.cancellation));
      case OrganizerClosed closed when closed.fetchPending:
        unawaited(_fetchTurnout(closed.pollAddress, closed.cancellation));
      case OrganizerStartVotingInProgress starting:
        unawaited(
          _phaseAction(
            OrganizerPhaseAction.startVoting,
            starting.pollAddress,
            starting.cancellation,
          ),
        );
      case OrganizerEndVotingInProgress ending:
        unawaited(
          _phaseAction(
            OrganizerPhaseAction.endVoting,
            ending.pollAddress,
            ending.cancellation,
          ),
        );
      case OrganizerFinalizeInProgress finalizing:
        unawaited(
          _phaseAction(
            OrganizerPhaseAction.finalize,
            finalizing.pollAddress,
            finalizing.cancellation,
          ),
        );
      case OrganizerPublishInProgress publishing:
        unawaited(_fetchResults(publishing));
      default:
        break;
    }
  }

  Future<void> _deploy(OrganizerDeployInProgress deploying) async {
    try {
      final pollAddress = await port.deployPoll(deploying.spec);
      if (deploying.cancellation.isCancelled) return;
      await advance(_DeploySucceeded(pollAddress));
    } on Object catch (error) {
      if (deploying.cancellation.isCancelled) return;
      await advance(_DeployFailed(error));
    }
  }

  Future<void> _fetchRoster(OrganizerRegistrationOpen open) async {
    try {
      final count = await port.fetchRoster(open.pollAddress);
      if (open.cancellation.isCancelled) return;
      await advance(_RosterFetched(count));
    } on Object catch (_) {
      if (open.cancellation.isCancelled) return;
      await advance(const _RosterFetchFailed());
    }
  }

  Future<void> _fetchTurnout(
    String pollAddress,
    CancellationToken token,
  ) async {
    try {
      final count = await port.fetchTurnout(pollAddress);
      if (token.isCancelled) return;
      await advance(_TurnoutFetched(count));
    } on Object catch (_) {
      if (token.isCancelled) return;
      await advance(const _TurnoutFetchFailed());
    }
  }

  Future<void> _phaseAction(
    OrganizerPhaseAction action,
    String pollAddress,
    CancellationToken token,
  ) async {
    try {
      switch (action) {
        case OrganizerPhaseAction.startVoting:
          await port.startVoting(pollAddress);
        case OrganizerPhaseAction.endVoting:
          await port.endVoting(pollAddress);
        case OrganizerPhaseAction.finalize:
          await port.finalize(pollAddress);
      }
      if (token.isCancelled) return;
      await advance(const _PhaseActionSucceeded());
    } on Object catch (error) {
      if (token.isCancelled) return;
      await advance(_PhaseActionFailed(error));
    }
  }

  Future<void> _fetchResults(OrganizerPublishInProgress publishing) async {
    try {
      final results = await port.fetchResults(publishing.pollAddress);
      if (publishing.cancellation.isCancelled) return;
      await advance(_ResultsFetched(results));
    } on Object catch (error) {
      if (publishing.cancellation.isCancelled) return;
      await advance(_ResultsFetchFailed(error));
    }
  }
}
