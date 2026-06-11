/// Voter journey (R2b) — the proof-voting state machine for the five
/// Semaphore modules: anon (pick one), approval, ranked, quadratic, survey
/// (Revolution spec §4.2).
///
/// One module-agnostic machine; the module only shows up in the typed
/// [BallotSpec] payload the voter submits. The machine encodes the audit
/// fixes structurally:
///
/// - A ballot is ONLY reachable when phase == voting AND eligibility was
///   confirmed AND the device can prove ([Capabilities.canProve]). There is
///   no transition row that produces [VoterBallotOpen] without those guards;
///   forcing entry throws [JourneyViolation].
/// - After a successful cast the machine AUTO-refreshes the poll snapshot
///   (entering [VoterCastSucceeded] always starts the refresh effect), so
///   the legacy stale-results bug is unrepresentable.
/// - All effects go through the abstract [VoterJourneyPort]; implementations
///   are injected (chain/relay adapters arrive in R2f). No imports from
///   core_chain or core_relay here.
/// - Every async effect is a `*InProgress` state with a [CancellationToken];
///   every failure is a typed [JourneyErrorState] with a recovery event.
library;

import 'dart:async' show unawaited;

import '../models/poll_snapshot.dart';
import '../models/relay_proof.dart';
import 'capabilities.dart';
import 'journey.dart';
import 'policy.dart';

// ---------------------------------------------------------------------------
// Modules and ballot payloads
// ---------------------------------------------------------------------------

/// The five proof-voting modules the voter journey covers.
enum VoterModule { anon, approval, ranked, quadratic, survey }

/// Typed ballot payload — exactly one shape per module. Sealed: switches in
/// the proving/relay adapters are exhaustive, and a payload can never be
/// submitted to a poll of another module (guarded in the transition table).
sealed class BallotSpec {
  const BallotSpec();

  /// The module this payload is valid for.
  VoterModule get module;

  /// Domain validity against the poll's option (or question) count. Chain
  /// rules are re-checked on-chain; this is the client-side mirror so an
  /// invalid ballot can never start proving.
  bool isValidFor(int optionCount);
}

/// `anon` module: a single option index (the Semaphore `message`).
final class SingleChoice extends BallotSpec {
  final int optionIndex;

  const SingleChoice(this.optionIndex);

  @override
  VoterModule get module => VoterModule.anon;

  @override
  bool isValidFor(int optionCount) =>
      optionIndex >= 0 && optionIndex < optionCount;

  @override
  bool operator ==(Object other) =>
      other is SingleChoice && other.optionIndex == optionIndex;

  @override
  int get hashCode => Object.hash(SingleChoice, optionIndex);

  @override
  String toString() => 'SingleChoice($optionIndex)';
}

/// `approval` module: bit `i` set ⇒ option `i` approved
/// (docs/architecture/module-approval.md — the bitmask is the message).
final class Approval extends BallotSpec {
  final BigInt bitmask;

  Approval(this.bitmask);

  @override
  VoterModule get module => VoterModule.approval;

  @override
  bool isValidFor(int optionCount) =>
      bitmask > BigInt.zero && bitmask < (BigInt.one << optionCount);

  @override
  bool operator ==(Object other) =>
      other is Approval && other.bitmask == bitmask;

  @override
  int get hashCode => Object.hash(Approval, bitmask);

  @override
  String toString() => 'Approval(0x${bitmask.toRadixString(16)})';
}

/// `ranked` module: a preference-ordered prefix of distinct option indices
/// (docs/architecture/module-ranked.md — packed into the message by the
/// proving adapter).
final class Ranked extends BallotSpec {
  final List<int> ordering;

  Ranked(List<int> ordering) : ordering = List.unmodifiable(ordering);

  @override
  VoterModule get module => VoterModule.ranked;

  @override
  bool isValidFor(int optionCount) =>
      ordering.isNotEmpty &&
      ordering.length <= optionCount &&
      ordering.toSet().length == ordering.length &&
      ordering.every((i) => i >= 0 && i < optionCount);

  @override
  bool operator ==(Object other) =>
      other is Ranked && _intListEquals(other.ordering, ordering);

  @override
  int get hashCode => Object.hash(Ranked, Object.hashAll(ordering));

  @override
  String toString() => 'Ranked($ordering)';
}

/// `quadratic` module: votes per option under the uniform credit budget
/// (docs/architecture/module-quadratic.md — cost is Σvᵢ², budget 100,
/// 4-bit slots cap any single option at 15).
final class Quadratic extends BallotSpec {
  /// Fixed uniform budget (CREDITS in ZkQuadraticVoting.sol).
  static const int credits = 100;

  /// 4-bit slot ceiling per option.
  static const int maxVotesPerOption = 15;

  final List<int> alloc;

  Quadratic(List<int> alloc) : alloc = List.unmodifiable(alloc);

  int get cost => alloc.fold(0, (sum, v) => sum + v * v);

  @override
  VoterModule get module => VoterModule.quadratic;

  @override
  bool isValidFor(int optionCount) =>
      alloc.isNotEmpty &&
      alloc.length <= optionCount &&
      alloc.every((v) => v >= 0 && v <= maxVotesPerOption) &&
      alloc.any((v) => v > 0) &&
      cost <= credits;

  @override
  bool operator ==(Object other) =>
      other is Quadratic && _intListEquals(other.alloc, alloc);

