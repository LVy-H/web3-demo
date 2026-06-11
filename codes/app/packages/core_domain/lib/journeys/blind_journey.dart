/// Blind (commit–reveal) voter journey — R2c (Revolution spec §4.2).
///
/// VOTER side only: register → voting open → commit(option) → committed →
/// poll ended → reveal window → reveal → revealed → finalized/results.
/// Owner actions (startVoting / endVoting / finalize) belong to the
/// organizer journey (R2e) and are deliberately absent here.
///
/// This machine encodes the blind-poll audit fixes as *structure*:
///
/// - **Salt backup is a gate, not a footnote.** [BlindCommitted] carries the
///   [SaltReceipt] and its [NextAction] demands acknowledging the backup
///   warning before anything else: the legacy flow stored the salt
///   device-locally and silently — losing the device meant a permanently
///   lost vote. The risk is now explicit and an export action is supported.
/// - **The reveal deadline is enforced client-side.** [BlindRevealWindow]
///   carries the deadline and exposes the remaining time; reveal transitions
///   are guard-rejected once it passes (legacy let you attempt and fail
///   on-chain). [BlindMissedReveal] is a typed terminal state that explains
///   what happened.
/// - **The unrecoverable case is represented, not hidden.** Entering the
///   reveal window without a locally available salt (detected via
///   [BlindJourneyPort.hasSalt]) lands in [BlindSaltMissing], a typed
///   dead-end with an honest copy key — not a generic error.
///
/// Effects go through the abstract [BlindJourneyPort]; core_domain never
/// imports core_chain/core_relay. Tests inject a fake port and a fake clock.
library;

import 'dart:async' show unawaited;

import 'package:core_domain/journeys/journey.dart';

// ---------------------------------------------------------------------------
// Values
// ---------------------------------------------------------------------------

/// What the on-chain blind poll says about this voter right now.
///
/// Phase uses the chain encoding shared with [ExternalPhaseChanged]:
/// 0 = Registration, 1 = Voting, 2 = Ended.
final class BlindJourneySnapshot {
  final int phase;
  final bool registered;
  final bool committed;
  final bool revealed;
  final bool finalized;

  const BlindJourneySnapshot({
    required this.phase,
    required this.registered,
    required this.committed,
    required this.revealed,
    required this.finalized,
  });

  @override
  String toString() =>
      'BlindJourneySnapshot(phase: $phase, registered: $registered, '
      'committed: $committed, revealed: $revealed, finalized: $finalized)';
}

/// Proof-of-commit handed back by [BlindJourneyPort.commit]: the option that
/// was committed and the salt that will be needed to reveal it.
///
/// The salt is the vote secret. [toString] redacts it so receipts can be
/// logged safely; the UI reads [saltHex] explicitly for the export action.
final class SaltReceipt {
  final int optionIndex;

  /// Hex-encoded salt (`0x…`). Required at reveal; without it the vote is
  /// permanently unrevealable — hence the backup gate on [BlindCommitted].
  final String saltHex;

  const SaltReceipt({required this.optionIndex, required this.saltHex});

  @override
  bool operator ==(Object other) =>
      other is SaltReceipt &&
      other.optionIndex == optionIndex &&
      other.saltHex == saltHex;

  @override
  int get hashCode => Object.hash(optionIndex, saltHex);

  @override
  String toString() => 'SaltReceipt(option: $optionIndex, salt: <redacted>)';
}

// ---------------------------------------------------------------------------
// Port (effects boundary — implemented in upper layers, faked in tests)
// ---------------------------------------------------------------------------

/// Side-effect boundary for the blind journey, bound to one poll upstream.
///
/// core_domain owns the flow; chain/relayer/storage details live behind
/// this interface (no core_chain/core_relay imports here).
abstract interface class BlindJourneyPort {
  /// Reads the poll phase and this voter's status.
  Future<BlindJourneySnapshot> fetchState();

