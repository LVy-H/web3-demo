/// Live-meeting journeys (R2d, Revolution spec §4.2): live VOTER and live
/// HOST state machines. One file for both — they are one feature (the same
/// room, two ends of the same handshake) and the file-ownership rule allows
/// exactly one implementation file per journey PR.
///
/// Voter flow:
///   needsTicket → joining → pending → admitted → waitingForOpen
///     → ballotOpen → provingInProgress → castInProgress → done
///
/// Host flow:
///   loading → sessionOpen (rotating ticket + admit-queue submachine)
///     → votingOpen (turnout) → closed
///
/// Audit fixes this file makes UNREPRESENTABLE (vs the legacy
/// `live_vote_view_model.dart` / `live_host_view_model.dart`):
///
/// - The legacy pending loop waited FOREVER (a 3-second timer with no bound
///   and no host-liveness signal). Here [LiveVoterPending] owns its polling
///   cadence via an injected [LiveTicker], counts ticks against a
///   configurable [LiveVoterMachine.pendingTimeout] (default 3 minutes), and
///   checks [LiveVoterPort.hostAlive] every tick. Timeout or a gone host is
///   a typed [LiveVoterStalled] state with recovery actions (retry / rescan
///   / leave) — there is no representable wait-forever state.
/// - The legacy host exposed orderless phase buttons (startVoting/endVoting
///   callable from any stage). Here phase actions are explicit transitions:
///   [LiveHostStartVotingRequested] is only legal from [LiveHostSessionOpen]
///   and guard-requires at least one admitted voter; [LiveHostCloseRequested]
///   is only legal from [LiveHostVotingOpen]. Anything else throws
///   [JourneyViolation].
/// - All timers/polls live in `*InProgress`-style states carrying a
///   [CancellationToken]; the machine auto-cancels on exit/dispose, so a
///   stale tick can never write back (the historical stuck-busy-flag class).
///
/// Privacy note: the voter's ephemeral identity seed NEVER enters
/// core_domain. [LiveVoterPort.announce] mints it behind the port and only
/// the derived commitment + confirmation code cross the boundary.
library;

import 'dart:async';

import 'capabilities.dart';
import 'journey.dart';

// ---------------------------------------------------------------------------
// Ticker (injected cadence — testable, no wall clock in the machines)
// ---------------------------------------------------------------------------

/// Source of periodic ticks for polling/rotation loops.
///
/// Injected so tests drive time deterministically. Machines subscribe on
/// entering a polling state and tie the subscription to that state's
/// [CancellationToken], so leaving the state always stops the cadence.
abstract interface class LiveTicker {
  Stream<void> every(Duration interval);
}

/// Production ticker backed by [Stream.periodic].
final class SystemLiveTicker implements LiveTicker {
  const SystemLiveTicker();

  @override
  Stream<void> every(Duration interval) =>
      Stream<void>.periodic(interval, (_) {});
}

// ---------------------------------------------------------------------------
// Live VOTER — values + port
// ---------------------------------------------------------------------------

/// A parsed, structurally valid live-session ticket (opaque wire form).
final class LiveTicket {
  /// The signed ticket wire string (what the relayer verifies).
  final String wire;

  const LiveTicket(this.wire);
}

/// Result of announcing an ephemeral identity to the relayer's pending list.
///
/// The identity seed stays behind the port; only the derived commitment and
/// the face-to-face confirmation code cross into the journey.
final class LiveAnnouncement {
  final String commitment;

  /// Short code the voter shows the host (the face-to-face trust baseline).
  final String confirmationCode;

  const LiveAnnouncement({
    required this.commitment,
    required this.confirmationCode,
  });
}

/// Confirmation that the host admitted this voter on-chain.
final class LiveAdmission {
  /// Ballot options, fetched at admission time.
  final List<String> options;

  /// On-chain poll phase at admission (0 = Registration, 1 = Voting,
  /// 2 = Ended) — lets the machine route admitted → waitingForOpen or
  /// straight to the ballot without an extra external event.
  final int phase;

  const LiveAdmission({required this.options, required this.phase});
}

/// Effect boundary for the live voter journey. Implemented in upper layers
/// (relay client, chain reader, prover); core_domain only sequences it.
abstract interface class LiveVoterPort {
  /// Parses a scanned/pasted value (deep link or bare wire) into a ticket.
  /// Throws on anything structurally invalid.
  Future<LiveTicket> parseTicket(String raw);

  /// Mints a fresh EPHEMERAL identity (never persisted, never exposed),
  /// derives commitment + confirmation code, and posts to the relayer's
  /// pending list. Throws if the relayer rejects the ticket.
  Future<LiveAnnouncement> announce(LiveTicket ticket);

  /// One admission check: non-null once the host confirmed [announcement]
  /// on-chain, null while still waiting.
  Future<LiveAdmission?> pollAdmission(LiveAnnouncement announcement);

  /// Host-liveness signal. `false` means the host is definitively gone
  /// (e.g. its heartbeat expired); transient probe errors should throw
  /// instead — the machine treats throws as "keep waiting".
  Future<bool> hostAlive();

  /// Generates the anonymous membership proof for [option].
  Future<Object> generateProof(LiveAnnouncement announcement, int option);

  /// Relays the ballot; returns the transaction hash.
  Future<String> relayBallot(int option, Object proof);
}

// ---------------------------------------------------------------------------
// Live VOTER — states
// ---------------------------------------------------------------------------

/// Why the voter journey stalled while waiting in the room.
enum LiveVoterStallReason {
  /// [LiveVoterMachine.pendingTimeout] elapsed without admission.
  pendingTimeout,

  /// The host-liveness signal reported the host gone.
  hostGone,

  /// The poll ended before this voter could cast.
  pollEnded,
}

/// Sealed root: switches over the live voter journey are exhaustive.
sealed class LiveVoterState extends JourneyState {
  const LiveVoterState();
}

/// Waiting for a ticket (scan or paste, per device capabilities).
final class LiveVoterNeedsTicket extends LiveVoterState {
  final Capabilities capabilities;

  const LiveVoterNeedsTicket(this.capabilities);

  @override
  String get id => 'liveVoter.needsTicket';

  @override
  NextAction? get nextAction => capabilities.canScanQr
      ? const NextAction(
          labelKey: 'action.scanTicket',
          type: NextActionType.submit,
        )
      : const NextAction(
          labelKey: 'action.pasteTicket',
          type: NextActionType.submit,
        );
}