  @override
  int get hashCode => Object.hash(Quadratic, Object.hashAll(alloc));

  @override
  String toString() => 'Quadratic($alloc)';
}

/// `survey` module: one answer word per question, in question order
/// (docs/architecture/module-survey.md — the adapter binds
/// `keccak256(abi.encode(answers)) >> 8` as the message).
final class Survey extends BallotSpec {
  final List<BigInt> answers;

  Survey(List<BigInt> answers) : answers = List.unmodifiable(answers);

  @override
  VoterModule get module => VoterModule.survey;

  @override
  bool isValidFor(int optionCount) =>
      answers.isNotEmpty &&
      answers.length == optionCount &&
      answers.every((a) => a >= BigInt.zero);

  @override
  bool operator ==(Object other) =>
      other is Survey &&
      other.answers.length == answers.length &&
      () {
        for (var i = 0; i < answers.length; i++) {
          if (other.answers[i] != answers[i]) return false;
        }
        return true;
      }();

  @override
  int get hashCode => Object.hash(Survey, Object.hashAll(answers));

  @override
  String toString() => 'Survey($answers)';
}

bool _intListEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// ---------------------------------------------------------------------------
// View, receipt, port
// ---------------------------------------------------------------------------

/// What the voter journey knows about the poll: the on-chain snapshot plus
/// the module resolved on-chain (spec §4.2: no `?module=` guessing) and the
/// results policy from poll metadata.
final class VoterPollView {
  final PollSnapshot snapshot;
  final VoterModule module;
  final ResultsPolicy resultsPolicy;

  const VoterPollView({
    required this.snapshot,
    required this.module,
    this.resultsPolicy = ResultsPolicy.defaultPolicy,
  });

  /// Chain phase: 0 = Registration, 1 = Voting, 2 = Ended.
  int get phase => snapshot.state;

  /// Option count (question count for surveys).
  int get optionCount => snapshot.options.length;

  /// Same view with the phase replaced (applying [ExternalPhaseChanged]
  /// without inventing other snapshot data).
  VoterPollView withPhase(int phase) => VoterPollView(
    snapshot: PollSnapshot(
      address: snapshot.address,
      state: phase,
      options: snapshot.options,
      results: snapshot.results,
      owner: snapshot.owner,
      participantCount: snapshot.participantCount,
    ),
    module: module,
    resultsPolicy: resultsPolicy,
  );
}

/// The voter's receipt: the proof nullifier (their anonymous "I voted" mark)
/// and the transaction hash, enough to verify the cast independently.
final class VoterReceipt {
  final String nullifier;
  final String txHash;

  const VoterReceipt({required this.nullifier, required this.txHash});

  @override
  bool operator ==(Object other) =>
      other is VoterReceipt &&
      other.nullifier == nullifier &&
      other.txHash == txHash;

  @override
  int get hashCode => Object.hash(nullifier, txHash);

  @override
  String toString() => 'VoterReceipt($nullifier, $txHash)';
}

/// All side effects of the voter journey, behind one injectable seam.
/// Implementations live in upper layers (R2f wires core_chain/core_relay);
/// tests inject fakes. core_domain never talks to the network itself.
abstract interface class VoterJourneyPort {
  /// Read the poll's current on-chain truth (snapshot + module + policy).
  Future<VoterPollView> fetchSnapshot();

  /// Is this device's identity a confirmed member of the poll's group?
  Future<bool> checkEligibility(VoterPollView view);

  /// Ask the relayer to register this identity (wallet-free join). Returns
  /// when the request is accepted; on-chain confirmation is re-checked via
  /// the join-pending loop, not assumed.
  Future<void> requestJoin(VoterPollView view);

  /// Generate the ZK membership proof binding [spec]'s encoded message.
  /// Implementations should honor [cancellation] (abort the prover);
  /// the machine additionally drops late results after cancellation.
  Future<RelayProof> generateProof(
    BallotSpec spec,
    VoterPollView view,
    CancellationToken cancellation,
  );

  /// Submit the ballot through the relayer; returns the voter's receipt.
  Future<VoterReceipt> relayBallot(
    BallotSpec spec,
    RelayProof proof,
    VoterPollView view,
    CancellationToken cancellation,
  );
}

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------

/// Sealed root: switches over [VoterState] are exhaustive.
sealed class VoterState extends JourneyState {
  const VoterState();
}

/// Fetching the poll snapshot (initial state; also re-entered on Refresh).
final class VoterLoading extends VoterState with EffectInProgress {
  @override
  final CancellationToken cancellation;

  VoterLoading(this.cancellation);

  @override
  String get id => 'voter.loading';

  @override
  NextAction? get nextAction =>
      const NextAction(labelKey: 'action.loading', type: NextActionType.wait);
}

/// Loading or eligibility-checking failed; Retry reloads from scratch.
final class VoterLoadFailed extends VoterState with JourneyErrorState {
  @override
  final Object? cause;

  const VoterLoadFailed(this.cause);

  @override
  String get id => 'voter.loadFailed';

  @override
  String get messageKey => 'error.loadFailed';

  @override
  JourneyEvent get recoveryEvent => const Retry();
}

/// Checking whether this identity is a confirmed member of the poll group.
/// [afterJoin] marks the join-pending recheck loop: a negative result then
/// means "registration still pending", not "not eligible".
final class VoterEligibilityChecking extends VoterState with EffectInProgress {
  final VoterPollView view;
  final bool afterJoin;
  @override
  final CancellationToken cancellation;