  /// Registers this voter (legal during the Registration phase only).
  Future<void> register();

  /// Commits [optionIndex]: generates a salt, stores it device-locally, and
  /// sends the commitment hash. Returns the receipt the voter must back up.
  Future<SaltReceipt> commit(int optionIndex);

  /// Whether the salt for this poll's commit is locally available.
  Future<bool> hasSalt();

  /// Reveals the committed vote using the locally stored salt.
  Future<void> reveal();

  /// Reads the on-chain reveal deadline.
  Future<DateTime> fetchRevealDeadline();
}

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------

/// Sealed root: switches over [BlindState] are exhaustive.
sealed class BlindState extends JourneyState {
  const BlindState();
}

/// Fetching the poll snapshot (initial entry and every [Refresh]).
final class BlindLoadInProgress extends BlindState with EffectInProgress {
  @override
  final CancellationToken cancellation;

  BlindLoadInProgress(this.cancellation);

  @override
  String get id => 'blind.loading';

  @override
  NextAction? get nextAction =>
      const NextAction(labelKey: 'action.loading', type: NextActionType.wait);
}

/// Loading the poll failed.
final class BlindLoadError extends BlindState with JourneyErrorState {
  @override
  final Object? cause;

  const BlindLoadError(this.cause);

  @override
  String get id => 'blind.loadError';

  @override
  String get messageKey => 'error.blind.loadFailed';

  @override
  JourneyEvent get recoveryEvent => const Retry();
}

/// Registration phase, voter not yet registered.
final class BlindRegistrationOpen extends BlindState {
  const BlindRegistrationOpen();

  @override
  String get id => 'blind.registrationOpen';

  @override
  NextAction? get nextAction => const NextAction(
    labelKey: 'action.register',
    type: NextActionType.submit,
  );
}

/// Sending the registration.
final class BlindRegisterInProgress extends BlindState with EffectInProgress {
  @override
  final CancellationToken cancellation;

  BlindRegisterInProgress(this.cancellation);

  @override
  String get id => 'blind.registering';

  @override
  NextAction? get nextAction => const NextAction(
    labelKey: 'action.registering',
    type: NextActionType.wait,
  );
}

/// Registration failed.
final class BlindRegisterError extends BlindState with JourneyErrorState {
  @override
  final Object? cause;

  const BlindRegisterError(this.cause);

  @override
  String get id => 'blind.registerError';

  @override
  String get messageKey => 'error.blind.registerFailed';

  @override
  JourneyEvent get recoveryEvent => const Retry();
}

/// Registered; waiting for voting to open.
final class BlindRegistered extends BlindState {
  const BlindRegistered();

  @override
  String get id => 'blind.registered';

  @override
  NextAction? get nextAction => const NextAction(
    labelKey: 'action.waitingForVotingOpen',
    type: NextActionType.wait,
  );
}

/// Voting phase open; the voter picks an option and commits.
final class BlindVotingOpen extends BlindState {
  const BlindVotingOpen();

  @override
  String get id => 'blind.votingOpen';

  @override
  NextAction? get nextAction => const NextAction(
    labelKey: 'action.commitVote',
    type: NextActionType.submit,
  );
}

/// Sending the commitment for [optionIndex].
final class BlindCommitInProgress extends BlindState with EffectInProgress {
  @override
  final CancellationToken cancellation;

  final int optionIndex;

  BlindCommitInProgress(this.cancellation, {required this.optionIndex});

  @override
  String get id => 'blind.committing';

  @override
  NextAction? get nextAction => const NextAction(
    labelKey: 'action.committing',
    type: NextActionType.wait,
  );
}

/// Commit failed; retains [optionIndex] so [Retry] re-commits the same vote.
final class BlindCommitError extends BlindState with JourneyErrorState {
  @override
  final Object? cause;

  final int optionIndex;

  const BlindCommitError(this.cause, {required this.optionIndex});

