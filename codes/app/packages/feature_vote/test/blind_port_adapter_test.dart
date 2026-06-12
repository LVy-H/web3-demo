// The production BlindJourneyPort: snapshot mapping, salt persisted BEFORE
// the commit lands, reveal from the stored salt, deadline decode.
import 'package:core_crypto/crypto/blind_commit.dart';
import 'package:core_storage/blind_commit_store.dart';
import 'package:feature_vote/feature_vote.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  late FakeChainReader reader;
  late FakeChainWriter writer;
  late InMemoryBlindCommitStore commits;
  late InMemoryKnownPollsStore knownPolls;

  BlindPortAdapter adapter() => BlindPortAdapter(
    reader: reader,
    writer: writer,
    commitStore: commits,
    pollAddress: testPollAddress,
    blindAbiJson: '[]',
    knownPolls: knownPolls,
    pollTitle: 'Blind poll',
  );

  setUp(() {
    reader = FakeChainReader();
    writer = FakeChainWriter();
    commits = InMemoryBlindCommitStore();
    knownPolls = InMemoryKnownPollsStore();
  });

  test('fetchState maps the chain reads for the signer', () async {
    reader
      ..state = 2
      ..registered = true
      ..committed = true;
    final snap = await adapter().fetchState();
    expect(snap.phase, 2);
    expect(snap.registered, isTrue);
    expect(snap.committed, isTrue);
    expect(snap.revealed, isFalse);
    expect(snap.finalized, isFalse);
  });

  test('without a signer every per-voter flag reads false', () async {
    writer = FakeChainWriter(withSigner: false);
    reader.registered = true; // would be true for SOME signer, not none
    final snap = await adapter().fetchState();
    expect(snap.registered, isFalse);
    expect(snap.committed, isFalse);
  });

  test('register sends the tx and records the join locally', () async {
    await adapter().register();
    expect(writer.sends.single.$1, 'register');
    expect(
      (await knownPolls.find(testPollAddress))!.stage,
      KnownPollStage.joined,
    );
  });

  test(
    'commit stores the salt FIRST, sends the hash, returns receipt',
    () async {
      final receipt = await adapter().commit(1);

      expect(receipt.optionIndex, 1);
      final saved = (await commits.read(testPollAddress))!;
      expect(saved.saltHex, receipt.saltHex);
      expect(saved.optionIndex, 1);

      final (function, params) = writer.sends.single;
      expect(function, 'commitVote');
      // The sent hash is exactly the contract's keccak(option ‖ salt).
      expect(params.single, blindCommitHash(1, fromHex(receipt.saltHex)));
      expect(await adapter().hasSalt(), isTrue);
      expect(
        (await knownPolls.find(testPollAddress))!.stage,
        KnownPollStage.committed,
      );
    },
  );

  test('reveal replays the stored option + salt', () async {
    final receipt = await adapter().commit(2);
    writer.sends.clear();

    await adapter().reveal();
    final (function, params) = writer.sends.single;
    expect(function, 'revealVote');
    expect(params[0], BigInt.from(2));
    expect(params[1], fromHex(receipt.saltHex));
    expect(
      (await knownPolls.find(testPollAddress))!.stage,
      KnownPollStage.voted,
    );
  });

  test('reveal without a stored salt is a StateError, never a blind tx', () {
    expect(() => adapter().reveal(), throwsStateError);
    expect(writer.sends, isEmpty);
  });

  test('fetchRevealDeadline decodes unix seconds', () async {
    reader.revealDeadline = BigInt.from(1750000000);
    final deadline = await adapter().fetchRevealDeadline();
    expect(deadline.millisecondsSinceEpoch, 1750000000 * 1000);
  });
}