  VoterEligibilityChecking({
    required this.view,
    required this.afterJoin,
    required this.cancellation,
  });

  @override
  String get id => 'voter.eligibilityChecking';

  @override
  NextAction? get nextAction => const NextAction(
    labelKey: 'action.checkingEligibility',
    type: NextActionType.wait,
  );
}

/// Not a member of this poll. The one action is requesting to join —
/// enabled only while registration is open and a relayer is available,
/// otherwise honestly disabled with the reason.
final class VoterNotEligible extends VoterState {
  final VoterPollView view;

  /// Why joining is impossible right now, or `null` when it is possible.
  final String? joinDisabledReasonKey;

  const VoterNotEligible({required this.view, this.joinDisabledReasonKey});

  bool get canRequestJoin => joinDisabledReasonKey == null;

  @override
  String get id => 'voter.notEligible';

  @override
  NextAction? get nextAction => NextAction(
    labelKey: 'action.requestJoin',
    type: NextActionType.submit,
    disabledReasonKey: joinDisabledReasonKey,
  );
}

/// The relayer is registering this identity in the poll group.
final class VoterJoinInProgress extends VoterState with EffectInProgress {
  final VoterPollView view;
  @override
  final CancellationToken cancellation;

  VoterJoinInProgress({required this.view, required this.cancellation});

  @override
  String get id => 'voter.joinInProgress';

  @override
  NextAction? get nextAction =>
      const NextAction(labelKey: 'action.joining', type: NextActionType.wait);
}

/// The join request failed; Retry re-submits it.
final class VoterJoinFailed extends VoterState with JourneyErrorState {
  final VoterPollView view;
  @override
  final Object? cause;

  const VoterJoinFailed({required this.view, required this.cause});

  @override
  String get id => 'voter.joinFailed';

  @override
  String get messageKey => 'error.joinFailed';

  @override
  JourneyEvent get recoveryEvent => const Retry();
}

/// Join accepted, awaiting on-chain confirmation. [Refresh] (user pull or
/// upper-layer poller) re-checks membership; confirmation is never assumed.
final class VoterJoinPending extends VoterState {
  final VoterPollView view;

  const VoterJoinPending({required this.view});

  @override
  String get id => 'voter.joinPending';

  @override
  NextAction? get nextAction => const NextAction(
    labelKey: 'action.recheckRegistration',
    type: NextActionType.submit,
  );
}

/// A post-join recheck still doesn't see the membership on-chain. Typed
/// error with [Refresh] as the way out — never a silent dead end.
final class VoterRegistrationStillPending extends VoterState
    with JourneyErrorState {
  final VoterPollView view;
  @override
  final Object? cause;

  const VoterRegistrationStillPending({required this.view, this.cause});

  @override
  String get id => 'voter.registrationStillPending';

  @override
  String get messageKey => 'error.registrationStillPending';

  @override
  JourneyEvent get recoveryEvent => const Refresh();
}

/// Eligible, but the ballot is not available on this device right now:
/// either voting hasn't opened (phase 0) or — honestly — this device cannot
/// prove ([blockedReasonKey] set) even though voting is open.
final class VoterWaitingForOpen extends VoterState {
  final VoterPollView view;

  /// Set when voting is open but the ballot is blocked on this device
  /// (e.g. `reason.deviceCannotProve`); `null` while waiting on the phase.
  final String? blockedReasonKey;

  const VoterWaitingForOpen({required this.view, this.blockedReasonKey});

  @override
  String get id => 'voter.waitingForOpen';

  @override
  NextAction? get nextAction => blockedReasonKey == null
      ? const NextAction(
          labelKey: 'action.waitForOpen',
          type: NextActionType.wait,
        )
      : NextAction(
          labelKey: 'action.castVote',
          type: NextActionType.submit,
          disabledReasonKey: blockedReasonKey,
        );
}

/// The ballot. Only reachable with phase == voting, confirmed eligibility
/// and a proving device — every transition row into this state is guarded.
final class VoterBallotOpen extends VoterState {
  final VoterPollView view;

  /// The voter's current (valid) selection, or `null` before any choice.
  final BallotSpec? draft;

  const VoterBallotOpen({required this.view, this.draft});

  @override
  String get id => 'voter.ballotOpen';

  @override
  NextAction? get nextAction => NextAction(
    labelKey: 'action.castVote',
    type: NextActionType.submit,
    disabledReasonKey: draft == null ? 'reason.noSelection' : null,
  );
}

/// Generating the ZK proof. Cancellable: the one action is Cancel, which
/// returns to the ballot with the draft preserved.
final class VoterProvingInProgress extends VoterState with EffectInProgress {
  final VoterPollView view;
  final BallotSpec spec;
  @override
  final CancellationToken cancellation;

  VoterProvingInProgress({
    required this.view,
    required this.spec,
    required this.cancellation,
  });

  @override
  String get id => 'voter.provingInProgress';

  @override
  NextAction? get nextAction =>
      const NextAction(labelKey: 'action.cancel', type: NextActionType.submit);
}

/// Proof generation failed; Retry resumes proving with the same ballot.
final class VoterProofFailed extends VoterState with JourneyErrorState {
  final VoterPollView view;
  final BallotSpec spec;
  @override
  final Object? cause;

  const VoterProofFailed({
    required this.view,
    required this.spec,
    required this.cause,
  });

  @override
  String get id => 'voter.proofFailed';