  @override
  String get id => 'blind.commitError';

  @override
  String get messageKey => 'error.blind.commitFailed';

  @override
  JourneyEvent get recoveryEvent => const Retry();
}

/// Vote committed. The salt now exists ONLY on this device.
///
/// Until the voter acknowledges the backup warning (or exports the salt),
/// the one next action is backing the salt up — the audit's
/// device-local-salt-loss risk made explicit. After acknowledgment the
/// state waits for the poll to end.
///
/// [receipt] is non-null when the commit happened in this session; on a
/// resumed session the salt lives only in local storage (the port has no
/// read-back), so [receipt] is null and the gate — which fired at commit
/// time — is recorded as already acknowledged.
final class BlindCommitted extends BlindState {
  final SaltReceipt? receipt;

  /// The voter has confirmed they understand losing the salt loses the vote.
  final bool backupAcknowledged;

  /// The voter exported the salt (which also counts as acknowledgment).
  final bool saltExported;

  const BlindCommitted({
    required this.receipt,
    required this.backupAcknowledged,
    this.saltExported = false,
  });

  @override
  String get id => 'blind.committed';

  @override
  NextAction? get nextAction => backupAcknowledged
      ? const NextAction(
          labelKey: 'action.waitingForPollEnd',
          type: NextActionType.wait,
        )
      : const NextAction(
          labelKey: 'action.backUpSalt',
          type: NextActionType.submit,
        );
}

/// Poll ended; checking salt availability and fetching the reveal deadline
/// before opening the reveal window.
final class BlindRevealCheckInProgress extends BlindState
    with EffectInProgress {
  @override
  final CancellationToken cancellation;

  BlindRevealCheckInProgress(this.cancellation);

  @override
  String get id => 'blind.revealCheck';

  @override
  NextAction? get nextAction => const NextAction(
    labelKey: 'action.checkingRevealWindow',
    type: NextActionType.wait,
  );
}

/// The reveal-window check failed (deadline fetch / salt probe).
final class BlindRevealCheckError extends BlindState with JourneyErrorState {
  @override
  final Object? cause;

  const BlindRevealCheckError(this.cause);

  @override
  String get id => 'blind.revealCheckError';

  @override
  String get messageKey => 'error.blind.revealCheckFailed';

  @override
  JourneyEvent get recoveryEvent => const Retry();
}

/// The reveal window is open: salt present, deadline known and not passed.
///
/// Exposes the remaining time for the countdown; once [revealDeadline]
/// passes, the reveal transition is guard-rejected (client-side enforcement
/// — legacy let voters attempt and fail on-chain) and [nextAction] honestly
/// disables itself. The UI dispatches [Timeout] to land in
/// [BlindMissedReveal].
final class BlindRevealWindow extends BlindState {
  final DateTime revealDeadline;

  final DateTime Function() _clock;

  const BlindRevealWindow({
    required this.revealDeadline,
    required DateTime Function() clock,
  }) : _clock = clock;

  @override
  String get id => 'blind.revealWindow';

  /// Time left to reveal, clamped at zero.
  Duration get remaining {
    final left = revealDeadline.difference(_clock());
    return left.isNegative ? Duration.zero : left;
  }

  bool get isExpired => remaining == Duration.zero;

  @override
  NextAction? get nextAction => isExpired
      ? const NextAction(
          labelKey: 'action.revealVote',
          type: NextActionType.submit,
          disabledReasonKey: 'reason.revealDeadlinePassed',
        )
      : const NextAction(
          labelKey: 'action.revealVote',
          type: NextActionType.submit,
        );
}

/// Sending the reveal (carries the deadline so a failure can still be
/// deadline-checked on retry).
final class BlindRevealInProgress extends BlindState with EffectInProgress {
  @override
  final CancellationToken cancellation;

  final DateTime revealDeadline;

  BlindRevealInProgress(this.cancellation, {required this.revealDeadline});

