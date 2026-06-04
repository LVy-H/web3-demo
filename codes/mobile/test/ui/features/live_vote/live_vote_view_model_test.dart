import 'package:flutter_test/flutter_test.dart';
import 'package:tessera/data/models/relay_proof.dart';
import 'package:tessera/data/services/chain_reader.dart';
import 'package:tessera/data/services/proof_service.dart';
import 'package:tessera/data/services/relay_client.dart';
import 'package:tessera/ui/features/live_vote/live_vote_view_model.dart';

const _proof = RelayProof(
  merkleTreeDepth: 1,
  merkleTreeRoot: '0',
  nullifier: '0',
  message: '1',
  scope: '0',
  points: ['0'],
);

LiveVoteViewModel _vm() => LiveVoteViewModel(
      proof: const FakeProofService(_proof),
      relay: RelayClient(baseUrl: 'http://127.0.0.1:1'),
      reader: ChainReader(
        rpcUrl: 'http://127.0.0.1:1',
        izkPollAbiJson: '[]',
        registryAbiJson: '[]',
        anonVotingAbiJson: '[]',
        registryAddress: '0x0000000000000000000000000000000000000000',
      ),
      pollAddress: '0x2222222222222222222222222222222222222222',
    );

void main() {
  group('extractTicket', () {
    test('pulls ?t= out of a full QR URL', () {
      // Web-URL regression guard. Host is a neutral, non-owned example domain
      // (we don't pin a real tessera-owned host here).
      const url =
          'https://app.example/live/0xabc/vote?t=AAAA-bbbb_cc';
      expect(LiveVoteViewModel.extractTicket(url), 'AAAA-bbbb_cc');
    });

    test('pulls ?t= out of a tessera:// deep-link payload', () {
      // The QR is now a neutral custom-scheme payload (no web domain). The same
      // Uri.queryParameters parse works for custom schemes.
      expect(
        LiveVoteViewModel.extractTicket('tessera://live/0xabc/vote?t=TOK'),
        'TOK',
      );
    });

    test('returns a bare ticket unchanged (trimmed)', () {
      expect(LiveVoteViewModel.extractTicket('  rawticket123 '), 'rawticket123');
    });
  });

  test('join without a ticket → error stage', () async {
    final vm = _vm();
    await vm.join();
    expect(vm.stage, LiveVoteStage.error);
    expect(vm.error, isNotNull);
  });

  test('setTicket extracts and stores the ticket', () {
    final vm = _vm();
    vm.setTicket('https://x/live/0xabc/vote?t=tok42');
    expect(vm.ticket, 'tok42');
  });

  // The ballot gate: a confirmed voter can only cast once the organizer opens
  // voting (poll phase 1). Before that the relayer would reject the cast.
  test('votingOpen / votingEnded reflect the on-chain poll phase', () {
    final vm = _vm();
    expect(vm.votingOpen, isFalse, reason: 'null until first read');
    expect(vm.votingEnded, isFalse);
    vm.pollState = 0; // Registration
    expect(vm.votingOpen, isFalse);
    expect(vm.votingEnded, isFalse);
    vm.pollState = 1; // Voting
    expect(vm.votingOpen, isTrue);
    expect(vm.votingEnded, isFalse);
    vm.pollState = 2; // Ended
    expect(vm.votingOpen, isFalse);
    expect(vm.votingEnded, isTrue);
  });
}