  @override
  String get messageKey => 'error.proofFailed';

  @override
  JourneyEvent get recoveryEvent => const Retry();
}

/// Relaying the ballot. Not user-cancellable: the relay may already have
/// landed on-chain; its outcome event is authoritative.
final class VoterCastInProgress extends VoterState with EffectInProgress {
  final VoterPollView view;
  final BallotSpec spec;
  final RelayProof proof;
  @override
  final CancellationToken cancellation;

  VoterCastInProgress({
    required this.view,
    required this.spec,
    required this.proof,
    required this.cancellation,
  });

  @override
  String get id => 'voter.castInProgress';

  @override
  NextAction? get nextAction =>
      const NextAction(labelKey: 'action.casting', type: NextActionType.wait);
}

/// Relaying failed; Retry re-submits the SAME proof (no re-proving needed —
/// the proof is still valid for this poll and ballot).
final class VoterRelayFailed extends VoterState with JourneyErrorState {
  final VoterPollView view;
  final BallotSpec spec;
  final RelayProof proof;
  @override
  final Object? cause;

  const VoterRelayFailed({
    required this.view,
    required this.spec,
    required this.proof,
    required this.cause,
  });

  @override
  String get id => 'voter.relayFailed';

  @override
  String get messageKey => 'error.relayFailed';

  @override
  JourneyEvent get recoveryEvent => const Retry();
}

/// The vote landed. Entering this state ALWAYS starts a snapshot refresh
/// ([refreshed] == false on entry from a cast) — the machine, not the
/// screen, owns post-cast freshness, so the legacy stale-results bug is
/// unrepresentable. The next action leads to the receipt.
final class VoterCastSucceeded extends VoterState with EffectInProgress {
  final VoterPollView view;
  final VoterReceipt receipt;

  /// Whether the post-cast snapshot refresh has completed.
  final bool refreshed;

  @override
  final CancellationToken cancellation;

  VoterCastSucceeded({
    required this.view,
    required this.receipt,
    required this.refreshed,
    required this.cancellation,
  });

  @override
  String get id => 'voter.castSucceeded';

  @override
  NextAction? get nextAction => const NextAction(
    labelKey: 'action.viewReceipt',
    type: NextActionType.navigate,
  );
}

/// The receipt was acknowledged/persisted by the upper layer; on to the
/// results (visible or sealed, per policy).
final class VoterReceiptSaved extends VoterState {
  final VoterPollView view;
  final VoterReceipt receipt;

  const VoterReceiptSaved({required this.view, required this.receipt});

  @override
  String get id => 'voter.receiptSaved';

  @override
  NextAction? get nextAction => const NextAction(
    labelKey: 'action.viewResults',
    type: NextActionType.navigate,
  );
}

/// Voting is still open and the policy seals the tally until close
/// (spec §5 default). The action is honestly disabled with the reason;
/// [ExternalPhaseChanged] to Ended unseals.
final class VoterResultsSealed extends VoterState {
  final VoterPollView view;
  final ResultsPolicy policy;

  const VoterResultsSealed({required this.view, required this.policy});

  @override
  String get id => 'voter.resultsSealed';

  @override
  NextAction? get nextAction => const NextAction(
    labelKey: 'action.viewResults',
    type: NextActionType.submit,
    disabledReasonKey: 'reason.resultsSealedUntilClose',
  );
}

/// Results are visible (poll ended, or live-public policy). Terminal.
final class VoterResultsVisible extends VoterState {
  final VoterPollView view;

  const VoterResultsVisible({required this.view});

  @override
  String get id => 'voter.resultsVisible';

  @override
  bool get isTerminal => true;

  @override
  NextAction? get nextAction => null;
}

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

/// The snapshot fetch completed (loading effect).
final class VoterSnapshotLoaded extends JourneyEvent {
  final VoterPollView view;

  const VoterSnapshotLoaded(this.view);
}

/// Loading or eligibility-checking failed.
final class VoterLoadErrored extends JourneyEvent {
  final Object cause;

  const VoterLoadErrored(this.cause);
}

/// The eligibility check completed.
final class VoterEligibilityChecked extends JourneyEvent {
  final bool eligible;

  const VoterEligibilityChecked({required this.eligible});
}

/// The voter asks to join the poll (from [VoterNotEligible]).
final class VoterRequestJoin extends JourneyEvent {
  const VoterRequestJoin();
}

/// The relayer accepted the join request (on-chain confirmation pending).
final class VoterJoinSucceeded extends JourneyEvent {
  const VoterJoinSucceeded();
}

/// The join request failed.
final class VoterJoinErrored extends JourneyEvent {
  final Object cause;

  const VoterJoinErrored(this.cause);
}

/// The voter changed their selection on the open ballot. Guarded: the
/// payload must match the poll's module and be valid for its options.
final class VoterBallotEdited extends JourneyEvent {
  final BallotSpec spec;

  const VoterBallotEdited(this.spec);
}

/// The voter submits the current draft (starts proving).
final class VoterBallotSubmitted extends JourneyEvent {
  const VoterBallotSubmitted();
}

/// The voter cancels proof generation (back to the ballot, draft kept).
final class VoterProvingCancelled extends JourneyEvent {
  const VoterProvingCancelled();
}

/// Proof generation completed.
final class VoterProofGenerated extends JourneyEvent {
  final RelayProof proof;

  const VoterProofGenerated(this.proof);
}

