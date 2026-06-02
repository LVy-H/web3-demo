import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/crypto/confirmation_code.dart';
import '../../../core/crypto/ticket.dart';
import '../../../data/services/chain_reader.dart';
import '../../../data/services/identity_store.dart';
import '../../../data/services/proof_service.dart';
import '../../../data/services/proof_service_factory.dart';
import '../../../data/services/relay_client.dart';

enum LiveVoteStage {
  needsTicket, // waiting for a ticket (scan/paste)
  joining, // deriving identity + announcing
  pending, // announced; show code; waiting for organizer to confirm
  registered, // confirmed on-chain; can vote
  proving,
  relaying,
  done,
  error,
}

/// Live-meeting VOTER flow: from a scanned/pasted ticket, mint an ephemeral
/// Semaphore identity (never persisted), show the organizer a confirmation code,
/// wait to be registered on-chain, then cast an anonymous vote. Proving +
/// commitment derivation go through [ProofService] (web, or desktop sidecar);
/// where neither is available, [canVote] is false and the UI says so.
class LiveVoteViewModel extends ChangeNotifier {
  final ProofService _proof;
  final RelayClient _relay;
  final ChainReader _reader;
  final String pollAddress;

  LiveVoteViewModel({
    required ProofService proof,
    required RelayClient relay,
    required ChainReader reader,
    required this.pollAddress,
    String? initialTicket,
  })  : _proof = proof,
        _relay = relay,
        _reader = reader {
    if (initialTicket != null && initialTicket.isNotEmpty) {
      ticket = extractTicket(initialTicket);
    }
  }

  LiveVoteStage stage = LiveVoteStage.needsTicket;
  String? ticket;
  String? _seed; // ephemeral identity (never persisted)
  String? commitment;
  String? code;
  String? error;
  String? txHash;
  List<String> options = const [];
  Timer? _poll;

  bool get canVote => proofServiceAvailable;

  bool _disposed = false;
  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Pull the raw ticket out of a scanned value: a full QR URL
  /// (`…/live/<addr>/vote?t=<ticket>`) or the bare ticket string.
  static String extractTicket(String raw) {
    final s = raw.trim();
    final uri = Uri.tryParse(s);
    final t = uri?.queryParameters['t'];
    return (t != null && t.isNotEmpty) ? t : s;
  }

  void setTicket(String raw) {
    ticket = extractTicket(raw);
    error = null;
    stage = LiveVoteStage.needsTicket;
    _notify();
  }

  Future<void> join() async {
    final t = ticket;
    if (t == null || t.isEmpty) {
      error = 'Scan or paste a ticket first.';
      stage = LiveVoteStage.error;
      _notify();
      return;
    }
    stage = LiveVoteStage.joining;
    error = null;
    _notify();
    try {
      _seed = generateIdentitySeed();
      commitment = await _proof.deriveCommitment(_seed!);
      code = confirmationCode(decodeTicket(t).n, commitment!);
      final res = await _relay.postPending(pollAddress, t, commitment!, code!);
      if (!res.ok) {
        error = res.error ?? 'The relayer rejected this ticket.';
        stage = LiveVoteStage.error;
        _notify();
        return;
      }
      stage = LiveVoteStage.pending;
      _notify();
      _poll?.cancel(); // a re-join must not stack a second polling timer
      _poll = Timer.periodic(
          const Duration(seconds: 3), (_) => _checkRegistered());
    } catch (e) {
      error = e.toString();
      stage = LiveVoteStage.error;
      _notify();
    }
  }

  Future<void> _checkRegistered() async {
    try {
      final group = await _reader.getRegisteredCommitments(pollAddress);
      if (commitment != null && group.contains(commitment)) {
        _poll?.cancel();
        options = await _reader.getOptions(pollAddress);
        stage = LiveVoteStage.registered;
        _notify();
      }
    } catch (_) {
      // transient; keep polling
    }
  }

  Future<void> castVote(int option) async {
    final seed = _seed;
    if (seed == null) return;
    stage = LiveVoteStage.proving;
    error = null;
    _notify();
    try {
      final group = await _reader.getRegisteredCommitments(pollAddress);
      final proof = await _proof.generateVoteProof(
        identitySeed: seed,
        memberCommitments: group,
        message: option,
        scope: pollAddress,
      );
      stage = LiveVoteStage.relaying;
      _notify();
      final res = await _relay.relayVote(pollAddress, option, proof);
      if (res.success) {
        txHash = res.txHash;
        stage = LiveVoteStage.done;
      } else {
        error = res.error ?? 'Relay failed';
        stage = LiveVoteStage.error;
      }
    } catch (e) {
      error = e.toString();
      stage = LiveVoteStage.error;
    }
    _notify();
  }
}