/// Parsing the ticket, minting the ephemeral identity and announcing to the
/// relayer (all behind [LiveVoterPort]).
final class LiveVoterJoiningInProgress extends LiveVoterState
    with EffectInProgress {
  final String rawTicket;

  @override
  final CancellationToken cancellation;

  LiveVoterJoiningInProgress({
    required this.rawTicket,
    required this.cancellation,
  });

  @override
  String get id => 'liveVoter.joining';

  @override
  NextAction? get nextAction =>
      const NextAction(labelKey: 'action.joining', type: NextActionType.wait);
}

/// Announced; showing the confirmation code and waiting for the host.
///
/// A resident effect state: the machine polls admission + host liveness on
/// the injected ticker and counts ticks against the pending timeout. Exiting
/// this state cancels the cadence via [cancellation] — the legacy unbounded
/// wait loop is unrepresentable.
final class LiveVoterPending extends LiveVoterState with EffectInProgress {
  final String rawTicket;
  final LiveAnnouncement announcement;

  @override
  final CancellationToken cancellation;

  LiveVoterPending({
    required this.rawTicket,
    required this.announcement,
    required this.cancellation,
  });

  /// The code the voter shows the host.
  String get confirmationCode => announcement.confirmationCode;

  @override
  String get id => 'liveVoter.pending';

  @override
  NextAction? get nextAction => const NextAction(
    labelKey: 'action.waitingForHost',
    type: NextActionType.wait,
  );
}

/// The bounded wait gave out (timeout / host gone) or the poll ended.
/// Always offers a way out: retry (re-announce), rescan, or leave.
final class LiveVoterStalled extends LiveVoterState with JourneyErrorState {
  final String rawTicket;
  final LiveVoterStallReason reason;

  @override
  final Object? cause;

  const LiveVoterStalled({
    required this.rawTicket,
    required this.reason,
    this.cause,
  });

  @override
  String get id => 'liveVoter.stalled';

  @override
  String get messageKey => switch (reason) {
    LiveVoterStallReason.pendingTimeout => 'error.liveVoter.pendingTimeout',
    LiveVoterStallReason.hostGone => 'error.liveVoter.hostGone',
    LiveVoterStallReason.pollEnded => 'error.liveVoter.pollEnded',
  };

  @override
  JourneyEvent get recoveryEvent => switch (reason) {
    LiveVoterStallReason.pollEnded => const LiveLeaveRequested(),
    _ => const Retry(),
  };

  @override
  NextAction? get nextAction => switch (reason) {
    // An ended poll cannot be retried into; the only honest action is out.
    LiveVoterStallReason.pollEnded => const NextAction(
      labelKey: 'action.leave',
      type: NextActionType.navigate,
    ),
    _ => const NextAction(labelKey: 'action.retry', type: NextActionType.retry),
  };
}

/// Joining failed (bad ticket, relayer rejection). Retry re-announces with
/// the same raw ticket; rescanning is also legal.
final class LiveVoterJoinFailed extends LiveVoterState with JourneyErrorState {
  final String rawTicket;

  @override
  final Object? cause;

  const LiveVoterJoinFailed({required this.rawTicket, this.cause});

  @override
  String get id => 'liveVoter.joinFailed';

  @override
  String get messageKey => 'error.liveVoter.joinFailed';

  @override
  JourneyEvent get recoveryEvent => const Retry();
}

/// Confirmed on-chain. Transient: the machine immediately routes by the
/// admission-time phase (→ waitingForOpen, → ballotOpen, or → stalled if the
/// poll already ended).
final class LiveVoterAdmitted extends LiveVoterState {
  final String rawTicket;
  final LiveAnnouncement announcement;
  final LiveAdmission admission;

  const LiveVoterAdmitted({
    required this.rawTicket,
    required this.announcement,
    required this.admission,
  });

  @override
  String get id => 'liveVoter.admitted';

  @override
  NextAction? get nextAction => const NextAction(
    labelKey: 'action.waitingForOpen',
    type: NextActionType.wait,
  );
}

/// Admitted, voting not open yet. Phase truth is external: the upper-layer
/// chain watcher dispatches [ExternalPhaseChanged] (contract convention #7).
final class LiveVoterWaitingForOpen extends LiveVoterState {
  final String rawTicket;
  final LiveAnnouncement announcement;
  final LiveAdmission admission;

  const LiveVoterWaitingForOpen({
    required this.rawTicket,
    required this.announcement,
    required this.admission,
  });

  @override
  String get id => 'liveVoter.waitingForOpen';

  @override
  NextAction? get nextAction => const NextAction(
    labelKey: 'action.waitingForOpen',
    type: NextActionType.wait,
  );
}

/// Voting is open; the ballot renders [LiveAdmission.options]. Casting is
/// guard-blocked (and the action honestly disabled) on devices that cannot
/// prove.
final class LiveVoterBallotOpen extends LiveVoterState {
  final Capabilities capabilities;
  final String rawTicket;
  final LiveAnnouncement announcement;
  final LiveAdmission admission;

  const LiveVoterBallotOpen({
    required this.capabilities,
    required this.rawTicket,
    required this.announcement,
    required this.admission,
  });

  @override
  String get id => 'liveVoter.ballotOpen';

  @override
  NextAction? get nextAction => NextAction(
    labelKey: 'action.castVote',
    type: NextActionType.submit,
    disabledReasonKey: capabilities.canProve
        ? null
        : (capabilities.reasonFor(Capability.prove) ??
              'reason.deviceCannotProve'),
  );
}

/// Generating the anonymous membership proof.
final class LiveVoterProvingInProgress extends LiveVoterState
    with EffectInProgress {
  final String rawTicket;
  final LiveAnnouncement announcement;
  final LiveAdmission admission;
  final int option;

  @override
  final CancellationToken cancellation;

  LiveVoterProvingInProgress({
    required this.rawTicket,
    required this.announcement,
    required this.admission,
    required this.option,
    required this.cancellation,
  });

  @override
  String get id => 'liveVoter.provingInProgress';

  @override
  NextAction? get nextAction =>
      const NextAction(labelKey: 'action.proving', type: NextActionType.wait);
}

/// Relaying the ballot.
final class LiveVoterCastInProgress extends LiveVoterState
    with EffectInProgress {
  final String rawTicket;
  final LiveAnnouncement announcement;
  final LiveAdmission admission;
  final int option;
  final Object proof;

  @override
  final CancellationToken cancellation;

  LiveVoterCastInProgress({
    required this.rawTicket,
    required this.announcement,
    required this.admission,
    required this.option,
    required this.proof,
    required this.cancellation,
  });

  @override
  String get id => 'liveVoter.castInProgress';

  @override
  NextAction? get nextAction =>
      const NextAction(labelKey: 'action.casting', type: NextActionType.wait);
}

