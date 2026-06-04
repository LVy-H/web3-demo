import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/crypto/confirmation_code.dart';
import '../../../core/crypto/ticket.dart';
import '../../../data/services/chain_reader.dart';
import '../../../data/services/identity_store.dart';
import '../../../data/services/proof_service.dart';
import '../../../data/services/proof_service_factory.dart';
import '../../../data/services/proximity_service.dart';
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
  final ProximityService _proximity;
  final String pollAddress;

  LiveVoteViewModel({
    required ProofService proof,
    required RelayClient relay,
    required ChainReader reader,
    required this.pollAddress,
    ProximityService proximity = const UnsupportedProximityService(),
    String? initialTicket,
    bool? canVoteOverride,
  }) : _proof = proof,
       _relay = relay,
       _reader = reader,
       _proximity = proximity,
       _canVoteOverride = canVoteOverride {
    if (initialTicket != null && initialTicket.isNotEmpty) {
      ticket = extractTicket(initialTicket);
    }
  }

  /// Test-only seam: forces [canVote] regardless of the host's global
  /// [proofServiceAvailable]. Needed because that global resolves off `dart:io`
  /// `Platform.isAndroid` (the prover availability), which is false on the
  /// Linux test host, so the ticket/scan stage would never render in a widget
  /// test. Null in production → the real global is used, behaviour unchanged.
  final bool? _canVoteOverride;

  LiveVoteStage stage = LiveVoteStage.needsTicket;
  String? ticket;
  String? _seed; // ephemeral identity (never persisted)
  String? commitment;
  String? code;
  String? error;
  String? txHash;
  List<String> options = const [];
  Timer? _poll;

  // Optional BLE proximity attestation (live-meeting anti-remote augment). Stays
  // false/silent without a radio; the face-to-face code is always the baseline.
  bool proximityChecking = false;
  bool proximityNearby = false;

  bool get canVote => _canVoteOverride ?? proofServiceAvailable;

  /// On-chain poll phase (0 = Registration, 1 = Voting, 2 = Ended); null until
  /// first read after registration. The ballot is GATED on [votingOpen]: a
  /// confirmed voter still can't cast until the organizer opens voting — the
  /// relayer would otherwise reject the cast with "Poll is not in voting phase".
  int? pollState;
  bool get votingOpen => pollState == 1;
  bool get votingEnded => pollState == 2;

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
      _attestProximity(); // background BLE "in the room" check; no-op without a radio
      _poll?.cancel(); // a re-join must not stack a second polling timer
      _poll = Timer.periodic(
        const Duration(seconds: 3),
        (_) => _checkRegistered(),
      );
    } catch (e) {
      error = e.toString();
      stage = LiveVoteStage.error;
      _notify();
    }
  }

  Future<void> _checkRegistered() async {
    try {
      // Phase 1: still waiting for the organizer to confirm us on-chain.
      if (stage == LiveVoteStage.pending) {
        final group = await _reader.getRegisteredCommitments(pollAddress);
        if (commitment == null || !group.contains(commitment)) return;
        options = await _reader.getOptions(pollAddress);
        stage = LiveVoteStage.registered;
        _notify();
      }
      // Phase 2: confirmed — keep the poll phase fresh so the ballot unlocks the
      // moment the organizer opens voting (state 1). Stop polling once voting is
      // open or already ended (nothing left to wait for).
      if (stage == LiveVoteStage.registered) {
        final s = await _reader.getState(pollAddress);
        if (s != pollState) {
          pollState = s;
          _notify();
        }
        if (votingOpen || votingEnded) _poll?.cancel();
      }
    } catch (_) {
      // transient; keep polling
    }
  }

  /// Background BLE proximity attestation: while the voter is pending, scan for
  /// the organizer's beacon so the screen can show "✓ in the room". Silent
  /// no-op where there's no radio (or the beacon isn't found) — it only ever
  /// ADDS a trust signal; the face-to-face confirmation code is the baseline.
  Future<void> _attestProximity() async {
    if (!_proximity.supported) return;
    proximityChecking = true;
    _notify();
    final r = await _proximity.attest(bleBeaconUuid(pollAddress));
    if (_disposed) return;
    proximityChecking = false;
    proximityNearby = r.verified;
    _notify();
  }

  Future<void> castVote(int option) async {
    final seed = _seed;
    if (seed == null) return;
    if (!votingOpen) return; // gated: the ballot is only enabled while voting is open
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
