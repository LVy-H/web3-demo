// Spec §3 principle 5: voters never see Semaphore / commitment / nullifier /
// module / relayer. This sweeps EVERY voter-facing string in the copy table.
import 'package:feature_vote/feature_vote.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const banned = ['semaphore', 'commitment', 'nullifier', 'module', 'relayer'];

  test('no jargon word appears in any voter-facing copy value', () {
    for (final value in allVoteCopyValues) {
      final lower = value.toLowerCase();
      for (final word in banned) {
        expect(
          lower.contains(word),
          isFalse,
          reason: 'copy "$value" leaks the banned word "$word"',
        );
      }
    }
  });

  test('kind labels are jargon-free names for what the poll does', () {
    for (final id in [
      'anon-vote',
      'approval-vote',
      'ranked-vote',
      'quadratic-vote',
      'survey-vote',
      'blind-vote',
      'live-vote',
      'something-new',
    ]) {
      final label = voteKindLabel(id).toLowerCase();
      expect(label.contains('vote-'), isFalse);
      for (final word in banned) {
        expect(label.contains(word), isFalse);
      }
      // The raw registry id never leaks through.
      expect(voteKindLabel(id), isNot(id));
    }
    expect(voteKindLabel('ranked-vote'), 'RANK THEM');
    expect(voteKindLabel('quadratic-vote'), 'SPLIT 100 POINTS');
  });

  test('every journey key used by the machines has real copy', () {
    const keys = [
      'action.requestJoin',
      'action.castVote',
      'action.viewReceipt',
      'action.backUpSalt',
      'action.revealVote',
      'reason.noSelection',
      'reason.registrationClosed',
      'reason.resultsSealedUntilClose',
      'reason.deviceCannotProve',
      'reason.revealDeadlinePassed',
      'error.loadFailed',
      'error.proofFailed',
      'error.relayFailed',
      'copy.blind.missedReveal',
      'copy.blind.saltMissing',
    ];
    for (final key in keys) {
      expect(voteCopy(key), isNot(voteCopy('no.such.key')), reason: key);
    }
  });
}