/// Proving or relaying failed. Retry returns to the ballot (the admitted
/// membership is still valid; nothing was consumed).
final class LiveVoterCastFailed extends LiveVoterState with JourneyErrorState {
  final String rawTicket;
  final LiveAnnouncement announcement;
  final LiveAdmission admission;

  @override
  final Object? cause;

  const LiveVoterCastFailed({
    required this.rawTicket,
    required this.announcement,
    required this.admission,
    this.cause,
  });

  @override
  String get id => 'liveVoter.castFailed';

  @override
  String get messageKey => 'error.liveVoter.castFailed';

  @override
  JourneyEvent get recoveryEvent => const Retry();
}

/// Ballot relayed; terminal.
final class LiveVoterDone extends LiveVoterState {
  final String txHash;

  const LiveVoterDone(this.txHash);

  @override
  String get id => 'liveVoter.done';

  @override
  bool get isTerminal => true;

  @override
  NextAction? get nextAction => null;
}

/// The voter chose to leave a stalled session; terminal.
final class LiveVoterLeft extends LiveVoterState {
  const LiveVoterLeft();

  @override
  String get id => 'liveVoter.left';

  @override
  bool get isTerminal => true;

  @override
  NextAction? get nextAction => null;
}

// ---------------------------------------------------------------------------
// Live VOTER — events
// ---------------------------------------------------------------------------

/// A ticket was scanned or pasted.
final class LiveTicketProvided extends JourneyEvent {
  final String raw;

  const LiveTicketProvided(this.raw);
}

/// The announce effect succeeded.
final class LiveJoinSucceeded extends JourneyEvent {
  final LiveAnnouncement announcement;

  const LiveJoinSucceeded(this.announcement);
}

/// The host confirmed this voter on-chain.
final class LiveAdmissionConfirmed extends JourneyEvent {
  final LiveAdmission admission;

  const LiveAdmissionConfirmed(this.admission);
}

/// The host-liveness signal reported the host gone.
final class LiveHostUnreachable extends JourneyEvent {
  const LiveHostUnreachable();
}

/// The voter wants to scan/paste a different ticket.
final class LiveRescanRequested extends JourneyEvent {
  const LiveRescanRequested();
}

/// The voter abandons the session (recovery from a stalled state).
final class LiveLeaveRequested extends JourneyEvent {
  const LiveLeaveRequested();
}

/// The voter cast a choice from the open ballot.
final class LiveCastRequested extends JourneyEvent {
  final int option;

  const LiveCastRequested(this.option);
}

/// Proof generation finished.
final class LiveProofReady extends JourneyEvent {
  final Object proof;

  const LiveProofReady(this.proof);
}

/// The relayer accepted the ballot.
final class LiveCastAccepted extends JourneyEvent {
  final String txHash;

  const LiveCastAccepted(this.txHash);
}

/// A voter-side effect (join / prove / relay) failed.
final class LiveVoterEffectFailed extends JourneyEvent {
  final Object cause;

  const LiveVoterEffectFailed(this.cause);
}

// ---------------------------------------------------------------------------
// Live VOTER — machine
// ---------------------------------------------------------------------------

/// Live-meeting voter journey machine.
///
/// All effects go through [LiveVoterPort]; the pending cadence comes from
/// the injected [LiveTicker] and is bounded by [pendingTimeout].
final class LiveVoterMachine extends JourneyMachine<LiveVoterState> {
  final LiveVoterPort port;
  final LiveTicker ticker;
  final Capabilities capabilities;

  /// How often the pending state checks admission + host liveness.
  final Duration pollInterval;

  /// Upper bound on the pending wait; hitting it transitions to
  /// [LiveVoterStalled] (reason [LiveVoterStallReason.pendingTimeout]).
  final Duration pendingTimeout;

  LiveVoterMachine({
    required this.port,
    required this.ticker,
    required this.capabilities,
    this.pollInterval = const Duration(seconds: 3),
    this.pendingTimeout = const Duration(minutes: 3),
  }) : super(LiveVoterNeedsTicket(capabilities));

