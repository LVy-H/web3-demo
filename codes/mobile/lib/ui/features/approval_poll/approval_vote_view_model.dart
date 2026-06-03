import 'package:flutter/foundation.dart';

import '../../../data/models/poll_snapshot.dart';
import '../../../data/repositories/approval_repository.dart';
import '../../../data/services/proof_service.dart';
import '../../../data/services/relay_client.dart';
import '../../core/view_state.dart';

enum ApprovalVoteStatus { idle, proving, relaying, success, error }

/// Drives the M3 approval-vote surface: loads the poll snapshot, runs the same
/// up-front registration pre-check as M1, and casts an APPROVAL ballot — a
/// bitmask (bit i set ⇒ option i approved) bound into the Semaphore proof's
/// `message` and relayed gaslessly via `/api/relay/approval-vote`.
///
/// This is a sibling of M1 [VoteViewModel]: same group reconstruction, same
/// client-side proving, same relay. The only difference is the ballot shape (a
/// bitmask instead of a single option index) and the relay endpoint. The
/// registration token pattern is copied verbatim — a late result from a
/// superseded check must never resurrect/overwrite newer state.
class ApprovalVoteViewModel extends ChangeNotifier {
  final ApprovalRepository _repo;
  final ProofService _proofService;
  final RelayClient _relay;
  final String pollAddress;

  ApprovalVoteViewModel({
    required ApprovalRepository repository,
    required ProofService proofService,
    required RelayClient relayClient,
    required this.pollAddress,
  }) : _repo = repository,
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
  ApprovalVoteStatus status = ApprovalVoteStatus.idle;
  String? castError;
  String? txHash;

  bool get isBusy =>
      status == ApprovalVoteStatus.proving ||
      status == ApprovalVoteStatus.relaying;

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

  /// Compute the ballot bitmask for the given set of approved option indices.
  /// `Σ over approved i of (1 << i)`, with ≤32 options (contract `MAX_OPTIONS`).
  ///
  /// Built with [BigInt] so the shift never truncates: on Flutter web (dart2js)
  /// the native `int` `<<` is a 32-bit-signed operation, so `1 << 31` overflows
  /// to a negative value and corrupts the mask bound into the Semaphore proof.
  /// BigInt has no such truncation, so this is correct on every target. The
  /// largest possible result — all 32 bits set — is `2^32 - 1 = 4294967295`,
  /// well inside JS `Number`'s 53-bit integer range, so the final [BigInt.toInt]
  /// is exact on web.
  static int bitmaskFor(Iterable<int> approvedIndices) {
    var mask = BigInt.zero;
    for (final i in approvedIndices) {
      mask |= BigInt.one << i;
    }
    return mask.toInt();
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

  /// Cast an approval ballot. [approvedIndices] is the set of options the voter
  /// approves; an empty set is rejected up-front (the contract's `EmptyBallot`).
  Future<void> castApproval({
    required String identitySeed,
    required Set<int> approvedIndices,
  }) async {
    castError = null;
    txHash = null;
    if (approvedIndices.isEmpty) {
      // Mirror the contract's EmptyBallot guard — never relay an empty mask.
      castError = 'Select at least one option to approve.';
      status = ApprovalVoteStatus.error;
      _notify();
      return;
    }
    final bitmask = bitmaskFor(approvedIndices);
    status = ApprovalVoteStatus.proving;
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
        status = ApprovalVoteStatus.error;
        _notify();
        return;
      }
      // The bitmask is the proof's `message` — the relayer/contract reject
      // unless `message == bitmask`, binding the ballot to the proof so no one
      // can alter which options were approved without invalidating the SNARK.
      final proof = await _proofService.generateVoteProof(
        identitySeed: identitySeed,
        memberCommitments: group,
        message: bitmask,
        scope: pollAddress,
      );
      status = ApprovalVoteStatus.relaying;
      _notify();
      final result = await _relay.relayApprovalVote(
        pollAddress,
        bitmask,
        proof,
      );
      if (result.success) {
        txHash = result.txHash;
        status = ApprovalVoteStatus.success;
      } else {
        castError = result.error ?? 'Relay failed';
        status = ApprovalVoteStatus.error;
      }
    } catch (e) {
      castError = e.toString();
      status = ApprovalVoteStatus.error;
    }
    _notify();
  }
}