  @override
  String get id => 'blind.revealing';

  @override
  NextAction? get nextAction =>
      const NextAction(labelKey: 'action.revealing', type: NextActionType.wait);
}

/// Reveal failed. [Retry] is guard-checked against [revealDeadline]; if the
/// window closed while erroring, [Timeout] leads to [BlindMissedReveal].
final class BlindRevealError extends BlindState with JourneyErrorState {
  @override
  final Object? cause;

  final DateTime revealDeadline;

  const BlindRevealError(this.cause, {required this.revealDeadline});

  @override
  String get id => 'blind.revealError';

  @override
  String get messageKey => 'error.blind.revealFailed';

  @override
  JourneyEvent get recoveryEvent => const Retry();
}

/// Vote revealed; waiting for the organizer to finalize results.
final class BlindRevealed extends BlindState {
  const BlindRevealed();

  @override
  String get id => 'blind.revealed';

  @override
  NextAction? get nextAction => const NextAction(
    labelKey: 'action.waitingForResults',
    type: NextActionType.wait,
  );
}

/// Results finalized — the journey's receipt state.
final class BlindResults extends BlindState {
  const BlindResults();

  @override
  String get id => 'blind.results';

  @override
  bool get isTerminal => true;

  @override
  NextAction? get nextAction => null;
}

/// The reveal deadline passed without a reveal. Terminal, with honest copy:
/// the committed vote can no longer be counted.
final class BlindMissedReveal extends BlindState {
  const BlindMissedReveal();

  @override
  String get id => 'blind.missedReveal';

  /// Honest explanation copy (jargon-free text lives in the app layer).
  String get copyKey => 'copy.blind.missedReveal';

  @override
  bool get isTerminal => true;

  @override
  NextAction? get nextAction => null;
}

/// The reveal window opened but no salt is locally available: the vote is
/// permanently unrevealable. A typed dead-end with honest copy — the
/// unrecoverable case is represented, not hidden behind a generic error.
final class BlindSaltMissing extends BlindState {
  const BlindSaltMissing();

  @override
  String get id => 'blind.saltMissing';

  /// Honest explanation copy: the salt was only on the committing device.
  String get copyKey => 'copy.blind.saltMissing';

  @override
  bool get isTerminal => true;

  @override
  NextAction? get nextAction => null;
}

/// The voter can no longer take part (registration closed before they
/// registered, or voting ended before they committed). Terminal, honest.
final class BlindCannotParticipate extends BlindState {
  /// Why participation is no longer possible
  /// (`copy.blind.registrationClosed` or `copy.blind.endedWithoutCommit`).
  final String copyKey;

  const BlindCannotParticipate({required this.copyKey});

  @override
  String get id => 'blind.cannotParticipate';

  @override
  bool get isTerminal => true;

  @override
  NextAction? get nextAction => null;
}

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

/// Snapshot fetch completed (effect-internal).
final class BlindStateLoaded extends JourneyEvent {
  final BlindJourneySnapshot snapshot;

  const BlindStateLoaded(this.snapshot);
}

/// Snapshot fetch failed (effect-internal).
final class BlindLoadFailed extends JourneyEvent {
  final Object cause;

  const BlindLoadFailed(this.cause);
}

/// The voter taps register.
final class BlindRegisterRequested extends JourneyEvent {
  const BlindRegisterRequested();
}

/// Registration landed (effect-internal).
final class BlindRegisterSucceeded extends JourneyEvent {
  const BlindRegisterSucceeded();
}

/// Registration failed (effect-internal).
final class BlindRegisterFailed extends JourneyEvent {
  final Object cause;

  const BlindRegisterFailed(this.cause);
}

/// The voter commits to option [optionIndex].
final class BlindCommitRequested extends JourneyEvent {
  final int optionIndex;

  const BlindCommitRequested(this.optionIndex);