  @override
  late final List<JourneyTransition<LiveVoterState>> transitions = [
    // Entry: a non-empty ticket starts the join.
    JourneyTransition(
      from: LiveVoterNeedsTicket,
      on: LiveTicketProvided,
      guard: (s, e) => (e as LiveTicketProvided).raw.trim().isNotEmpty,
      to: (s, e) => LiveVoterJoiningInProgress(
        rawTicket: (e as LiveTicketProvided).raw.trim(),
        cancellation: CancellationToken(),
      ),
    ),
    JourneyTransition(
      from: LiveVoterJoiningInProgress,
      on: LiveJoinSucceeded,
      to: (s, e) => LiveVoterPending(
        rawTicket: (s as LiveVoterJoiningInProgress).rawTicket,
        announcement: (e as LiveJoinSucceeded).announcement,
        cancellation: CancellationToken(),
      ),
    ),
    JourneyTransition(
      from: LiveVoterJoiningInProgress,
      on: LiveVoterEffectFailed,
      to: (s, e) => LiveVoterJoinFailed(
        rawTicket: (s as LiveVoterJoiningInProgress).rawTicket,
        cause: (e as LiveVoterEffectFailed).cause,
      ),
    ),
    JourneyTransition(
      from: LiveVoterJoinFailed,
      on: Retry,
      to: (s, e) => LiveVoterJoiningInProgress(
        rawTicket: (s as LiveVoterJoinFailed).rawTicket,
        cancellation: CancellationToken(),
      ),
    ),
    JourneyTransition(
      from: LiveVoterJoinFailed,
      on: LiveRescanRequested,
      to: (s, e) => LiveVoterNeedsTicket(capabilities),
    ),
    // Pending: the bounded wait. Admission, timeout and host-gone are the
    // only exits besides disposal — wait-forever is unrepresentable.
    JourneyTransition(
      from: LiveVoterPending,
      on: LiveAdmissionConfirmed,
      to: (s, e) => LiveVoterAdmitted(
        rawTicket: (s as LiveVoterPending).rawTicket,
        announcement: s.announcement,
        admission: (e as LiveAdmissionConfirmed).admission,
      ),
    ),
    JourneyTransition(
      from: LiveVoterPending,
      on: Timeout,
      to: (s, e) => LiveVoterStalled(
        rawTicket: (s as LiveVoterPending).rawTicket,
        reason: LiveVoterStallReason.pendingTimeout,
      ),
    ),
    JourneyTransition(
      from: LiveVoterPending,
      on: LiveHostUnreachable,
      to: (s, e) => LiveVoterStalled(
        rawTicket: (s as LiveVoterPending).rawTicket,
        reason: LiveVoterStallReason.hostGone,
      ),
    ),
    // Stalled recovery: retry (re-announce), rescan, or leave. An ended
    // poll cannot be retried into.
    JourneyTransition(
      from: LiveVoterStalled,
      on: Retry,
      guard: (s, e) =>
          (s as LiveVoterStalled).reason != LiveVoterStallReason.pollEnded,
      to: (s, e) => LiveVoterJoiningInProgress(
        rawTicket: (s as LiveVoterStalled).rawTicket,
        cancellation: CancellationToken(),
      ),
    ),
    JourneyTransition(
      from: LiveVoterStalled,
      on: LiveRescanRequested,
      to: (s, e) => LiveVoterNeedsTicket(capabilities),
    ),
    JourneyTransition(
      from: LiveVoterStalled,
      on: LiveLeaveRequested,
      to: (s, e) => const LiveVoterLeft(),
    ),
    // Admitted: routed by phase (dispatched automatically from onEnter using
    // the admission-time phase, then kept fresh by the external watcher).
    JourneyTransition(
      from: LiveVoterAdmitted,
      on: ExternalPhaseChanged,
      guard: (s, e) => (e as ExternalPhaseChanged).phase <= 0,
      to: (s, e) => LiveVoterWaitingForOpen(
        rawTicket: (s as LiveVoterAdmitted).rawTicket,
        announcement: s.announcement,
        admission: s.admission,
      ),
    ),
    JourneyTransition(
      from: LiveVoterAdmitted,
      on: ExternalPhaseChanged,
      guard: (s, e) => (e as ExternalPhaseChanged).phase == 1,
      to: (s, e) => LiveVoterBallotOpen(
        capabilities: capabilities,
        rawTicket: (s as LiveVoterAdmitted).rawTicket,
        announcement: s.announcement,
        admission: s.admission,
      ),
    ),
    JourneyTransition(
      from: LiveVoterAdmitted,
      on: ExternalPhaseChanged,
      guard: (s, e) => (e as ExternalPhaseChanged).phase >= 2,
      to: (s, e) => LiveVoterStalled(
        rawTicket: (s as LiveVoterAdmitted).rawTicket,
        reason: LiveVoterStallReason.pollEnded,
      ),
    ),
    JourneyTransition(
      from: LiveVoterWaitingForOpen,
      on: ExternalPhaseChanged,
      guard: (s, e) => (e as ExternalPhaseChanged).phase <= 0,
      // Re-announced registration phase: benign self-transition.
      to: (s, e) => s,
    ),
    JourneyTransition(
      from: LiveVoterWaitingForOpen,
      on: ExternalPhaseChanged,
      guard: (s, e) => (e as ExternalPhaseChanged).phase == 1,
      to: (s, e) => LiveVoterBallotOpen(
        capabilities: capabilities,
        rawTicket: (s as LiveVoterWaitingForOpen).rawTicket,
        announcement: s.announcement,
        admission: s.admission,
      ),
    ),
    JourneyTransition(
      from: LiveVoterWaitingForOpen,
      on: ExternalPhaseChanged,
      guard: (s, e) => (e as ExternalPhaseChanged).phase >= 2,
      to: (s, e) => LiveVoterStalled(
        rawTicket: (s as LiveVoterWaitingForOpen).rawTicket,
        reason: LiveVoterStallReason.pollEnded,
      ),
    ),
    // Ballot: casting requires a proving device and a valid option index.
    JourneyTransition(
      from: LiveVoterBallotOpen,
      on: LiveCastRequested,
      guard: (s, e) {
        final state = s as LiveVoterBallotOpen;
        final option = (e as LiveCastRequested).option;
        return capabilities.canProve &&
            option >= 0 &&
            option < state.admission.options.length;
      },
      to: (s, e) => LiveVoterProvingInProgress(
        rawTicket: (s as LiveVoterBallotOpen).rawTicket,
        announcement: s.announcement,
        admission: s.admission,
        option: (e as LiveCastRequested).option,
        cancellation: CancellationToken(),
      ),
    ),
    JourneyTransition(
      from: LiveVoterBallotOpen,
      on: ExternalPhaseChanged,
      guard: (s, e) => (e as ExternalPhaseChanged).phase == 1,
      to: (s, e) => s,
    ),
    JourneyTransition(
      from: LiveVoterBallotOpen,
      on: ExternalPhaseChanged,
      guard: (s, e) => (e as ExternalPhaseChanged).phase >= 2,
      to: (s, e) => LiveVoterStalled(
        rawTicket: (s as LiveVoterBallotOpen).rawTicket,
        reason: LiveVoterStallReason.pollEnded,
      ),
    ),
    JourneyTransition(
      from: LiveVoterProvingInProgress,
      on: LiveProofReady,
      to: (s, e) => LiveVoterCastInProgress(
        rawTicket: (s as LiveVoterProvingInProgress).rawTicket,
        announcement: s.announcement,
        admission: s.admission,
        option: s.option,
        proof: (e as LiveProofReady).proof,
        cancellation: CancellationToken(),
      ),
    ),
    JourneyTransition(
      from: LiveVoterProvingInProgress,
      on: LiveVoterEffectFailed,
      to: (s, e) => LiveVoterCastFailed(
        rawTicket: (s as LiveVoterProvingInProgress).rawTicket,
        announcement: s.announcement,
        admission: s.admission,
        cause: (e as LiveVoterEffectFailed).cause,
      ),
    ),
    JourneyTransition(
      from: LiveVoterCastInProgress,
      on: LiveCastAccepted,
      to: (s, e) => LiveVoterDone((e as LiveCastAccepted).txHash),
    ),
    JourneyTransition(
      from: LiveVoterCastInProgress,
      on: LiveVoterEffectFailed,
      to: (s, e) => LiveVoterCastFailed(
        rawTicket: (s as LiveVoterCastInProgress).rawTicket,
        announcement: s.announcement,
        admission: s.admission,
        cause: (e as LiveVoterEffectFailed).cause,
      ),
    ),
    JourneyTransition(
      from: LiveVoterCastFailed,
      on: Retry,
      to: (s, e) => LiveVoterBallotOpen(
        capabilities: capabilities,
        rawTicket: (s as LiveVoterCastFailed).rawTicket,
        announcement: s.announcement,
        admission: s.admission,
      ),
    ),
  ];

