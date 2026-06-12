/// Production [LiveHostPort] — the wallet-free run-event console backend.
///
/// vs the legacy `LiveHostRepository` (dev-signer required to host at all):
/// - **Admitting is sponsored.** Confirming a voter registers their
///   commitment through the relayer's `register-voter` (the relayer owns
///   sponsored polls), then redeems the ticket — no private key on the host
///   device.
/// - **Start voting is sponsored** via the relayer lifecycle route, with the
///   dev-signer as the dev-poll fallback.
/// - **Session setup is honest.** The legacy flow swallowed a failed org-key
///   registration and minted tickets no voter could redeem; here a failed
///   `issueOrgKey` fails the load into the journey's typed error state with
///   retry.
library;

import 'dart:convert';

import 'package:core_chain/chain_reader.dart';
import 'package:core_chain/chain_writer.dart';
import 'package:core_crypto/crypto/org_keypair.dart';
import 'package:core_crypto/crypto/ticket.dart';
import 'package:core_domain/journeys/live_journeys.dart';
import 'package:core_domain/models/pending_voter.dart';
import 'package:core_relay/relay_client.dart';
import 'package:core_storage/org_key_store.dart';

import 'organize_gateway.dart';

class RelayLiveHostPort implements LiveHostPort {
  final RelayClient relay;
  final ChainReader reader;
  final OrgKeyStore orgKeys;
  final OrganizeRelayGateway gateway;
  final String pollAddress;

  /// Dev-signer fallback for phase actions on dev-created polls.
  final ChainWriter? writer;
  final String? writerAbiJson;

  /// Clock seam (unix seconds) so ticket minting is testable.
  final int Function() nowSeconds;

  OrgKeypair? _keypair;
  int _lastTurnout = 0;

  /// Last queue snapshot, keyed by confirmation code — [confirmVoter]
  /// receives only the code the host read off the voter's screen.
  final Map<String, PendingVoter> _pendingByCode = {};

  RelayLiveHostPort({
    required this.relay,
    required this.reader,
    required this.orgKeys,
    required this.gateway,
    required this.pollAddress,
    this.writer,
    this.writerAbiJson,
    int Function()? nowSeconds,
  }) : nowSeconds =
           nowSeconds ?? (() => DateTime.now().millisecondsSinceEpoch ~/ 1000);

  static const _writerAbiName = 'ZkApprovalVoting';

  @override
  Future<void> loadSession() async {
    var keypair = _keypair;
    if (keypair == null) {
      final raw = await orgKeys.read(pollAddress);
      keypair = raw == null ? null : OrgKeypair.fromJson(jsonDecode(raw));
      if (keypair == null) {
        keypair = generateOrgKeypair();
        await orgKeys.write(pollAddress, jsonEncode(keypair.toJson()));
      }
      _keypair = keypair;
    }
    // NOT best-effort: tickets minted against an unregistered key can never
    // be redeemed, so a failed registration must fail the load (typed
    // journey error with retry), not silently produce a dead QR.
    await relay.issueOrgKey(pollAddress, keypair.pubKey);
  }

  @override
  Future<String> rotateTicket() async {
    final keypair = _keypair;
    if (keypair == null) {
      throw StateError('rotateTicket before loadSession');
    }
    final wire = signTicket(
      createTicketPayload(pollAddress, nowSeconds()),
      keypair.privKey,
    );
    // The same deep-link payload the legacy host minted; the JOIN grammar
    // reads it back as a live-vote target.
    return 'tessera://live/$pollAddress/vote?t=$wire';
  }

  @override
  Future<AdmitQueue> fetchQueue() async {
    final voters = await relay.fetchQueue(pollAddress);
    _pendingByCode.clear();
    final pending = <PendingLiveVoter>[];
    var admitted = 0;
    for (final voter in voters) {
      if (voter.status == 'confirmed') {
        admitted++;
      } else if (voter.status == 'pending') {
        _pendingByCode[voter.confirmationCode] = voter;
        pending.add(
          PendingLiveVoter(
            commitment: voter.ephemeralIdentityCommitment,
            confirmationCode: voter.confirmationCode,
          ),
        );
      }
    }
    try {
      final results = await reader.getResults(pollAddress);
      _lastTurnout = results.fold<BigInt>(BigInt.zero, (a, b) => a + b).toInt();
    } catch (_) {
      // Keep the last turnout over failing the whole heartbeat.
    }
    return AdmitQueue(
      pending: pending,
      admitted: admitted,
      turnout: _lastTurnout,
    );
  }

  @override
  Future<AdmitQueue> confirmVoter(String confirmationCode) async {
    final voter = _pendingByCode[confirmationCode];
    if (voter == null) {
      throw const OrganizeWireException(
        'That code isn’t in the waiting list any more — ask the voter to '
        'scan again.',
      );
    }
    final result = await relay.registerVoter(
      pollAddress,
      voter.ephemeralIdentityCommitment,
    );
    if (!result.ok) {
      throw OrganizeWireException(
        result.error ?? 'That voter could not be admitted. Try again.',
      );
    }
    try {
      await relay.redeemTicket(pollAddress, voter.ticket);
    } catch (_) {
      // The registration landed; redeeming is relayer bookkeeping.
    }
    return fetchQueue();
  }

  @override
  Future<void> startVoting() async {
    try {
      await gateway.startVoting(pollAddress);
    } on Object {
      final w = writer;
      if (w == null || !w.canSign || writerAbiJson == null) rethrow;
      await w.send(
        to: pollAddress,
        abiJson: writerAbiJson!,
        abiName: _writerAbiName,
        function: 'startVoting',
      );
    }
  }

  @override
  Future<void> close() async {
    final w = writer;
    if (w != null && w.canSign && writerAbiJson != null) {
      await w.send(
        to: pollAddress,
        abiJson: writerAbiJson!,
        abiName: _writerAbiName,
        function: 'endVoting',
      );
      return;
    }
    await gateway.endVoting(pollAddress);
  }
}