  @override
  String toString() => 'BlindCommitRequested($optionIndex)';
}

/// Commit landed; carries the salt receipt to back up (effect-internal).
final class BlindCommitSucceeded extends JourneyEvent {
  final SaltReceipt receipt;

  const BlindCommitSucceeded(this.receipt);
}

/// Commit failed (effect-internal).
final class BlindCommitFailed extends JourneyEvent {
  final Object cause;

  const BlindCommitFailed(this.cause);
}

/// The voter confirms they understand the salt-loss risk.
final class BlindSaltBackupAcknowledged extends JourneyEvent {
  const BlindSaltBackupAcknowledged();
}

/// The voter exports the salt (share/save); implies acknowledgment.
/// Only legal while the in-session [SaltReceipt] is present.
final class BlindExportSaltRequested extends JourneyEvent {
  const BlindExportSaltRequested();
}

/// Reveal-window check passed: salt present, deadline known
/// (effect-internal). Whether the window is still open is decided against
/// the machine clock when this event is applied.
final class BlindRevealWindowReady extends JourneyEvent {
  final DateTime revealDeadline;

  const BlindRevealWindowReady(this.revealDeadline);
}

/// Reveal-window check found no locally available salt (effect-internal).
final class BlindSaltUnavailable extends JourneyEvent {
  const BlindSaltUnavailable();
}

/// Reveal-window check failed (effect-internal).
final class BlindRevealCheckFailed extends JourneyEvent {
  final Object cause;

  const BlindRevealCheckFailed(this.cause);
}

/// The voter taps reveal. Guard-rejected once the deadline has passed.
final class BlindRevealRequested extends JourneyEvent {
  const BlindRevealRequested();
}

/// Reveal landed (effect-internal).
final class BlindRevealSucceeded extends JourneyEvent {
  const BlindRevealSucceeded();
}

/// Reveal failed (effect-internal).
final class BlindRevealFailed extends JourneyEvent {
  final Object cause;

  const BlindRevealFailed(this.cause);
}

/// The organizer finalized results (observed externally).
final class BlindResultsFinalized extends JourneyEvent {
  const BlindResultsFinalized();
}

// ---------------------------------------------------------------------------
// Machine
// ---------------------------------------------------------------------------

/// The blind commit–reveal journey machine (voter side).
///
/// Construct with a [BlindJourneyPort] bound to one poll; the machine
/// immediately starts loading. [clock] is injectable for deterministic
/// deadline tests and defaults to [DateTime.now].
///
/// Phase truth is external: dispatch [ExternalPhaseChanged] only when the
/// chain phase actually changes (redundant phase events are violations by
/// the contract's no-silent-no-op rule).
final class BlindJourneyMachine extends JourneyMachine<BlindState> {
  final BlindJourneyPort port;

  /// Time source for deadline guards and the countdown.
  final DateTime Function() clock;

  BlindJourneyMachine({required this.port, DateTime Function()? clock})
    : clock = clock ?? DateTime.now,
      super(BlindLoadInProgress(CancellationToken())) {
    // The initial state never passes through advance()/onEnter, so its
    // effect is started here.
    unawaited(_load(state as BlindLoadInProgress));
  }

  /// Convenience countdown surface: time left to reveal while in
  /// [BlindRevealWindow], else null.
  Duration? get revealTimeRemaining => switch (state) {
    BlindRevealWindow(:final remaining) => remaining,
    _ => null,
  };