  @override
  void onEnter(LiveVoterState previous, LiveVoterState next) {
    switch (next) {
      case LiveVoterJoiningInProgress():
        unawaited(_join(next));
      case LiveVoterPending():
        _waitForAdmission(next);
      case LiveVoterAdmitted(:final admission):
        // Route by the admission-time phase without requiring the external
        // watcher to have fired yet.
        unawaited(advance(ExternalPhaseChanged(admission.phase)));
      case LiveVoterProvingInProgress():
        unawaited(_prove(next));
      case LiveVoterCastInProgress():
        unawaited(_cast(next));
      default:
        break;
    }
  }

  Future<void> _join(LiveVoterJoiningInProgress state) async {
    try {
      final ticket = await port.parseTicket(state.rawTicket);
      if (state.cancellation.isCancelled) return;
      final announcement = await port.announce(ticket);
      if (state.cancellation.isCancelled) return;
      await advance(LiveJoinSucceeded(announcement));
    } on Object catch (error) {
      if (state.cancellation.isCancelled) return;
      await advance(LiveVoterEffectFailed(error));
    }
  }

  /// The bounded pending loop: every [pollInterval] check timeout first,
  /// then admission, then host liveness. The subscription dies with the
  /// state's token, so leaving pending always stops the cadence.
  void _waitForAdmission(LiveVoterPending state) {
    final token = state.cancellation;
    var ticks = 0;
    var busy = false;
    final sub = ticker.every(pollInterval).listen((_) async {
      if (busy || token.isCancelled) return;
      busy = true;
      try {
        ticks++;
        if (pollInterval * ticks >= pendingTimeout) {
          if (!token.isCancelled) await advance(const Timeout());
          return;
        }
        final admission = await port.pollAdmission(state.announcement);
        if (token.isCancelled) return;
        if (admission != null) {
          await advance(LiveAdmissionConfirmed(admission));
          return;
        }
        final alive = await port.hostAlive();
        if (token.isCancelled) return;
        if (!alive) await advance(const LiveHostUnreachable());
      } on Object {
        // Transient probe failure: keep waiting — the timeout still bounds
        // the overall wait, so this can never become wait-forever.
      } finally {
        busy = false;
      }
    });
    unawaited(token.whenCancelled.then((_) => sub.cancel()));
  }

  Future<void> _prove(LiveVoterProvingInProgress state) async {
    try {
      final proof = await port.generateProof(state.announcement, state.option);
      if (state.cancellation.isCancelled) return;
      await advance(LiveProofReady(proof));
    } on Object catch (error) {
      if (state.cancellation.isCancelled) return;
      await advance(LiveVoterEffectFailed(error));
    }
  }

  Future<void> _cast(LiveVoterCastInProgress state) async {
    try {
      final txHash = await port.relayBallot(state.option, state.proof);
      if (state.cancellation.isCancelled) return;
      await advance(LiveCastAccepted(txHash));
    } on Object catch (error) {
      if (state.cancellation.isCancelled) return;
      await advance(LiveVoterEffectFailed(error));
    }
  }
}

// ---------------------------------------------------------------------------
// Live HOST — values + port
// ---------------------------------------------------------------------------

/// A voter waiting in the admit queue (announced, not yet confirmed).
final class PendingLiveVoter {
  final String commitment;

  /// The face-to-face code the host matches against the voter's screen.
  final String confirmationCode;

  const PendingLiveVoter({
    required this.commitment,
    required this.confirmationCode,
  });
}

/// The admit-queue submachine's value: who is waiting, who is in, and how
/// many ballots have landed. Confirm-by-code is expressed as the
/// [LiveHostConfirmRequested] transition, guarded on membership in
/// [pending] — confirming an unknown code is a [JourneyViolation], not a
/// silent no-op.
final class AdmitQueue {
  final List<PendingLiveVoter> pending;

  /// Voters confirmed on-chain.
  final int admitted;

  /// Ballots cast so far (turnout; meaningful once voting opens).
  final int turnout;

  const AdmitQueue({
    required this.pending,
    required this.admitted,
    this.turnout = 0,
  });

  static const AdmitQueue empty = AdmitQueue(pending: [], admitted: 0);

  bool hasCode(String confirmationCode) =>
      pending.any((v) => v.confirmationCode == confirmationCode);
}

/// Effect boundary for the live host journey (org keypair, ticket minting,
/// relayer queue, chain phase transactions — all behind upper layers).
abstract interface class LiveHostPort {
  /// Ensures the per-poll org keypair / session prerequisites exist.
  Future<void> loadSession();

  /// Mints a fresh signed ticket; returns the QR payload (deep link).
  Future<String> rotateTicket();

  /// Current admit queue + turnout snapshot.
  Future<AdmitQueue> fetchQueue();

  /// Confirms the pending voter showing [confirmationCode] on-chain;
  /// returns the updated queue.
  Future<AdmitQueue> confirmVoter(String confirmationCode);

  /// Opens the voting phase on-chain.
  Future<void> startVoting();

  /// Closes the poll on-chain.
  Future<void> close();
}

// ---------------------------------------------------------------------------
// Live HOST — states
// ---------------------------------------------------------------------------

/// Which host effect failed (drives the retry rebuild).
enum LiveHostFailedAction { load, confirm, startVoting, close }

/// Sealed root: switches over the live host journey are exhaustive.
sealed class LiveHostState extends JourneyState {
  const LiveHostState();
}

/// Loading the session (org keypair, first ticket, initial queue).
final class LiveHostLoadingInProgress extends LiveHostState
    with EffectInProgress {
  @override
  final CancellationToken cancellation;

  LiveHostLoadingInProgress(this.cancellation);

  @override
  String get id => 'liveHost.loading';

  @override
  NextAction? get nextAction =>
      const NextAction(labelKey: 'action.loading', type: NextActionType.wait);
}

/// Session running: the QR ticket rotates on the injected ticker and the
/// admit queue refreshes every poll. A resident effect state — its cadence
/// dies with [cancellation] on every exit.
final class LiveHostSessionOpen extends LiveHostState with EffectInProgress {
  /// Current QR payload (rotates every [LiveHostMachine.rotateEvery]).
  final String ticket;

  final AdmitQueue queue;

  /// Poll ticks left until the next ticket rotation.
  final int ticksUntilRotate;

  @override
  final CancellationToken cancellation;

  LiveHostSessionOpen({
    required this.ticket,
    required this.queue,
    required this.ticksUntilRotate,
    required this.cancellation,
  });

