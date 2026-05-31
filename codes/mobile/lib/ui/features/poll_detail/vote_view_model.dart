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

  bool get isBusy =>
      status == VoteStatus.proving || status == VoteStatus.relaying;

  Future<void> castVote({
    required String identitySeed,
    required int optionIndex,
  }) async {
    error = null;
    txHash = null;
    status = VoteStatus.proving;
    notifyListeners();
    try {
      final group = await _repo.fetchGroup(pollAddress);
      final proof = await _proofService.generateVoteProof(
        identitySeed: identitySeed,
        memberCommitments: group,
        message: optionIndex,
        scope: pollAddress,
      );
      status = VoteStatus.relaying;
      notifyListeners();
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
    notifyListeners();
  }
}
