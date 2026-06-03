import 'package:flutter/foundation.dart';

import '../../../core/voting/quadratic_alloc.dart';
import '../../../data/models/poll_snapshot.dart';
import '../../../data/repositories/quadratic_repository.dart';
import '../../../data/services/proof_service.dart';
import '../../../data/services/relay_client.dart';
import '../../core/view_state.dart';

enum QuadraticVoteStatus { idle, proving, relaying, success, error }

/// Drives the M5 quadratic-voting surface: loads the poll snapshot, runs the
/// same up-front registration pre-check as M1/M3/M4, and casts a QUADRATIC
/// ballot — a *packed allocation* (up to 8 direct 4-bit slots, `vᵢ` votes for
/// option `i`, cost `vᵢ²`) bound into the Semaphore proof's `message` and
/// relayed gaslessly via `/api/relay/quadratic-vote`.
///
/// Sibling of [RankedVoteViewModel] with one structural difference: the ballot
/// STATE (the allocation vector + the live budget meter) lives HERE on the
/// view-model — not in the screen's State as the ranked surface did — so the
/// budget-meter logic (`spent = Σ vᵢ²`, `remaining = CREDITS - spent`, the
/// increment-disable rule) is unit-testable and the meter updates reactively.
/// Steppers call [increment]/[decrement]; the meter is a `Consumer`.
///
/// The contract's `getResults()` IS the authoritative outcome (the per-option
/// vote sum), so unlike ranked there is NO off-chain replay — this view-model
/// owns the cast path only; the winner is read straight from the chain.
class QuadraticVoteViewModel extends ChangeNotifier {
  final QuadraticRepository _repo;
  final ProofService _proofService;
  final RelayClient _relay;
  final String pollAddress;

  QuadraticVoteViewModel({
    required QuadraticRepository repository,
    required ProofService proofService,
    required RelayClient relayClient,
    required this.pollAddress,
  })  : _repo = repository,
        _proofService = proofService,
        _relay = relayClient;

  // ── Poll load ──────────────────────────────────────────────────────────────
  ViewState state = ViewState.idle;
  String? error;
  PollSnapshot? snapshot;

  /// The voter's allocation vector — one entry per option (`votes[i]` = votes
  /// for option `i`). Sized to the poll's options once the snapshot loads.
  List<int> votes = <int>[];

  Future<void> load() async {
    state = ViewState.loading;
    _notify();
    try {
      final snap = await _repo.fetchPoll(pollAddress);
      snapshot = snap;
      votes = List<int>.filled(snap.options.length, 0);
      state = ViewState.loaded;
    } catch (e) {
      error = e.toString();
      state = ViewState.error;
    }
    _notify();
  }

  // ── Budget meter (live, on the view-model so it's unit-testable) ────────────

  /// Total CREDITS budget every voter receives (mirror of the contract).
  int get credits => kQuadraticCredits;

  /// Credits spent so far: `Σ vᵢ²`. Mirrors the contract's `sumSq`.
  int get spent => creditsSpent(votes);

  /// Credits remaining: `CREDITS - spent`. Never negative (increments that
  /// would exceed the budget are blocked by [canIncrement]).
  int get remaining => credits - spent;

  /// The total votes allocated: `Σ vᵢ`. A ballot is empty (the contract's
  /// `EmptyBallot`) iff this is `0`.
  int get totalAllocated => totalVotes(votes);

  /// Whether option [i] can be incremented from `vᵢ` to `vᵢ + 1` WITHOUT
  /// exceeding the budget — and without exceeding the 4-bit slot max.
  ///
  /// Going from `v` to `v+1` raises `spent` by `(v+1)² - v² = 2v + 1`, so the
  /// guard is `spent + 2*vᵢ + 1 ≤ CREDITS` (mirrors the contract's
  /// `Σ vᵢ² ≤ CREDITS`). This caps a SINGLE option at `v = 10` (10² = 100 =
  /// CREDITS) — the `+` flips off there — and likewise blocks `[10, 1]` (with
  /// one option at 10 the budget is fully spent, so EVERY other option's `+` is
  /// also disabled). 4-bit ceiling `vᵢ < 15` is the never-binding belt-and-
  /// braces guard (the budget always bites first).
  bool canIncrement(int i) {
    if (i < 0 || i >= votes.length) return false;
    final v = votes[i];
    if (v >= kMaxSlotVotes) return false;
    return spent + 2 * v + 1 <= credits;
  }

  /// Whether option [i] can be decremented (i.e. `vᵢ > 0`).
  bool canDecrement(int i) =>
      i >= 0 && i < votes.length && votes[i] > 0;

  /// Increment option [i] by one vote, if [canIncrement] allows it. No-op
  /// otherwise (the UI also disables the control, this is the model guard).
  void increment(int i) {
    if (!canIncrement(i) || isBusy) return;
    votes[i] += 1;
    _notify();
  }

  /// Decrement option [i] by one vote, if `vᵢ > 0`.
  void decrement(int i) {
    if (!canDecrement(i) || isBusy) return;
    votes[i] -= 1;
    _notify();
  }

