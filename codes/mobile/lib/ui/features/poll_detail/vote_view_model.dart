import 'package:flutter/foundation.dart';

import '../../../data/repositories/poll_repository.dart';
import '../../../data/services/proof_service.dart';
import '../../../data/services/relay_client.dart';

enum VoteStatus { idle, proving, relaying, success, error }

/// Casts an anonymous vote: reconstruct the group → generate a Semaphore proof
/// (client-side, via [ProofService]) → relay it gaslessly. Ties together the
/// pieces verified separately (group reconstruction, in-browser proving, relay
/// client). Only used where proving is available (web now; mobile later).
class VoteViewModel extends ChangeNotifier {
  final PollRepository _repo;
  final ProofService _proofService;
  final RelayClient _relay;
  final String pollAddress;

  VoteViewModel({
    required PollRepository repository,
    required ProofService proofService,
    required RelayClient relayClient,
    required this.pollAddress,
  })  : _repo = repository,
        _proofService = proofService,
        _relay = relayClient;

  VoteStatus status = VoteStatus.idle;
  String? error;
  String? txHash;

  // Proactive registration status for the entered identity, so the voter sees
  // they aren't a member BEFORE casting (instead of the post-cast "leaf -1").
  String? myCommitment;
  bool? isRegistered; // null = unknown / check failed
  bool checkingRegistration = false;

  bool get isBusy =>
      status == VoteStatus.proving || status == VoteStatus.relaying;

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
    try {
      myCommitment = await _proofService.deriveCommitment(identitySeed);
      final group = await _repo.fetchGroup(pollAddress);
      isRegistered = group.contains(myCommitment);
    } catch (_) {
      isRegistered = null;
    } finally {
      checkingRegistration = false;
      _notify();
    }
  }

  Future<void> castVote({
    required String identitySeed,
    required int optionIndex,
  }) async {
    error = null;
    txHash = null;
    status = VoteStatus.proving;
    _notify();
    try {
      final group = await _repo.fetchGroup(pollAddress);
      // Membership pre-check: proving over a group you're not a member of fails
      // deep in Semaphore with a cryptic "leaf at index -1". Surface a clear
      // message instead (you can only vote anonymously once registered).
      final commitment = await _proofService.deriveCommitment(identitySeed);
      if (!group.contains(commitment)) {
        error = "This identity isn't registered in this poll yet. Ask the "
            "organizer to confirm you (scan the live-meeting QR), or have your "
            "commitment registered first.";
        status = VoteStatus.error;
        _notify();
        return;
      }
      final proof = await _proofService.generateVoteProof(
        identitySeed: identitySeed,
        memberCommitments: group,
        message: optionIndex,
        scope: pollAddress,
      );
      status = VoteStatus.relaying;
      _notify();
      final result = await _relay.relayVote(pollAddress, optionIndex, proof);
      if (result.success) {
        txHash = result.txHash;
        status = VoteStatus.success;
      } else {
        error = result.error ?? 'Relay failed';
        status = VoteStatus.error;
      }
    } catch (e) {
      error = e.toString();
      status = VoteStatus.error;
    }
    _notify();
  }
}
