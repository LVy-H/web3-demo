/// Production [LiveVoterPort]: the live-voter journey's effect boundary,
/// implemented over core_relay (announce / queue), core_crypto (ticket
/// decode, confirmation code, proof generation) and injected chain reads.
///
/// Pure Dart (no Flutter imports) so it tests under plain `dart test`
/// alongside the grammar. Chain reads arrive as narrow function injections
/// (group / options / phase) instead of a core_chain dependency — the app
/// shell wires them from its ChainReader; tests hand in closures.
///
/// PRIVACY: the ephemeral identity seed is minted HERE, kept in a private
/// map keyed by commitment, and never crosses the port boundary, exactly as
/// the [LiveVoterPort] contract requires. It dies with this object — a live
/// session's identity is never persisted anywhere.
library;

import 'dart:math';

import 'package:core_crypto/crypto/confirmation_code.dart';
import 'package:core_crypto/crypto/ticket.dart';
import 'package:core_crypto/proof/proof_service.dart';
import 'package:core_domain/journeys/live_journeys.dart';
import 'package:core_domain/models/relay_proof.dart';
import 'package:core_relay/relay_client.dart';

/// Reads the poll's registered commitments (decimal strings) on-chain.
typedef FetchGroup = Future<List<String>> Function(String pollAddress);

/// Reads the poll's ballot options on-chain.
typedef FetchOptions = Future<List<String>> Function(String pollAddress);

/// Reads the poll's phase on-chain (0 = Registration, 1 = Voting, 2 = Ended).
typedef FetchPhase = Future<int> Function(String pollAddress);

/// A fresh 32-byte ephemeral seed as 0x-hex. Local on purpose: the seed is
/// never persisted, so pulling core_storage (and its flutter_secure_storage
/// import) into this pure-Dart graph for its `generateIdentitySeed` would
/// buy nothing and break `dart test`.
String _randomSeedHex([Random? rng]) {
  final r = rng ?? Random.secure();
  final bytes = List<int>.generate(32, (_) => r.nextInt(256));
  return '0x${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
}

class RelayLiveVoterPort implements LiveVoterPort {
  final String pollAddress;
  final RelayClient relay;
  final ProofService proofService;
  final FetchGroup fetchGroup;
  final FetchOptions fetchOptions;
  final FetchPhase fetchPhase;

  /// Test seam for deterministic seeds; production uses [Random.secure].
  final String Function() mintSeed;

  /// Ephemeral seeds by commitment — never exposed, never persisted.
  final Map<String, String> _seeds = {};

  /// The commitment of the most recent announce, for [hostAlive]'s queue
  /// lookup. Null until the first successful announce.
  String? _lastCommitment;

  RelayLiveVoterPort({
    required this.pollAddress,
    required this.relay,
    required this.proofService,
    required this.fetchGroup,
    required this.fetchOptions,
    required this.fetchPhase,
    String Function()? mintSeed,
  }) : mintSeed = mintSeed ?? _randomSeedHex;

  String get _poll => pollAddress.toLowerCase();

  @override
  Future<LiveTicket> parseTicket(String raw) async {
    final s = raw.trim();
    // A scanned deep link (`…/live/<addr>/vote?t=<wire>`) carries the wire
    // in `?t=`; anything else is treated as the bare wire itself — the
    // exact legacy extraction, so every QR in the wild keeps working.
    final t = Uri.tryParse(s)?.queryParameters['t'];
    final wire = (t != null && t.isNotEmpty) ? t : s;
    // Structural validation: decodeTicket throws on malformed input — the
    // machine maps that throw to LiveVoterJoinFailed.
    final ticket = decodeTicket(wire);
    if (ticket.p.toLowerCase() != _poll) {
      throw const TicketSessionMismatch();
    }
    return LiveTicket(wire);
  }

  @override
  Future<LiveAnnouncement> announce(LiveTicket ticket) async {
    final decoded = decodeTicket(ticket.wire);
    final seed = mintSeed();
    final commitment = await proofService.deriveCommitment(seed);
    final code = confirmationCode(decoded.n, commitment);
    final res = await relay.postPending(_poll, ticket.wire, commitment, code);
    if (!res.ok) {
      throw RelayException(
        res.error ?? 'the relayer rejected this ticket (HTTP ${res.status})',
      );
    }
    _seeds[commitment] = seed;
    _lastCommitment = commitment;
    return LiveAnnouncement(commitment: commitment, confirmationCode: code);
  }

  @override
  Future<LiveAdmission?> pollAdmission(LiveAnnouncement announcement) async {
    // Admission truth is ON-CHAIN: the host's confirm registers the
    // commitment in the poll's group (same check the legacy voter used).
    final group = await fetchGroup(_poll);
    if (!group.contains(announcement.commitment)) return null;
    final options = await fetchOptions(_poll);
    final phase = await fetchPhase(_poll);
    return LiveAdmission(options: options, phase: phase);
  }

  /// Host-liveness, approximated from the relayer's queue endpoint.
  ///
  /// DOCUMENTED CHOICE: the relayer has no dedicated host-heartbeat
  /// endpoint yet, and the host's rotating tickets are only visible on the
  /// host's screen. What the voter CAN observe is the queue
  /// (`GET /api/relay/tickets/queue`) — the host console's working surface,
  /// where our announced entry lives with a status the HOST controls
  /// ('pending' | 'confirmed' | 'rejected'). So:
  ///   - our entry present and not rejected → the session still knows us
  ///     → `true`;
  ///   - our entry REJECTED or VANISHED (host cleared the session, relayer
  ///     restarted) → definitively dropped → `false` (→ stalled, with
  ///     retry/rescan/leave);
  ///   - transient probe errors THROW, per the port contract — the machine
  ///     keeps waiting, still bounded by its pending timeout.
  /// A host that simply walks away while our entry sits 'pending' is caught
  /// by the machine's pendingTimeout, not by this probe.
  @override
  Future<bool> hostAlive() async {
    final commitment = _lastCommitment;
    if (commitment == null) return true; // nothing announced — nothing to lose
    final queue = await relay.fetchQueue(_poll); // throws on probe failure
    for (final voter in queue) {
      if (voter.ephemeralIdentityCommitment == commitment) {
        return voter.status != 'rejected';
      }
    }
    return false;
  }

  @override
  Future<Object> generateProof(
    LiveAnnouncement announcement,
    int option,
  ) async {
    final seed = _seeds[announcement.commitment];
    if (seed == null) {
      throw StateError('no ephemeral identity for this announcement');
    }
    final group = await fetchGroup(_poll);
    return proofService.generateVoteProof(
      identitySeed: seed,
      memberCommitments: group,
      message: option,
      scope: _poll,
    );
  }

  @override
  Future<String> relayBallot(int option, Object proof) async {
    final res = await relay.relayVote(_poll, option, proof as RelayProof);
    if (!res.success) {
      throw RelayException(res.error ?? 'the vote could not be sent');
    }
    return res.txHash ?? '';
  }
}

/// The scanned ticket belongs to a DIFFERENT live session than the one this
/// screen was opened for — joining would strand the voter in the wrong
/// room, so it is rejected at parse time (→ LiveVoterJoinFailed).
final class TicketSessionMismatch implements Exception {
  const TicketSessionMismatch();

  @override
  String toString() => 'ticket was issued for a different live session';
}