  /// Pack the current allocation vector into the `uint32` ballot the contract /
  /// proof `message` expects. Delegates to the canonical [packAlloc] (DIRECT
  /// 4-bit slots, no `+1`).
  int get packedAlloc => packAlloc(votes);

  /// Whether a cast is allowed: at least one vote allocated (the contract's
  /// `EmptyBallot` guard), an identity entered (checked at cast), and no cast in
  /// flight.
  bool get canCast => totalAllocated >= 1 && !isBusy;

  /// Reset the allocation to all-zero (e.g. a "clear" affordance).
  void clearAllocation() {
    votes = List<int>.filled(votes.length, 0);
    _notify();
  }

  // ── Cast ────────────────────────────────────────────────────────────────────
  QuadraticVoteStatus status = QuadraticVoteStatus.idle;
  String? castError;
  String? txHash;

  bool get isBusy =>
      status == QuadraticVoteStatus.proving ||
      status == QuadraticVoteStatus.relaying;

  // Proactive registration status for the entered identity, so the voter sees
  // they aren't a member BEFORE casting (instead of a post-cast "leaf -1").
  String? myCommitment;
  bool? isRegistered; // null = unknown / check failed
  bool checkingRegistration = false;

  // Monotonic token: each checkRegistration() call captures the current value;
  // a late result from a superseded call (re-typed seed, or cleared field) is
  // dropped so it can't resurrect/overwrite newer state.
  int _regToken = 0;

  bool _disposed = false;
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  // castVote is long-running (proving + relaying); guard against notifying after
  // the screen popped and disposed this notifier.
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Derive the entered identity's commitment and check whether it's already a
  /// member of this poll's group, so the form can show registration status
  /// up-front. Failures leave [isRegistered] null (unknown) rather than error.
  Future<void> checkRegistration(String identitySeed) async {
    checkingRegistration = true;
    _notify();
    final token = ++_regToken;
    try {
      // Capture into locals and gate ALL state writes on the token AFTER the
      // awaits — a superseded call resumes here with a stale result and must
      // not clobber newer state (type→clear, or type A→type B).
      final commitment = await _proofService.deriveCommitment(identitySeed);
      final group = await _repo.fetchGroup(pollAddress);
      if (token != _regToken) return;
      myCommitment = commitment;
      isRegistered = group.contains(commitment);
    } catch (_) {
      if (token == _regToken) isRegistered = null;
    } finally {
      if (token == _regToken) {
        checkingRegistration = false;
        _notify();
      }
    }
  }

  /// Clear any registration status (e.g. the seed field was emptied) and
  /// supersede any in-flight [checkRegistration] so its late result can't
  /// resurrect the panel.
  void clearRegistration() {
    _regToken++; // supersede any in-flight check
    myCommitment = null;
    isRegistered = null;
    checkingRegistration = false;
    _notify();
  }

  /// Cast the current quadratic ballot. The allocation is read from [votes]; an
  /// all-zero ballot is rejected up-front (the contract's `EmptyBallot`).
  Future<void> castQuadratic({required String identitySeed}) async {
    castError = null;
    txHash = null;
    if (totalAllocated < 1) {
      // Mirror the contract's EmptyBallot guard — never relay an empty ballot.
      castError = 'Allocate votes to at least one option.';
      status = QuadraticVoteStatus.error;
      _notify();
      return;
    }
    // Defensive: the increment guard keeps `spent ≤ CREDITS`, but never relay a
    // ballot the contract would reject as OverBudget.
    if (spent > credits) {
      castError = 'Over budget — you spent $spent of $credits credits.';
      status = QuadraticVoteStatus.error;
      _notify();
      return;
    }
    final alloc = packedAlloc;
    status = QuadraticVoteStatus.proving;
    _notify();
    try {
      final group = await _repo.fetchGroup(pollAddress);
      // Membership pre-check: proving over a group you're not a member of fails
      // deep in Semaphore with a cryptic "leaf at index -1". Surface a clear
      // message instead (you can only vote anonymously once registered).
      final commitment = await _proofService.deriveCommitment(identitySeed);
      if (!group.contains(commitment)) {
        castError =
            "This identity isn't registered in this poll yet. Ask the "
            "organizer to confirm you (scan the live-meeting QR), or have your "
            "commitment registered first.";
        status = QuadraticVoteStatus.error;
        _notify();
        return;
      }
      // The packed allocation is the proof's `message` — the relayer/contract
      // reject unless `message == packedAlloc`, binding the ballot to the proof
      // so no one can re-weight the allocation without invalidating the SNARK.
      final proof = await _proofService.generateVoteProof(
        identitySeed: identitySeed,
        memberCommitments: group,
        message: alloc,
        scope: pollAddress,
      );
      status = QuadraticVoteStatus.relaying;
      _notify();
      final result =
          await _relay.relayQuadraticVote(pollAddress, alloc, proof);
      if (result.success) {
        txHash = result.txHash;
        status = QuadraticVoteStatus.success;
      } else {
        castError = result.error ?? 'Relay failed';
        status = QuadraticVoteStatus.error;
      }
    } catch (e) {
      castError = e.toString();
      status = QuadraticVoteStatus.error;
    }
    _notify();
  }
}
