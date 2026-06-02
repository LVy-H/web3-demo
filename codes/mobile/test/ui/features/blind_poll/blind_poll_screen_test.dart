import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tessera/data/models/blind_snapshot.dart';
import 'package:tessera/data/repositories/blind_repository.dart';
import 'package:tessera/data/services/blind_commit_store.dart';
import 'package:tessera/data/services/chain_reader.dart';
import 'package:tessera/data/services/chain_writer.dart';
import 'package:tessera/ui/features/blind_poll/blind_poll_screen.dart';
import 'package:tessera/ui/features/blind_poll/blind_poll_view_model.dart';

const _owner = '0x1111111111111111111111111111111111111111';
const _poll = '0x2222222222222222222222222222222222222222';

/// A BlindRepository that serves a canned snapshot — no network. The signer is
/// the owner so both voter and owner actions render.
class _FakeBlindRepo extends BlindRepository {
  final BlindSnapshot snap;
  _FakeBlindRepo(this.snap)
      : super(
          reader: ChainReader(
            rpcUrl: 'http://127.0.0.1:1',
            izkPollAbiJson: '[]',
            registryAbiJson: '[]',
            anonVotingAbiJson: '[]',
            registryAddress: '0x0000000000000000000000000000000000000000',
          ),
          writer: ChainWriter(rpcUrl: 'http://127.0.0.1:1', chainId: 31337),
          commits: InMemoryBlindCommitStore(),
          blindAbiJson: '[]',
        );
  @override
  bool get canWrite => true;
  @override
  String? get signer => _owner;
  @override
  Future<BlindSnapshot> fetch(String poll) async => snap;
  @override
  Future<bool> hasSavedCommit(String poll) async => false;
}

BlindSnapshot _snap({
  required int state,
  bool registered = false,
  bool committed = false,
  bool revealed = false,
}) =>
    BlindSnapshot(
      address: _poll,
      state: state,
      options: const ['Yes', 'No', 'Abstain'],
      results: [BigInt.zero, BigInt.one, BigInt.zero],
      participantCount: BigInt.from(2),
      owner: _owner,
      revealDeadline: BigInt.zero,
      finalized: false,
      registered: registered,
      committed: committed,
      revealed: revealed,
    );

Widget _host(BlindSnapshot snap) => ChangeNotifierProvider(
      create: (_) => BlindPollViewModel(_FakeBlindRepo(snap), _poll),
      child: const MaterialApp(home: BlindPollScreen(address: _poll)),
    );

void main() {
  testWidgets('Registration phase: register + owner start-voting render',
      (tester) async {
    await tester.pumpWidget(_host(_snap(state: 0)));
    await tester.pumpAndSettle();

    expect(find.text('BLIND · COMMIT-REVEAL'), findsOneWidget);
    expect(find.text('REVEALED TALLY'), findsOneWidget);
    expect(find.text('REGISTER TO VOTE'), findsOneWidget);
    expect(find.text('START VOTING (OWNER)'), findsOneWidget);
  });

  testWidgets('Voting phase (registered, not committed) shows options + commit',
      (tester) async {
    await tester.pumpWidget(_host(_snap(state: 1, registered: true)));
    await tester.pumpAndSettle();

    expect(find.text('COMMIT VOTE'), findsOneWidget);
    // 'Yes' appears in both the tally bar and the selectable option tile.
    expect(find.text('Yes'), findsWidgets);
    expect(find.byIcon(Icons.radio_button_unchecked), findsNWidgets(3));
    expect(find.text('END VOTING (OWNER)'), findsOneWidget);
  });

  testWidgets('Ended phase (committed) offers reveal', (tester) async {
    await tester.pumpWidget(
        _host(_snap(state: 2, registered: true, committed: true)));
    await tester.pumpAndSettle();

    // No saved salt on this device -> guidance instead of a reveal button.
    expect(find.textContaining('no saved salt'), findsOneWidget);
  });
}