  @override
  String get id => 'liveHost.sessionOpen';

  /// Start-voting is THE next action, honestly disabled until someone is
  /// admitted (and guard-enforced regardless — see the transition table).
  @override
  NextAction? get nextAction => NextAction(
    labelKey: 'action.startVoting',
    type: NextActionType.submit,
    disabledReasonKey: queue.admitted >= 1
        ? null
        : 'reason.liveHost.noAdmittedVoters',
  );
}

/// Confirming one pending voter on-chain (modal: rotation pauses, resumes
/// on return to [LiveHostSessionOpen]).
final class LiveHostConfirmingInProgress extends LiveHostState
    with EffectInProgress {
  final String ticket;
  final AdmitQueue queue;
  final int ticksUntilRotate;
  final String confirmationCode;

  @override
  final CancellationToken cancellation;

  LiveHostConfirmingInProgress({
    required this.ticket,
    required this.queue,
    required this.ticksUntilRotate,
    required this.confirmationCode,
    required this.cancellation,
  });

  @override
  String get id => 'liveHost.confirming';

  @override
  NextAction? get nextAction => const NextAction(
    labelKey: 'action.confirming',
    type: NextActionType.wait,
  );
}

/// Opening the voting phase on-chain.
final class LiveHostStartVotingInProgress extends LiveHostState
    with EffectInProgress {
  final String ticket;
  final AdmitQueue queue;
  final int ticksUntilRotate;

  @override
  final CancellationToken cancellation;

  LiveHostStartVotingInProgress({
    required this.ticket,
    required this.queue,
    required this.ticksUntilRotate,
    required this.cancellation,
  });

  @override
  String get id => 'liveHost.startingVoting';

  @override
  NextAction? get nextAction => const NextAction(
    labelKey: 'action.startingVoting',
    type: NextActionType.wait,
  );
}

/// Voting open: turnout refreshes on the ticker; the tally stays sealed
/// (results policy lives elsewhere — this state only counts ballots).
final class LiveHostVotingOpen extends LiveHostState with EffectInProgress {
  final int admitted;
  final int turnout;

  @override
  final CancellationToken cancellation;

  LiveHostVotingOpen({
    required this.admitted,
    required this.turnout,
    required this.cancellation,
  });

  @override
  String get id => 'liveHost.votingOpen';

  @override
  NextAction? get nextAction => const NextAction(
    labelKey: 'action.closeVoting',
    type: NextActionType.submit,
  );
}

/// Closing the poll on-chain.
final class LiveHostClosingInProgress extends LiveHostState
    with EffectInProgress {
  final int admitted;
  final int turnout;

  @override
  final CancellationToken cancellation;

  LiveHostClosingInProgress({
    required this.admitted,
    required this.turnout,
    required this.cancellation,
  });

  @override
  String get id => 'liveHost.closing';

  @override
  NextAction? get nextAction =>
      const NextAction(labelKey: 'action.closing', type: NextActionType.wait);
}

/// Poll closed; terminal.
final class LiveHostClosed extends LiveHostState {
  final int admitted;
  final int turnout;

  const LiveHostClosed({required this.admitted, required this.turnout});

  @override
  String get id => 'liveHost.closed';

  @override
  bool get isTerminal => true;

  @override
  NextAction? get nextAction => null;
}

/// A host effect failed. Retry rebuilds the exact in-progress state that
/// failed (the snapshot fields below carry what each rebuild needs).
final class LiveHostFailed extends LiveHostState with JourneyErrorState {
  final LiveHostFailedAction action;

  @override
  final Object? cause;

  // Snapshot for retry rebuilds; which fields are set depends on [action]
  // (enforced by the named constructors below).
  final String? ticket;
  final AdmitQueue? queue;
  final int? ticksUntilRotate;
  final String? confirmationCode;
  final int? admitted;
  final int? turnout;

  const LiveHostFailed._({
    required this.action,
    required this.cause,
    this.ticket,
    this.queue,
    this.ticksUntilRotate,
    this.confirmationCode,
    this.admitted,
    this.turnout,
  });

  const LiveHostFailed.load({required Object? cause})
    : this._(action: LiveHostFailedAction.load, cause: cause);

  const LiveHostFailed.confirm({
    required Object? cause,
    required String ticket,
    required AdmitQueue queue,
    required int ticksUntilRotate,
    required String confirmationCode,
  }) : this._(
         action: LiveHostFailedAction.confirm,
         cause: cause,
         ticket: ticket,
         queue: queue,
         ticksUntilRotate: ticksUntilRotate,
         confirmationCode: confirmationCode,
       );

  const LiveHostFailed.startVoting({
    required Object? cause,
    required String ticket,
    required AdmitQueue queue,
    required int ticksUntilRotate,
  }) : this._(
         action: LiveHostFailedAction.startVoting,
         cause: cause,
         ticket: ticket,
         queue: queue,
         ticksUntilRotate: ticksUntilRotate,
       );

  const LiveHostFailed.close({
    required Object? cause,
    required int admitted,
    required int turnout,
  }) : this._(
         action: LiveHostFailedAction.close,
         cause: cause,
         admitted: admitted,
         turnout: turnout,
       );

  @override
  String get id => 'liveHost.failed';

  @override
  String get messageKey => switch (action) {
    LiveHostFailedAction.load => 'error.liveHost.loadFailed',
    LiveHostFailedAction.confirm => 'error.liveHost.confirmFailed',
    LiveHostFailedAction.startVoting => 'error.liveHost.startVotingFailed',
    LiveHostFailedAction.close => 'error.liveHost.closeFailed',
  };

  @override
  JourneyEvent get recoveryEvent => const Retry();
}

// ---------------------------------------------------------------------------
// Live HOST — events
// ---------------------------------------------------------------------------

/// The session load effect finished (first ticket + initial queue).
final class LiveHostSessionLoaded extends JourneyEvent {
  final String ticket;
  final AdmitQueue queue;

  const LiveHostSessionLoaded({required this.ticket, required this.queue});
}

/// One ticker cycle completed: fresh queue, and a fresh ticket when the
/// rotation came due this tick.
final class LiveHostTicked extends JourneyEvent {
  /// Non-null only on rotation ticks.
  final String? ticket;

  final AdmitQueue queue;

  const LiveHostTicked({required this.queue, this.ticket});
}

/// Host confirmed a voter's code from the admit queue.
final class LiveHostConfirmRequested extends JourneyEvent {
  final String confirmationCode;

  const LiveHostConfirmRequested(this.confirmationCode);
}