  @override
  late final List<JourneyTransition<BlindState>> transitions = [
    // -- Load / refresh ------------------------------------------------------
    JourneyTransition(
      from: BlindLoadInProgress,
      on: BlindStateLoaded,
      to: (state, event) => _route((event as BlindStateLoaded).snapshot),
    ),
    JourneyTransition(
      from: BlindLoadInProgress,
      on: BlindLoadFailed,
      to: (state, event) => BlindLoadError((event as BlindLoadFailed).cause),
    ),
    JourneyTransition(
      from: BlindLoadError,
      on: Retry,
      to: (state, event) => BlindLoadInProgress(CancellationToken()),
    ),

    // -- Register ------------------------------------------------------------
    JourneyTransition(
      from: BlindRegistrationOpen,
      on: BlindRegisterRequested,
      to: (state, event) => BlindRegisterInProgress(CancellationToken()),
    ),
    JourneyTransition(
      from: BlindRegistrationOpen,
      on: ExternalPhaseChanged,
      guard: (state, event) => (event as ExternalPhaseChanged).phase >= 1,
      to: (state, event) => const BlindCannotParticipate(
        copyKey: 'copy.blind.registrationClosed',
      ),
    ),
    JourneyTransition(
      from: BlindRegisterInProgress,
      on: BlindRegisterSucceeded,
      to: (state, event) => const BlindRegistered(),
    ),
    JourneyTransition(
      from: BlindRegisterInProgress,
      on: BlindRegisterFailed,
      to: (state, event) =>
          BlindRegisterError((event as BlindRegisterFailed).cause),
    ),
    JourneyTransition(
      from: BlindRegisterError,
      on: Retry,
      to: (state, event) => BlindRegisterInProgress(CancellationToken()),
    ),

    // -- Wait for voting to open ----------------------------------------------
    JourneyTransition(
      from: BlindRegistered,
      on: ExternalPhaseChanged,
      guard: (state, event) => (event as ExternalPhaseChanged).phase == 1,
      to: (state, event) => const BlindVotingOpen(),
    ),
    JourneyTransition(
      from: BlindRegistered,
      on: ExternalPhaseChanged,
      guard: (state, event) => (event as ExternalPhaseChanged).phase >= 2,
      to: (state, event) => const BlindCannotParticipate(
        copyKey: 'copy.blind.endedWithoutCommit',
      ),
    ),
    JourneyTransition(
      from: BlindRegistered,
      on: Refresh,
      to: (state, event) => BlindLoadInProgress(CancellationToken()),
    ),

    // -- Commit ----------------------------------------------------------------
    JourneyTransition(
      from: BlindVotingOpen,
      on: BlindCommitRequested,
      guard: (state, event) => (event as BlindCommitRequested).optionIndex >= 0,
      to: (state, event) => BlindCommitInProgress(
        CancellationToken(),
        optionIndex: (event as BlindCommitRequested).optionIndex,
      ),
    ),
    JourneyTransition(
      from: BlindVotingOpen,
      on: ExternalPhaseChanged,
      guard: (state, event) => (event as ExternalPhaseChanged).phase >= 2,
      to: (state, event) => const BlindCannotParticipate(
        copyKey: 'copy.blind.endedWithoutCommit',
      ),
    ),
    JourneyTransition(
      from: BlindVotingOpen,
      on: Refresh,
      to: (state, event) => BlindLoadInProgress(CancellationToken()),
    ),
    JourneyTransition(
      from: BlindCommitInProgress,
      on: BlindCommitSucceeded,
      to: (state, event) => BlindCommitted(
        receipt: (event as BlindCommitSucceeded).receipt,
        backupAcknowledged: false,
      ),
    ),
    JourneyTransition(
      from: BlindCommitInProgress,
      on: BlindCommitFailed,
      to: (state, event) => BlindCommitError(
        (event as BlindCommitFailed).cause,
        optionIndex: (state as BlindCommitInProgress).optionIndex,
      ),
    ),
    JourneyTransition(
      from: BlindCommitError,
      on: Retry,
      to: (state, event) => BlindCommitInProgress(
        CancellationToken(),
        optionIndex: (state as BlindCommitError).optionIndex,
      ),
    ),

    // -- Committed: the salt-backup gate ----------------------------------------
    JourneyTransition(
      from: BlindCommitted,
      on: BlindSaltBackupAcknowledged,
      to: (state, event) => BlindCommitted(
        receipt: (state as BlindCommitted).receipt,
        backupAcknowledged: true,
        saltExported: state.saltExported,
      ),
    ),
    JourneyTransition(
      from: BlindCommitted,
      on: BlindExportSaltRequested,
      // Export needs the in-session receipt; on a resumed session the salt
      // lives only in local storage and the port has no read-back.
      guard: (state, event) => (state as BlindCommitted).receipt != null,
      to: (state, event) => BlindCommitted(
        receipt: (state as BlindCommitted).receipt,
        backupAcknowledged: true,
        saltExported: true,
      ),
    ),
    JourneyTransition(
      from: BlindCommitted,
      on: ExternalPhaseChanged,
      guard: (state, event) => (event as ExternalPhaseChanged).phase >= 2,
      to: (state, event) => BlindRevealCheckInProgress(CancellationToken()),
    ),
    JourneyTransition(
      from: BlindCommitted,
      on: Refresh,
      to: (state, event) => BlindLoadInProgress(CancellationToken()),
    ),

    // -- Reveal window check -----------------------------------------------------
    JourneyTransition(
      from: BlindRevealCheckInProgress,
      on: BlindRevealWindowReady,
      to: (state, event) {
        final deadline = (event as BlindRevealWindowReady).revealDeadline;
        // Arrived after the deadline: the window never opens.
        return clock().isBefore(deadline)
            ? BlindRevealWindow(revealDeadline: deadline, clock: clock)
            : const BlindMissedReveal();
      },
    ),
    JourneyTransition(
      from: BlindRevealCheckInProgress,
      on: BlindSaltUnavailable,
      to: (state, event) => const BlindSaltMissing(),
    ),
    JourneyTransition(
      from: BlindRevealCheckInProgress,
      on: BlindRevealCheckFailed,
      to: (state, event) =>
          BlindRevealCheckError((event as BlindRevealCheckFailed).cause),
    ),
    JourneyTransition(
      from: BlindRevealCheckError,
      on: Retry,
      to: (state, event) => BlindRevealCheckInProgress(CancellationToken()),
    ),

    // -- Reveal (deadline enforced client-side) -----------------------------------
    JourneyTransition(
      from: BlindRevealWindow,
      on: BlindRevealRequested,
      guard: (state, event) => !(state as BlindRevealWindow).isExpired,
      to: (state, event) => BlindRevealInProgress(
        CancellationToken(),
        revealDeadline: (state as BlindRevealWindow).revealDeadline,
      ),
    ),
    JourneyTransition(
      from: BlindRevealWindow,
      on: Timeout,
      to: (state, event) => const BlindMissedReveal(),
    ),
    JourneyTransition(
      from: BlindRevealInProgress,
      on: BlindRevealSucceeded,
      to: (state, event) => const BlindRevealed(),
    ),
    JourneyTransition(
      from: BlindRevealInProgress,
      on: BlindRevealFailed,
      to: (state, event) => BlindRevealError(
        (event as BlindRevealFailed).cause,
        revealDeadline: (state as BlindRevealInProgress).revealDeadline,
      ),
    ),
    JourneyTransition(
      from: BlindRevealError,
      on: Retry,
      guard: (state, event) =>
          clock().isBefore((state as BlindRevealError).revealDeadline),
      to: (state, event) => BlindRevealInProgress(
        CancellationToken(),
        revealDeadline: (state as BlindRevealError).revealDeadline,
      ),
    ),
    JourneyTransition(
      from: BlindRevealError,
      on: Timeout,
      to: (state, event) => const BlindMissedReveal(),
    ),

    // -- Revealed → results --------------------------------------------------------
    JourneyTransition(
      from: BlindRevealed,
      on: BlindResultsFinalized,
      to: (state, event) => const BlindResults(),
    ),
    JourneyTransition(
      from: BlindRevealed,
      on: Refresh,
      to: (state, event) => BlindLoadInProgress(CancellationToken()),
    ),
  ];

