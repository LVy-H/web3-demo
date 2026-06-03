import 'package:flutter/foundation.dart';

import '../../../core/voting/ranked_irv.dart';
import '../../../data/models/poll_snapshot.dart';
import '../../../data/repositories/ranked_repository.dart';
import '../../../data/services/proof_service.dart';
import '../../../data/services/relay_client.dart';
import '../../core/view_state.dart';

enum RankedVoteStatus { idle, proving, relaying, success, error }

/// Drives the M4 ranked-choice surface: loads the poll snapshot, runs the same
/// up-front registration pre-check as M1/M3, and casts a RANKED ballot — a
/// *packed ranking* (up to 8 slots, 4 bits each, most-preferred in slot 0) bound
/// into the Semaphore proof's `message` and relayed gaslessly via
/// `/api/relay/ranked-vote`.
///
/// This is a sibling of [ApprovalVoteViewModel]: same group reconstruction, same
/// client-side proving, same relay. The only difference is the ballot shape (an
/// ordered prefix of options → a packed ranking, instead of a bitmask) and the
/// relay endpoint. The registration token pattern is copied verbatim — a late
/// result from a superseded check must never resurrect/overwrite newer state.
///
/// The contract stores the full ranking + tallies the ROUND-1 first preference
/// ONLY; the instant-runoff WINNER is computed off-chain by [runIrv] over the
/// full ballots. This view-model never claims the first-pref leader is the
/// outcome.
class RankedVoteViewModel extends ChangeNotifier {
  final RankedRepository _repo;
  final ProofService _proofService;
  final RelayClient _relay;
  final String pollAddress;

  RankedVoteViewModel({
    required RankedRepository repository,
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

  Future<void> load() async {
    state = ViewState.loading;
    _notify();
    try {
      snapshot = await _repo.fetchPoll(pollAddress);
      state = ViewState.loaded;
    } catch (e) {
      error = e.toString();
      state = ViewState.error;
    }
    _notify();
  }

  // ── Cast ────────────────────────────────────────────────────────────────────
  RankedVoteStatus status = RankedVoteStatus.idle;
  String? castError;
  String? txHash;

  bool get isBusy =>
      status == RankedVoteStatus.proving || status == RankedVoteStatus.relaying;

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

  /// Pack an ordered [ranking] (option indices, most-preferred first) into the
  /// packed `uint32` ballot the contract / proof `message` expects. Delegates to
  /// the canonical [packRanking] so the encoding is identical to the off-chain
  /// IRV codec (slot value = option index + 1, slot 0 = most preferred).
  static int packFor(List<int> ranking) => packRanking(ranking);

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

  /// Cast a ranked ballot. [ranking] is the ordered prefix of options the voter
  /// ranked (most-preferred first); an empty ranking is rejected up-front (the
  /// contract's `EmptyBallot`).
  Future<void> castRanked({
    required String identitySeed,
    required List<int> ranking,
  }) async {
    castError = null;
    txHash = null;
    if (ranking.isEmpty) {
      // Mirror the contract's EmptyBallot guard — never relay an empty ballot.
      castError = 'Rank at least one option.';
      status = RankedVoteStatus.error;
      _notify();
      return;
    }
    final packedRanking = packFor(ranking);
    status = RankedVoteStatus.proving;
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
        status = RankedVoteStatus.error;
        _notify();
        return;
      }
      // The packed ranking is the proof's `message` — the relayer/contract
      // reject unless `message == packedRanking`, binding the ballot to the
      // proof so no one can reorder or alter the ranking without invalidating
      // the SNARK.
      final proof = await _proofService.generateVoteProof(
        identitySeed: identitySeed,
        memberCommitments: group,
        message: packedRanking,
        scope: pollAddress,
      );
      status = RankedVoteStatus.relaying;
      _notify();
      final result =
          await _relay.relayRankedVote(pollAddress, packedRanking, proof);
      if (result.success) {
        txHash = result.txHash;
        status = RankedVoteStatus.success;
      } else {
        castError = result.error ?? 'Relay failed';
        status = RankedVoteStatus.error;
      }
    } catch (e) {
      castError = e.toString();
      status = RankedVoteStatus.error;
    }
    _notify();
  }
}