/// Proof generation failed.
final class VoterProofErrored extends JourneyEvent {
  final Object cause;

  const VoterProofErrored(this.cause);
}

/// The relay confirmed the cast.
final class VoterCastCompleted extends JourneyEvent {
  final VoterReceipt receipt;

  const VoterCastCompleted(this.receipt);
}

/// The relay failed.
final class VoterCastErrored extends JourneyEvent {
  final Object cause;

  const VoterCastErrored(this.cause);
}

/// The post-cast auto-refresh delivered a fresh snapshot.
final class VoterSnapshotRefreshed extends JourneyEvent {
  final VoterPollView view;

  const VoterSnapshotRefreshed(this.view);
}

/// The upper layer saved/showed the receipt (navigation happened).
final class VoterReceiptAcknowledged extends JourneyEvent {
  const VoterReceiptAcknowledged();
}

/// The voter moves on from the receipt to the results.
final class VoterResultsRequested extends JourneyEvent {
  const VoterResultsRequested();
}

// ---------------------------------------------------------------------------
// Machine
// ---------------------------------------------------------------------------

/// The voter journey machine.
///
/// `loading → eligibilityChecking → notEligible → joinInProgress →
/// joinPending → (recheck) → waitingForOpen → ballotOpen → proving →
/// cast → castSucceeded(auto-refresh) → receiptSaved →
/// resultsVisible | resultsSealed`, with typed error exits for load, join,
/// proof, relay and registration-still-pending.
final class VoterJourneyMachine extends JourneyMachine<VoterState> {
  final VoterJourneyPort port;
  final Capabilities capabilities;

  VoterJourneyMachine({required this.port, required this.capabilities})
    : super(VoterLoading(CancellationToken())) {
    _startEffect(state);
  }

  // --- guards/builders ------------------------------------------------------

  /// THE ballot gate: phase == voting and this device can prove. Eligibility
  /// is structural — only confirmed-eligible paths reach rows using this.
  bool _ballotAvailable(VoterPollView view) =>
      view.phase == 1 && capabilities.canProve;

  String get _cannotProveReason =>
      capabilities.reasonFor(Capability.prove) ?? 'reason.deviceCannotProve';

  VoterNotEligible _notEligible(VoterPollView view) => VoterNotEligible(
    view: view,
    joinDisabledReasonKey: view.phase != 0
        ? 'reason.registrationClosed'
        : capabilities.relayerAvailable
        ? null
        : capabilities.reasonFor(Capability.relayer) ??
              'reason.relayerUnavailable',
  );

  VoterWaitingForOpen _waitingForOpen(VoterPollView view) =>
      VoterWaitingForOpen(
        view: view,
        blockedReasonKey: view.phase == 1 && !capabilities.canProve
            ? _cannotProveReason
            : null,
      );

  VoterEligibilityChecking _recheck(
    VoterPollView view, {
    required bool after,
  }) => VoterEligibilityChecking(
    view: view,
    afterJoin: after,
    cancellation: CancellationToken(),
  );

  /// Where an eligible voter lands for [view]'s phase. The ballot row is the
  /// only producer of [VoterBallotOpen] besides the waiting-room phase-change
  /// row — both apply the same [_ballotAvailable] gate.
  VoterState _eligibleLanding(VoterPollView view) {
    if (view.phase == 2) return VoterResultsVisible(view: view);
    if (_ballotAvailable(view)) return VoterBallotOpen(view: view);
    return _waitingForOpen(view);
  }

  // --- transition table -----------------------------------------------------