  /// Maps a fresh snapshot to the state the voter is actually in.
  BlindState _route(BlindJourneySnapshot snapshot) {
    if (snapshot.finalized) return const BlindResults();
    if (snapshot.revealed) return const BlindRevealed();
    if (snapshot.committed) {
      if (snapshot.phase >= 2) {
        // Poll ended with an unrevealed commit: probe salt + deadline.
        return BlindRevealCheckInProgress(CancellationToken());
      }
      // Resumed session: the salt lives only in local storage (no receipt
      // to re-show); the backup gate fired at commit time.
      return const BlindCommitted(receipt: null, backupAcknowledged: true);
    }
    if (snapshot.phase >= 2) {
      return BlindCannotParticipate(
        copyKey: snapshot.registered
            ? 'copy.blind.endedWithoutCommit'
            : 'copy.blind.registrationClosed',
      );
    }
    if (snapshot.registered) {
      return snapshot.phase == 1
          ? const BlindVotingOpen()
          : const BlindRegistered();
    }
    return snapshot.phase == 0
        ? const BlindRegistrationOpen()
        : const BlindCannotParticipate(
            copyKey: 'copy.blind.registrationClosed',
          );
  }

  @override
  void onEnter(BlindState previous, BlindState next) {
    if (next is BlindLoadInProgress) {
      unawaited(_load(next));
    } else if (next is BlindRegisterInProgress) {
      unawaited(_register(next));
    } else if (next is BlindCommitInProgress) {
      unawaited(_commit(next));
    } else if (next is BlindRevealCheckInProgress) {
      unawaited(_checkRevealWindow(next));
    } else if (next is BlindRevealInProgress) {
      unawaited(_reveal(next));
    }
  }

