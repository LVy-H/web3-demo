import 'package:feature_vote/feature_vote.dart';
import 'package:flutter_test/flutter_test.dart';

KnownPoll poll(
  String address, {
  KnownPollStage stage = KnownPollStage.joined,
  String title = 'T',
  int joinedAtMs = 1,
  String? receiptCode,
}) => KnownPoll(
  address: address,
  title: title,
  moduleType: 'anon-vote',
  stage: stage,
  joinedAtMs: joinedAtMs,
  receiptCode: receiptCode,
);

void main() {
  test(
    'upsert keys by lowercased address and keeps newest-first order',
    () async {
      final store = InMemoryKnownPollsStore();
      await store.upsert(poll('0xAAA', joinedAtMs: 1));
      await store.upsert(poll('0xBBB', joinedAtMs: 2));
      await store.upsert(poll('0xaaa', stage: KnownPollStage.voted));

      final all = await store.all();
      expect(all.length, 2);
      expect(all.first.address, '0xBBB');
      expect((await store.find('0xAaA'))!.stage, KnownPollStage.voted);
    },
  );

  test('stage never regresses (a late joined write keeps voted)', () async {
    final store = InMemoryKnownPollsStore();
    await store.upsert(
      poll('0xAAA', stage: KnownPollStage.voted, receiptCode: '123'),
    );
    await store.upsert(poll('0xAAA', stage: KnownPollStage.joined));

    final record = (await store.find('0xaaa'))!;
    expect(record.stage, KnownPollStage.voted);
    expect(record.receiptCode, '123');
  });

  test('JSON round-trips and skips corrupt entries', () {
    final encoded = encodeKnownPolls([
      poll('0xAAA', stage: KnownPollStage.committed, joinedAtMs: 7),
    ]);
    final decoded = decodeKnownPolls(encoded);
    expect(decoded.single.address, '0xAAA');
    expect(decoded.single.stage, KnownPollStage.committed);
    expect(decoded.single.joinedAtMs, 7);

    expect(decodeKnownPolls('not json'), isEmpty);
    expect(decodeKnownPolls('[{"bogus":true}, 42]'), isEmpty);
    expect(decodeKnownPolls(null), isEmpty);
  });

  test('home sections bucket by stage + chain phase', () {
    // Voted → DONE regardless of phase.
    expect(
      sectionFor(poll('0x1', stage: KnownPollStage.voted), 1),
      VoteHomeSection.done,
    );
    // Committed blind vote: waiting until close, actionable after.
    expect(
      sectionFor(poll('0x1', stage: KnownPollStage.committed), 1),
      VoteHomeSection.waiting,
    );
    expect(
      sectionFor(poll('0x1', stage: KnownPollStage.committed), 2),
      VoteHomeSection.needsYou,
    );
    // Joined: actionable while voting is open, waiting before, done after.
    expect(sectionFor(poll('0x1'), 0), VoteHomeSection.waiting);
    expect(sectionFor(poll('0x1'), 1), VoteHomeSection.needsYou);
    expect(sectionFor(poll('0x1'), 2), VoteHomeSection.done);
    // Unreachable chain reads degrade to waiting, never crash or mislead.
    expect(sectionFor(poll('0x1'), null), VoteHomeSection.waiting);
  });
}