  @override
  late final List<JourneyTransition<VoterState>> transitions = [
    // loading -----------------------------------------------------------------
    JourneyTransition(
      from: VoterLoading,
      on: VoterSnapshotLoaded,
      guard: (s, e) => (e as VoterSnapshotLoaded).view.phase == 2,
      to: (s, e) => VoterResultsVisible(view: (e as VoterSnapshotLoaded).view),
    ),
    JourneyTransition(
      from: VoterLoading,
      on: VoterSnapshotLoaded,
      guard: (s, e) => (e as VoterSnapshotLoaded).view.phase != 2,
      to: (s, e) => _recheck((e as VoterSnapshotLoaded).view, after: false),
    ),
    JourneyTransition(
      from: VoterLoading,
      on: VoterLoadErrored,
      to: (s, e) => VoterLoadFailed((e as VoterLoadErrored).cause),
    ),
    JourneyTransition(
      from: VoterLoadFailed,
      on: Retry,
      to: (s, e) => VoterLoading(CancellationToken()),
    ),

    // eligibility check -------------------------------------------------------
    JourneyTransition(
      from: VoterEligibilityChecking,
      on: VoterEligibilityChecked,
      guard: (s, e) => (e as VoterEligibilityChecked).eligible,
      to: (s, e) => _eligibleLanding((s as VoterEligibilityChecking).view),
    ),
    JourneyTransition(
      from: VoterEligibilityChecking,
      on: VoterEligibilityChecked,
      guard: (s, e) =>
          !(e as VoterEligibilityChecked).eligible &&
          (s as VoterEligibilityChecking).afterJoin,
      to: (s, e) => VoterRegistrationStillPending(
        view: (s as VoterEligibilityChecking).view,
      ),
    ),
    JourneyTransition(
      from: VoterEligibilityChecking,
      on: VoterEligibilityChecked,
      guard: (s, e) =>
          !(e as VoterEligibilityChecked).eligible &&
          !(s as VoterEligibilityChecking).afterJoin,
      to: (s, e) => _notEligible((s as VoterEligibilityChecking).view),
    ),
    JourneyTransition(
      from: VoterEligibilityChecking,
      on: VoterLoadErrored,
      to: (s, e) => VoterLoadFailed((e as VoterLoadErrored).cause),
    ),

    // not eligible / join -----------------------------------------------------
    JourneyTransition(
      from: VoterNotEligible,
      on: VoterRequestJoin,
      guard: (s, e) => (s as VoterNotEligible).canRequestJoin,
      to: (s, e) => VoterJoinInProgress(
        view: (s as VoterNotEligible).view,
        cancellation: CancellationToken(),
      ),
    ),
    JourneyTransition(
      from: VoterNotEligible,
      on: Refresh,
      to: (s, e) => VoterLoading(CancellationToken()),
    ),
    JourneyTransition(
      from: VoterNotEligible,
      on: ExternalPhaseChanged,
      guard: (s, e) => (e as ExternalPhaseChanged).phase == 2,
      to: (s, e) =>
          VoterResultsVisible(view: (s as VoterNotEligible).view.withPhase(2)),
    ),
    JourneyTransition(
      from: VoterNotEligible,
      on: ExternalPhaseChanged,
      guard: (s, e) => (e as ExternalPhaseChanged).phase != 2,
      to: (s, e) => _notEligible(
        (s as VoterNotEligible).view.withPhase(
          (e as ExternalPhaseChanged).phase,
        ),
      ),
    ),
    JourneyTransition(
      from: VoterJoinInProgress,
      on: VoterJoinSucceeded,
      to: (s, e) => VoterJoinPending(view: (s as VoterJoinInProgress).view),
    ),
    JourneyTransition(
      from: VoterJoinInProgress,
      on: VoterJoinErrored,
      to: (s, e) => VoterJoinFailed(
        view: (s as VoterJoinInProgress).view,
        cause: (e as VoterJoinErrored).cause,
      ),
    ),
    JourneyTransition(
      from: VoterJoinFailed,
      on: Retry,
      to: (s, e) => VoterJoinInProgress(
        view: (s as VoterJoinFailed).view,
        cancellation: CancellationToken(),
      ),
    ),

    // join pending: on-chain confirmation is re-checked, never assumed --------
    JourneyTransition(
      from: VoterJoinPending,
      on: Refresh,
      to: (s, e) => _recheck((s as VoterJoinPending).view, after: true),
    ),
    JourneyTransition(
      from: VoterJoinPending,
      on: ExternalPhaseChanged,
      guard: (s, e) => (e as ExternalPhaseChanged).phase == 2,
      to: (s, e) =>
          VoterResultsVisible(view: (s as VoterJoinPending).view.withPhase(2)),
    ),
    JourneyTransition(
      from: VoterJoinPending,
      on: ExternalPhaseChanged,
      guard: (s, e) => (e as ExternalPhaseChanged).phase != 2,
      to: (s, e) => VoterJoinPending(
        view: (s as VoterJoinPending).view.withPhase(
          (e as ExternalPhaseChanged).phase,
        ),
      ),
    ),
    JourneyTransition(
      from: VoterRegistrationStillPending,
      on: Refresh,
      to: (s, e) =>
          _recheck((s as VoterRegistrationStillPending).view, after: true),
    ),

    // waiting for open: phase truth is external -------------------------------
    JourneyTransition(
      from: VoterWaitingForOpen,
      on: ExternalPhaseChanged,
      // The ONLY other producer of VoterBallotOpen: same gate as
      // _eligibleLanding — voting open AND this device can prove.
      guard: (s, e) =>
          (e as ExternalPhaseChanged).phase == 1 && capabilities.canProve,
      to: (s, e) =>
          VoterBallotOpen(view: (s as VoterWaitingForOpen).view.withPhase(1)),
    ),
    JourneyTransition(
      from: VoterWaitingForOpen,
      on: ExternalPhaseChanged,
      guard: (s, e) =>
          (e as ExternalPhaseChanged).phase == 1 && !capabilities.canProve,
      to: (s, e) =>
          _waitingForOpen((s as VoterWaitingForOpen).view.withPhase(1)),
    ),
    JourneyTransition(
      from: VoterWaitingForOpen,
      on: ExternalPhaseChanged,
      guard: (s, e) => (e as ExternalPhaseChanged).phase == 0,
      to: (s, e) =>
          _waitingForOpen((s as VoterWaitingForOpen).view.withPhase(0)),
    ),
    JourneyTransition(
      from: VoterWaitingForOpen,
      on: ExternalPhaseChanged,
      guard: (s, e) => (e as ExternalPhaseChanged).phase == 2,
      to: (s, e) => VoterResultsVisible(
        view: (s as VoterWaitingForOpen).view.withPhase(2),
      ),
    ),
    JourneyTransition(
      from: VoterWaitingForOpen,
      on: Refresh,
      to: (s, e) => VoterLoading(CancellationToken()),
    ),

    // ballot -------------------------------------------------------------------
    JourneyTransition(
      from: VoterBallotOpen,
      on: VoterBallotEdited,
      // A payload of the wrong module or invalid for this poll's options is
      // guard-rejected: JourneyViolation, never a silently broken draft.
      guard: (s, e) {
        final spec = (e as VoterBallotEdited).spec;
        final view = (s as VoterBallotOpen).view;
        return spec.module == view.module && spec.isValidFor(view.optionCount);
      },
      to: (s, e) => VoterBallotOpen(
        view: (s as VoterBallotOpen).view,
        draft: (e as VoterBallotEdited).spec,
      ),
    ),
    JourneyTransition(
      from: VoterBallotOpen,
      on: VoterBallotSubmitted,
      // Defense in depth: re-assert the ballot gate at submit time too.
      guard: (s, e) {
        final open = s as VoterBallotOpen;
        return open.draft != null && _ballotAvailable(open.view);
      },
      to: (s, e) => VoterProvingInProgress(
        view: (s as VoterBallotOpen).view,
        spec: s.draft!,
        cancellation: CancellationToken(),
      ),
    ),
    JourneyTransition(
      from: VoterBallotOpen,
      on: ExternalPhaseChanged,
      guard: (s, e) => (e as ExternalPhaseChanged).phase == 2,
      to: (s, e) =>
          VoterResultsVisible(view: (s as VoterBallotOpen).view.withPhase(2)),
    ),
    JourneyTransition(
      from: VoterBallotOpen,
      on: ExternalPhaseChanged,
      guard: (s, e) => (e as ExternalPhaseChanged).phase == 1,
      to: (s, e) => s, // already on the ballot; nothing changed
    ),
    JourneyTransition(
      from: VoterBallotOpen,
      on: ExternalPhaseChanged,
      guard: (s, e) => (e as ExternalPhaseChanged).phase == 0,
      to: (s, e) => _waitingForOpen((s as VoterBallotOpen).view.withPhase(0)),
    ),
    JourneyTransition(
      from: VoterBallotOpen,
      on: Refresh,
      to: (s, e) => VoterLoading(CancellationToken()),
    ),

    // proving -------------------------------------------------------------------
    JourneyTransition(
      from: VoterProvingInProgress,
      on: VoterProofGenerated,
      to: (s, e) => VoterCastInProgress(
        view: (s as VoterProvingInProgress).view,
        spec: s.spec,
        proof: (e as VoterProofGenerated).proof,
        cancellation: CancellationToken(),
      ),
    ),
    JourneyTransition(
      from: VoterProvingInProgress,
      on: VoterProofErrored,
      to: (s, e) => VoterProofFailed(
        view: (s as VoterProvingInProgress).view,
        spec: s.spec,
        cause: (e as VoterProofErrored).cause,
      ),
    ),
    JourneyTransition(
      from: VoterProvingInProgress,
      on: VoterProvingCancelled,
      // Leaving the state auto-cancels the token; the draft is preserved.
      to: (s, e) => VoterBallotOpen(
        view: (s as VoterProvingInProgress).view,
        draft: s.spec,
      ),
    ),
    JourneyTransition(
      from: VoterProvingInProgress,
      on: ExternalPhaseChanged,
      guard: (s, e) => (e as ExternalPhaseChanged).phase == 2,
      to: (s, e) => VoterResultsVisible(
        view: (s as VoterProvingInProgress).view.withPhase(2),
      ),
    ),
    JourneyTransition(
      from: VoterProvingInProgress,
      on: ExternalPhaseChanged,
      guard: (s, e) => (e as ExternalPhaseChanged).phase != 2,
      to: (s, e) => s, // identical instance: effect keeps running
    ),
    JourneyTransition(
      from: VoterProofFailed,
      on: Retry,
      to: (s, e) => VoterProvingInProgress(
        view: (s as VoterProofFailed).view,
        spec: s.spec,
        cancellation: CancellationToken(),
      ),
    ),

    // casting --------------------------------------------------------------------
    JourneyTransition(
      from: VoterCastInProgress,
      on: VoterCastCompleted,
      to: (s, e) => VoterCastSucceeded(
        view: (s as VoterCastInProgress).view,
        receipt: (e as VoterCastCompleted).receipt,
        refreshed: false,
        cancellation: CancellationToken(),
      ),
    ),
    JourneyTransition(
      from: VoterCastInProgress,
      on: VoterCastErrored,
      to: (s, e) => VoterRelayFailed(
        view: (s as VoterCastInProgress).view,
        spec: s.spec,
        proof: s.proof,
        cause: (e as VoterCastErrored).cause,
      ),
    ),
    JourneyTransition(
      from: VoterCastInProgress,
      on: ExternalPhaseChanged,
      to: (s, e) => s, // relay outcome is authoritative; keep waiting
    ),
    JourneyTransition(
      from: VoterRelayFailed,
      on: Retry,
      // Same proof, no re-proving: it is still valid for this ballot.
      to: (s, e) => VoterCastInProgress(
        view: (s as VoterRelayFailed).view,
        spec: s.spec,
        proof: s.proof,
        cancellation: CancellationToken(),
      ),
    ),

    // cast succeeded: auto-refresh, then on to the receipt ------------------------
    JourneyTransition(
      from: VoterCastSucceeded,
      on: VoterSnapshotRefreshed,
      to: (s, e) => VoterCastSucceeded(
        view: (e as VoterSnapshotRefreshed).view,
        receipt: (s as VoterCastSucceeded).receipt,
        refreshed: true,
        cancellation: CancellationToken(),
      ),
    ),
    JourneyTransition(
      from: VoterCastSucceeded,
      on: VoterReceiptAcknowledged,
      to: (s, e) => VoterReceiptSaved(
        view: (s as VoterCastSucceeded).view,
        receipt: s.receipt,
      ),
    ),
    JourneyTransition(
      from: VoterCastSucceeded,
      on: ExternalPhaseChanged,
      to: (s, e) {
        final done = s as VoterCastSucceeded;
        return VoterCastSucceeded(
          view: done.view.withPhase((e as ExternalPhaseChanged).phase),
          receipt: done.receipt,
          refreshed: done.refreshed,
          cancellation: CancellationToken(),
        );
      },
    ),

    // receipt → results -----------------------------------------------------------
    JourneyTransition(
      from: VoterReceiptSaved,
      on: VoterResultsRequested,
      guard: (s, e) => _resultsVisibleNow((s as VoterReceiptSaved).view),
      to: (s, e) => VoterResultsVisible(view: (s as VoterReceiptSaved).view),
    ),
    JourneyTransition(
      from: VoterReceiptSaved,
      on: VoterResultsRequested,
      guard: (s, e) => !_resultsVisibleNow((s as VoterReceiptSaved).view),
      to: (s, e) => VoterResultsSealed(
        view: (s as VoterReceiptSaved).view,
        policy: s.view.resultsPolicy,
      ),
    ),
    JourneyTransition(
      from: VoterReceiptSaved,
      on: ExternalPhaseChanged,
      to: (s, e) => VoterReceiptSaved(
        view: (s as VoterReceiptSaved).view.withPhase(
          (e as ExternalPhaseChanged).phase,
        ),
        receipt: s.receipt,
      ),
    ),
    JourneyTransition(
      from: VoterResultsSealed,
      on: ExternalPhaseChanged,
      guard: (s, e) => (e as ExternalPhaseChanged).phase == 2,
      to: (s, e) => VoterResultsVisible(
        view: (s as VoterResultsSealed).view.withPhase(2),
      ),
    ),
    JourneyTransition(
      from: VoterResultsSealed,
      on: ExternalPhaseChanged,
      guard: (s, e) => (e as ExternalPhaseChanged).phase != 2,
      to: (s, e) => s,
    ),
  ];