/// The confirm effect succeeded; carries the updated queue.
final class LiveHostConfirmSucceeded extends JourneyEvent {
  final AdmitQueue queue;

  const LiveHostConfirmSucceeded(this.queue);
}

/// Host pressed start-voting (legal only from sessionOpen, ≥1 admitted).
final class LiveHostStartVotingRequested extends JourneyEvent {
  const LiveHostStartVotingRequested();
}

/// The start-voting transaction landed.
final class LiveHostVotingStarted extends JourneyEvent {
  const LiveHostVotingStarted();
}

/// Host pressed close (legal only from votingOpen).
final class LiveHostCloseRequested extends JourneyEvent {
  const LiveHostCloseRequested();
}

/// The close transaction landed.
final class LiveHostCloseSucceeded extends JourneyEvent {
  const LiveHostCloseSucceeded();
}

/// A host-side effect (load / confirm / start / close) failed.
final class LiveHostEffectFailed extends JourneyEvent {
  final Object cause;

  const LiveHostEffectFailed(this.cause);
}

// ---------------------------------------------------------------------------
// Live HOST — machine
// ---------------------------------------------------------------------------

/// Live-meeting host journey machine.
///
/// Phase actions are explicit transitions: start-voting only from
/// [LiveHostSessionOpen] with at least one admitted voter, close only from
/// [LiveHostVotingOpen]. The legacy scattered, orderless phase buttons are
/// impossible to express against this table.
final class LiveHostMachine extends JourneyMachine<LiveHostState> {
  final LiveHostPort port;
  final LiveTicker ticker;

  /// Queue/turnout refresh cadence.
  final Duration pollInterval;

  /// Ticket rotation cadence (rounded up to whole poll ticks).
  final Duration rotateEvery;

  LiveHostMachine({
    required this.port,
    required this.ticker,
    this.pollInterval = const Duration(seconds: 2),
    this.rotateEvery = const Duration(seconds: 25),
  }) : super(LiveHostLoadingInProgress(CancellationToken())) {
    // The initial state is not entered via a transition, so kick its load
    // effect here; re-entries (Retry) go through onEnter.
    unawaited(_load(state as LiveHostLoadingInProgress));
  }

  /// Rotation period expressed in poll ticks (at least one).
  late final int rotateTicks = pollInterval.inMicroseconds <= 0
      ? 1
      : (rotateEvery.inMicroseconds / pollInterval.inMicroseconds)
            .ceil()
            .clamp(1, 1 << 31)
            .toInt();

  @override
  late final List<JourneyTransition<LiveHostState>> transitions = [
    JourneyTransition(
      from: LiveHostLoadingInProgress,
      on: LiveHostSessionLoaded,
      to: (s, e) => LiveHostSessionOpen(
        ticket: (e as LiveHostSessionLoaded).ticket,
        queue: e.queue,
        ticksUntilRotate: rotateTicks,
        cancellation: CancellationToken(),
      ),
    ),
    JourneyTransition(
      from: LiveHostLoadingInProgress,
      on: LiveHostEffectFailed,
      to: (s, e) =>
          LiveHostFailed.load(cause: (e as LiveHostEffectFailed).cause),
    ),
    // Session heartbeat: every tick refreshes the queue and counts down the
    // rotation; a rotation tick carries the fresh ticket.
    JourneyTransition(
      from: LiveHostSessionOpen,
      on: LiveHostTicked,
      to: (s, e) {
        final state = s as LiveHostSessionOpen;
        final event = e as LiveHostTicked;
        return LiveHostSessionOpen(
          ticket: event.ticket ?? state.ticket,
          queue: event.queue,
          ticksUntilRotate: event.ticket != null
              ? rotateTicks
              : state.ticksUntilRotate - 1,
          cancellation: CancellationToken(),
        );
      },
    ),
    // Admit-queue submachine: confirm is guarded on the code actually being
    // in the pending list — confirming a ghost is a violation, not a no-op.
    JourneyTransition(
      from: LiveHostSessionOpen,
      on: LiveHostConfirmRequested,
      guard: (s, e) => (s as LiveHostSessionOpen).queue.hasCode(
        (e as LiveHostConfirmRequested).confirmationCode,
      ),
      to: (s, e) => LiveHostConfirmingInProgress(
        ticket: (s as LiveHostSessionOpen).ticket,
        queue: s.queue,
        ticksUntilRotate: s.ticksUntilRotate,
        confirmationCode: (e as LiveHostConfirmRequested).confirmationCode,
        cancellation: CancellationToken(),
      ),
    ),
    JourneyTransition(
      from: LiveHostConfirmingInProgress,
      on: LiveHostConfirmSucceeded,
      to: (s, e) => LiveHostSessionOpen(
        ticket: (s as LiveHostConfirmingInProgress).ticket,
        queue: (e as LiveHostConfirmSucceeded).queue,
        ticksUntilRotate: s.ticksUntilRotate,
        cancellation: CancellationToken(),
      ),
    ),
    JourneyTransition(
      from: LiveHostConfirmingInProgress,
      on: LiveHostEffectFailed,
      to: (s, e) => LiveHostFailed.confirm(
        cause: (e as LiveHostEffectFailed).cause,
        ticket: (s as LiveHostConfirmingInProgress).ticket,
        queue: s.queue,
        ticksUntilRotate: s.ticksUntilRotate,
        confirmationCode: s.confirmationCode,
      ),
    ),
    // Phase gate: start-voting ONLY from sessionOpen, and only with at
    // least one admitted voter (the action is also honestly disabled in
    // the UI via nextAction until then).
    JourneyTransition(
      from: LiveHostSessionOpen,
      on: LiveHostStartVotingRequested,
      guard: (s, e) => (s as LiveHostSessionOpen).queue.admitted >= 1,
      to: (s, e) => LiveHostStartVotingInProgress(
        ticket: (s as LiveHostSessionOpen).ticket,
        queue: s.queue,
        ticksUntilRotate: s.ticksUntilRotate,
        cancellation: CancellationToken(),
      ),
    ),
    JourneyTransition(
      from: LiveHostStartVotingInProgress,
      on: LiveHostVotingStarted,
      to: (s, e) => LiveHostVotingOpen(
        admitted: (s as LiveHostStartVotingInProgress).queue.admitted,
        turnout: s.queue.turnout,
        cancellation: CancellationToken(),
      ),
    ),
    JourneyTransition(
      from: LiveHostStartVotingInProgress,
      on: LiveHostEffectFailed,
      to: (s, e) => LiveHostFailed.startVoting(
        cause: (e as LiveHostEffectFailed).cause,
        ticket: (s as LiveHostStartVotingInProgress).ticket,
        queue: s.queue,
        ticksUntilRotate: s.ticksUntilRotate,
      ),
    ),
    // Turnout heartbeat while voting is open.
    JourneyTransition(
      from: LiveHostVotingOpen,
      on: LiveHostTicked,
      to: (s, e) => LiveHostVotingOpen(
        admitted: (e as LiveHostTicked).queue.admitted,
        turnout: e.queue.turnout,
        cancellation: CancellationToken(),
      ),
    ),
    // Phase gate: close ONLY from votingOpen.
    JourneyTransition(
      from: LiveHostVotingOpen,
      on: LiveHostCloseRequested,
      to: (s, e) => LiveHostClosingInProgress(
        admitted: (s as LiveHostVotingOpen).admitted,
        turnout: s.turnout,
        cancellation: CancellationToken(),
      ),
    ),
    JourneyTransition(
      from: LiveHostClosingInProgress,
      on: LiveHostCloseSucceeded,
      to: (s, e) => LiveHostClosed(
        admitted: (s as LiveHostClosingInProgress).admitted,
        turnout: s.turnout,
      ),
    ),
    JourneyTransition(
      from: LiveHostClosingInProgress,
      on: LiveHostEffectFailed,
      to: (s, e) => LiveHostFailed.close(
        cause: (e as LiveHostEffectFailed).cause,
        admitted: (s as LiveHostClosingInProgress).admitted,
        turnout: s.turnout,
      ),
    ),
    // Retry rebuilds the exact in-progress state that failed.
    JourneyTransition(
      from: LiveHostFailed,
      on: Retry,
      to: (s, e) {
        final failed = s as LiveHostFailed;
        return switch (failed.action) {
          LiveHostFailedAction.load => LiveHostLoadingInProgress(
            CancellationToken(),
          ),
          LiveHostFailedAction.confirm => LiveHostConfirmingInProgress(
            ticket: failed.ticket!,
            queue: failed.queue!,
            ticksUntilRotate: failed.ticksUntilRotate!,
            confirmationCode: failed.confirmationCode!,
            cancellation: CancellationToken(),
          ),
          LiveHostFailedAction.startVoting => LiveHostStartVotingInProgress(
            ticket: failed.ticket!,
            queue: failed.queue!,
            ticksUntilRotate: failed.ticksUntilRotate!,
            cancellation: CancellationToken(),
          ),
          LiveHostFailedAction.close => LiveHostClosingInProgress(
            admitted: failed.admitted!,
            turnout: failed.turnout!,
            cancellation: CancellationToken(),
          ),
        };
      },
    ),
  ];

