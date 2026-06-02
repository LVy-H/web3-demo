import 'dart:convert';

import '../../core/crypto/org_keypair.dart';
import '../../core/crypto/ticket.dart';
import '../models/pending_voter.dart';
import '../services/chain_writer.dart';
import '../services/org_key_store.dart';
import '../services/relay_client.dart';

/// Organizer (HOST) side of the live-meeting flow. Pure Dart + on-chain — no
/// Semaphore commitment derivation needed here (the organizer *receives*
/// commitments from the relayer queue). Responsibilities:
///  - a per-poll ed25519 org keypair (persisted), registered with the relayer so
///    it can verify the tickets the host mints;
///  - minting fresh signed tickets for the rotating QR;
///  - reading the pending-voter queue;
///  - confirming a voter = `registerVoter(commitment)` on-chain (owner) then
///    `redeemTicket` on the relayer;
///  - the start/end voting phase transitions.
///
/// Writes go through the dev-signer [ChainWriter]; [canHost] is false without one.
class LiveHostRepository {
  final RelayClient relay;
  final ChainWriter writer;
  final String anonAbiJson;
  final OrgKeyStore _store;

  LiveHostRepository({
    required this.relay,
    required this.writer,
    required this.anonAbiJson,
    OrgKeyStore? store,
  }) : _store = store ?? SecureOrgKeyStore();

  static const _name = 'ZkAnonVoting';

  bool get canHost => writer.canSign;
  String? get signer => writer.signerAddress;

  /// Load the per-poll org keypair (or generate + persist), and register its
  /// public key with the relayer so posted tickets verify. Idempotent.
  Future<OrgKeypair> ensureOrgKeypair(String pollId) async {
    final raw = await _store.read(pollId);
    OrgKeypair? kp =
        raw == null ? null : OrgKeypair.fromJson(jsonDecode(raw));
    if (kp == null) {
      kp = generateOrgKeypair();
      await _store.write(pollId, jsonEncode(kp.toJson()));
    }
    try {
      await relay.issueOrgKey(pollId, kp.pubKey);
    } catch (_) {
      // Best-effort: relayer may be down or the key already issued.
    }
    return kp;
  }

  /// A fresh signed ticket wire string for the rotating QR. [nowSeconds] is the
  /// current unix time (the caller supplies it so this stays testable).
  String mintTicket(String pollId, OrgKeypair kp, int nowSeconds) =>
      signTicket(createTicketPayload(pollId, nowSeconds), kp.privKey);

  Future<List<PendingVoter>> queue(String pollId) => relay.fetchQueue(pollId);

  /// Confirm a voter: register their commitment on-chain (owner-only), then mark
  /// the ticket consumed on the relayer. Returns the registration tx hash.
  Future<String> confirm(String pollId, PendingVoter voter) async {
    final hash = await writer.send(
      to: pollId,
      abiJson: anonAbiJson,
      abiName: _name,
      function: 'registerVoter',
      params: [BigInt.parse(voter.ephemeralIdentityCommitment)],
    );
    try {
      await relay.redeemTicket(pollId, voter.ticket);
    } catch (_) {
      // Registration already landed on-chain; redeem is bookkeeping.
    }
    return hash;
  }

  Future<String> startVoting(String pollId) => writer.send(
      to: pollId, abiJson: anonAbiJson, abiName: _name, function: 'startVoting');

  Future<String> endVoting(String pollId) => writer.send(
      to: pollId, abiJson: anonAbiJson, abiName: _name, function: 'endVoting');
}