  static bool _resultsVisibleNow(VoterPollView view) =>
      view.phase == 2 || view.resultsPolicy == ResultsPolicy.livePublic;

  // --- effects ----------------------------------------------------------------

  @override
  void onEnter(VoterState previous, VoterState next) {
    if (identical(previous, next)) return; // no-op self transition
    _startEffect(next);
  }

  void _startEffect(VoterState next) {
    switch (next) {
      case VoterLoading():
        unawaited(_load(next));
      case VoterEligibilityChecking():
        unawaited(_checkEligibility(next));
      case VoterJoinInProgress():
        unawaited(_join(next));
      case VoterProvingInProgress():
        unawaited(_prove(next));
      case VoterCastInProgress():
        unawaited(_cast(next));
      case VoterCastSucceeded(refreshed: false):
        // The post-cast refresh is the machine's job, unconditionally.
        unawaited(_refreshAfterCast(next));
      default:
        break;
    }
  }

  Future<void> _load(VoterLoading loading) async {
    try {
      final view = await port.fetchSnapshot();
      if (loading.cancellation.isCancelled) return;
      await advance(VoterSnapshotLoaded(view));
    } on Object catch (error) {
      if (loading.cancellation.isCancelled) return;
      await advance(VoterLoadErrored(error));
    }
  }