  Future<void> _load(BlindLoadInProgress loading) async {
    try {
      final snapshot = await port.fetchState();
      if (loading.cancellation.isCancelled) return;
      await advance(BlindStateLoaded(snapshot));
    } on Object catch (error) {
      if (loading.cancellation.isCancelled) return;
      await advance(BlindLoadFailed(error));
    }
  }

  Future<void> _register(BlindRegisterInProgress registering) async {
    try {
      await port.register();
      if (registering.cancellation.isCancelled) return;
      await advance(const BlindRegisterSucceeded());
    } on Object catch (error) {
      if (registering.cancellation.isCancelled) return;
      await advance(BlindRegisterFailed(error));
    }
  }

  Future<void> _commit(BlindCommitInProgress committing) async {
    try {
      final receipt = await port.commit(committing.optionIndex);
      if (committing.cancellation.isCancelled) return;
      await advance(BlindCommitSucceeded(receipt));
    } on Object catch (error) {
      if (committing.cancellation.isCancelled) return;
      await advance(BlindCommitFailed(error));
    }
  }

  Future<void> _checkRevealWindow(BlindRevealCheckInProgress checking) async {
    try {
      final saltAvailable = await port.hasSalt();
      if (checking.cancellation.isCancelled) return;
      if (!saltAvailable) {
        await advance(const BlindSaltUnavailable());
        return;
      }
      final deadline = await port.fetchRevealDeadline();
      if (checking.cancellation.isCancelled) return;
      await advance(BlindRevealWindowReady(deadline));
    } on Object catch (error) {
      if (checking.cancellation.isCancelled) return;
      await advance(BlindRevealCheckFailed(error));
    }
  }

  Future<void> _reveal(BlindRevealInProgress revealing) async {
    try {
      await port.reveal();
      if (revealing.cancellation.isCancelled) return;
      await advance(const BlindRevealSucceeded());
    } on Object catch (error) {
      if (revealing.cancellation.isCancelled) return;
      await advance(BlindRevealFailed(error));
    }
  }
}
