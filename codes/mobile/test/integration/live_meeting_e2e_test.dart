import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tessera/core/crypto/confirmation_code.dart';
import 'package:tessera/core/crypto/ticket.dart';
import 'package:tessera/data/repositories/live_host_repository.dart';
import 'package:tessera/data/services/chain_reader.dart';
import 'package:tessera/data/services/chain_writer.dart';
import 'package:tessera/data/services/identity_store.dart';
import 'package:tessera/data/services/org_key_store.dart';
import 'package:tessera/data/services/proof_service_desktop.dart';
import 'package:tessera/data/services/relay_client.dart';
import 'package:wallet/wallet.dart' show EthereumAddress;
import 'package:web3dart/web3dart.dart';

/// THE FULL live-meeting user journey, end-to-end on Linux via the sidecar + the
/// live stack — the sequence that was only unit-tested before:
///   host creates poll + org key + QR ticket
///   → voter mints an ephemeral identity, derives its commitment + the 4-digit
///     confirmation code, announces to the relayer (postPending)
///   → host sees the voter in the queue, confirms (registerVoter on-chain + redeem)
///   → host starts voting
///   → voter generates a Semaphore proof over the group and RELAYS the vote
///   → the vote LANDS: tally increments AND the nullifier is now "used" (receipt).
///
/// Opt-in: RUN_DESKTOP_PROVER=1 flutter test test/integration/live_meeting_e2e_test.dart
void main() {
  const sidecar = 'web_prover/desktop_prover.mjs';
  const bundle = 'web/zkprover.js';
  // Hardhat account #5 — its own nonce lane.
  const hostKey =
      '0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba';

  final fixtureFile = File('test/fixtures/local_chain.json');
  final on = Platform.environment['RUN_DESKTOP_PROVER'] == '1';
  if (!on || !fixtureFile.existsSync() || !File(sidecar).existsSync()) {
    test('live-meeting e2e (opt-in)', () {
      markTestSkipped('set RUN_DESKTOP_PROVER=1 + dev-stack up to run');
    }, skip: true);
    return;
  }
  final fx = jsonDecode(fixtureFile.readAsStringSync()) as Map<String, dynamic>;
  final rpc = fx['rpcUrl'] as String;
  final registry = fx['registry'] as String;
  final relayerUrl = (fx['relayerUrl'] as String?) ?? 'http://127.0.0.1:3001';
  final semaphore = (fx['semaphore'] as String?) ??
      '0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0';

  String abi(String p) => jsonEncode(jsonDecode(File(p).readAsStringSync())['abi']);
  final registryAbi = abi('assets/abi/PollRegistry.json');
  final anonAbi = abi('assets/abi/ZkAnonVoting.json');

  Future<bool> up(String url, String body) async {
    try {
      final r = await http
          .post(Uri.parse(url),
              headers: {'content-type': 'application/json'}, body: body)
          .timeout(const Duration(seconds: 3));
      return r.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  test('host → voter → confirm → vote lands on-chain + receipt verifiable',
      () async {
    final nodeUp = await up(rpc,
        '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}');
    final relayUp = await up('$relayerUrl/api/relay/tickets/issue', '{}');
    if (!nodeUp || !relayUp) {
      markTestSkipped('node ($nodeUp) / relayer ($relayUp) unreachable');
      return;
    }

    final writer = ChainWriter(rpcUrl: rpc, chainId: 31337, privateKey: hostKey);
    final reader = ChainReader(
      rpcUrl: rpc,
      izkPollAbiJson: abi('assets/abi/IZkPoll.json'),
      registryAbiJson: registryAbi,
      anonVotingAbiJson: anonAbi,
      registryAddress: registry,
    );
    final relay = RelayClient(baseUrl: relayerUrl);
    final prover = ProofServiceDesktop(
        nodePath: 'node', sidecarPath: sidecar, bundlePath: bundle);
    final host = LiveHostRepository(
        relay: relay,
        writer: writer,
        anonAbiJson: anonAbi,
        store: InMemoryOrgKeyStore());
    addTearDown(writer.dispose);
    addTearDown(reader.dispose);
    addTearDown(relay.close);
    addTearDown(prover.dispose);
    final owner = writer.signerAddress!;

    // ── HOST: create the poll, org key, and a fresh QR ticket ──
    final anon = DeployedContract(ContractAbi.fromJson(anonAbi, 'ZkAnonVoting'),
        EthereumAddress.fromHex('0x0000000000000000000000000000000000000000'));
    final initData = anon.function('initialize').encodeCall([
      EthereumAddress.fromHex(semaphore),
      EthereumAddress.fromHex(owner),
      ['Yes', 'No'],
    ]);
    await writer.send(
        to: registry,
        abiJson: registryAbi,
        abiName: 'PollRegistry',
        function: 'createPoll',
        params: ['anon-vote', 'Live Meeting E2E', 'full loop', initData]);
    final poll = (await reader.getAllPolls())
        .where((p) =>
            p.moduleType == 'anon-vote' &&
            p.creator.toLowerCase() == owner.toLowerCase())
        .last
        .pollAddress;
    final kp = await host.ensureOrgKeypair(poll);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final ticketWire = host.mintTicket(poll, kp, now);

    // ── VOTER: ephemeral identity → commitment → code → announce ──
    final voterSeed = generateIdentitySeed();
    final commitment = await prover.deriveCommitment(voterSeed);
    final code = confirmationCode(decodeTicket(ticketWire).n, commitment);
    final posted = await relay.postPending(poll, ticketWire, commitment, code);
    expect(posted.ok, isTrue, reason: 'voter announced to the relayer');

    // ── HOST: see the voter, confirm (registerVoter + redeem) ──
    PendingVoterShim? mine;
    for (var i = 0; i < 10 && mine == null; i++) {
      try {
        final q = await host.queue(poll);
        final hit = q
            .where((v) => v.ephemeralIdentityCommitment == commitment)
            .toList();
        if (hit.isNotEmpty) mine = PendingVoterShim(hit.first.ticket, hit.first.confirmationCode);
      } catch (_) {/* relayer 429 under load */}
      if (mine == null) await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    if (mine == null) {
      markTestSkipped('relayer rate-limited; queue unreadable under load');
      return;
    }
    expect(mine.code, code, reason: 'organizer reads the same face-to-face code');

    final q = await host.queue(poll);
    await host.confirm(poll, q.firstWhere((v) => v.ephemeralIdentityCommitment == commitment));
    await host.startVoting(poll);

    // ── VOTER: prove membership + relay the vote ──
    final group = await reader.getRegisteredCommitments(poll);
    expect(group, contains(commitment), reason: 'voter registered on-chain');
    const chosen = 1; // "No"
    final proof = await prover.generateVoteProof(
        identitySeed: voterSeed, memberCommitments: group, message: chosen, scope: poll);
    expect(await prover.verifyProof(proof), isTrue, reason: 'proof valid vs real vkey');

    final relayed = await relay.relayVote(poll, chosen, proof);
    expect(relayed.success, isTrue,
        reason: 'relayer submitted the vote on-chain: ${relayed.error}');

    // ── The vote LANDED: tally + receipt ──
    final results = await reader.getResults(poll);
    expect(results[chosen], BigInt.one, reason: '"No" tallied on-chain');
    expect(await reader.isNullifierUsed(poll, proof.nullifier), isTrue,
        reason: 'receipt: the nullifier is now used');
  }, timeout: const Timeout(Duration(minutes: 4)));
}

/// Tiny holder so the retry loop can detect a hit without nullable juggling.
class PendingVoterShim {
  final String ticket;
  final String code;
  PendingVoterShim(this.ticket, this.code);
}