  Future<void> _checkEligibility(VoterEligibilityChecking checking) async {
    try {
      final eligible = await port.checkEligibility(checking.view);
      if (checking.cancellation.isCancelled) return;
      await advance(VoterEligibilityChecked(eligible: eligible));
    } on Object catch (error) {
      if (checking.cancellation.isCancelled) return;
      await advance(VoterLoadErrored(error));
    }
  }

  Future<void> _join(VoterJoinInProgress joining) async {
    try {
      await port.requestJoin(joining.view);
      if (joining.cancellation.isCancelled) return;
      await advance(const VoterJoinSucceeded());
    } on Object catch (error) {
      if (joining.cancellation.isCancelled) return;
      await advance(VoterJoinErrored(error));
    }
  }

  Future<void> _prove(VoterProvingInProgress proving) async {
    try {
      final proof = await port.generateProof(
        proving.spec,
        proving.view,
        proving.cancellation,
      );
      if (proving.cancellation.isCancelled) return;
      await advance(VoterProofGenerated(proof));
    } on Object catch (error) {
      if (proving.cancellation.isCancelled) return;
      await advance(VoterProofErrored(error));
    }
  }

  Future<void> _cast(VoterCastInProgress casting) async {
    try {
      final receipt = await port.relayBallot(
        casting.spec,
        casting.proof,
        casting.view,
        casting.cancellation,
      );
      if (casting.cancellation.isCancelled) return;
      await advance(VoterCastCompleted(receipt));
    } on Object catch (error) {
      if (casting.cancellation.isCancelled) return;
      await advance(VoterCastErrored(error));
    }
  }

  Future<void> _refreshAfterCast(VoterCastSucceeded done) async {
    VoterPollView view;
    try {
      view = await port.fetchSnapshot();
    } on Object {
      // Refresh failure is non-fatal post-cast: keep the carried view (and
      // stop the loop by marking refreshed).
      view = done.view;
    }
    if (done.cancellation.isCancelled) return;
    await advance(VoterSnapshotRefreshed(view));
  }
}