  @override
  void onEnter(LiveHostState previous, LiveHostState next) {
    switch (next) {
      case LiveHostLoadingInProgress():
        unawaited(_load(next));
      case LiveHostSessionOpen():
        _watchSession(next);
      case LiveHostConfirmingInProgress():
        unawaited(_confirm(next));
      case LiveHostStartVotingInProgress():
        unawaited(_startVoting(next));
      case LiveHostVotingOpen():
        _watchTurnout(next);
      case LiveHostClosingInProgress():
        unawaited(_close(next));
      default:
        break;
    }
  }

  Future<void> _load(LiveHostLoadingInProgress state) async {
    try {
      await port.loadSession();
      if (state.cancellation.isCancelled) return;
      final ticket = await port.rotateTicket();
      if (state.cancellation.isCancelled) return;
      final queue = await port.fetchQueue();
      if (state.cancellation.isCancelled) return;
      await advance(LiveHostSessionLoaded(ticket: ticket, queue: queue));
    } on Object catch (error) {
      if (state.cancellation.isCancelled) return;
      await advance(LiveHostEffectFailed(error));
    }
  }

  /// Session heartbeat: refresh the queue each tick; mint a fresh ticket on
  /// rotation ticks. Each dispatched tick re-enters sessionOpen with a new
  /// token, so the loop is restarted per state instance and always dies on
  /// exit. Transient errors skip the tick (no dispatch, loop stays alive).
  void _watchSession(LiveHostSessionOpen state) {
    final token = state.cancellation;
    var busy = false;
    final sub = ticker.every(pollInterval).listen((_) async {
      if (busy || token.isCancelled) return;
      busy = true;
      try {
        final rotationDue = state.ticksUntilRotate <= 1;
        final ticket = rotationDue ? await port.rotateTicket() : null;
        if (token.isCancelled) return;
        final queue = await port.fetchQueue();
        if (token.isCancelled) return;
        await advance(LiveHostTicked(ticket: ticket, queue: queue));
      } on Object {
        // Transient (network blip): keep the last snapshot, try next tick.
      } finally {
        busy = false;
      }
    });
    unawaited(token.whenCancelled.then((_) => sub.cancel()));
  }

  /// Turnout heartbeat while voting is open.
  void _watchTurnout(LiveHostVotingOpen state) {
    final token = state.cancellation;
    var busy = false;
    final sub = ticker.every(pollInterval).listen((_) async {
      if (busy || token.isCancelled) return;
      busy = true;
      try {
        final queue = await port.fetchQueue();
        if (token.isCancelled) return;
        await advance(LiveHostTicked(queue: queue));
      } on Object {
        // Transient: try next tick.
      } finally {
        busy = false;
      }
    });
    unawaited(token.whenCancelled.then((_) => sub.cancel()));
  }

  Future<void> _confirm(LiveHostConfirmingInProgress state) async {
    try {
      final queue = await port.confirmVoter(state.confirmationCode);
      if (state.cancellation.isCancelled) return;
      await advance(LiveHostConfirmSucceeded(queue));
    } on Object catch (error) {
      if (state.cancellation.isCancelled) return;
      await advance(LiveHostEffectFailed(error));
    }
  }

  Future<void> _startVoting(LiveHostStartVotingInProgress state) async {
    try {
      await port.startVoting();
      if (state.cancellation.isCancelled) return;
      await advance(const LiveHostVotingStarted());
    } on Object catch (error) {
      if (state.cancellation.isCancelled) return;
      await advance(LiveHostEffectFailed(error));
    }
  }

  Future<void> _close(LiveHostClosingInProgress state) async {
    try {
      await port.close();
      if (state.cancellation.isCancelled) return;
      await advance(const LiveHostCloseSucceeded());
    } on Object catch (error) {
      if (state.cancellation.isCancelled) return;
      await advance(LiveHostEffectFailed(error));
    }
  }
}
