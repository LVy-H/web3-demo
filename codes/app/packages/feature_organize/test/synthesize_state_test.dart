// Cold-load state synthesis: a RunPollSnapshot must map onto the SAME
// organizer journey state types the live machine produces, so the dashboard
// card has one rendering path (spec §4.2: screens are journey states).
import 'package:core_domain/journeys/organizer_journey.dart';
import 'package:feature_organize/feature_organize.dart';
import 'package:flutter_test/flutter_test.dart';

RunPollSnapshot _snapshot({
  int phase = 0,
  int roster = 12,
  int? turnout,
  OrganizerModule? module = OrganizerModule.anonVote,
  bool finalized = false,
  int revealDeadline = 0,
}) => RunPollSnapshot(
  pollAddress: '0xpoll',
  title: 'Snack budget',
  module: module,
  phase: phase,
  roster: roster,
  turnout: turnout,
  finalized: finalized,
  revealDeadline: revealDeadline,
);

void main() {
  test('phase 0 → registrationOpen with the live roster', () {
    final state = synthesizeOrganizerState(_snapshot(phase: 0, roster: 7));
    expect(state, isA<OrganizerRegistrationOpen>());
    expect((state as OrganizerRegistrationOpen).rosterCount, 7);
    expect(state.nextAction!.labelKey, 'action.organizer.startVoting');
  });

  test('phase 1 → votingOpen with turnout and no small-group flag at the '
      'threshold', () {
    final state = synthesizeOrganizerState(
      _snapshot(phase: 1, roster: 5, turnout: 3),
    );
    expect(state, isA<OrganizerVotingOpen>());
    final voting = state as OrganizerVotingOpen;
    expect(voting.turnout, 3);
    expect(voting.smallGroupWarning, isFalse);
    expect(voting.nextAction!.labelKey, 'action.organizer.endVoting');
  });

  test('below the roster threshold the small-group warning is on', () {
    final state = synthesizeOrganizerState(
      _snapshot(phase: 1, roster: 4, turnout: 2),
    );
    expect((state as OrganizerVotingOpen).smallGroupWarning, isTrue);
  });

  test('phase 2 non-blind → closed, already "finalized", publish is next', () {
    final state = synthesizeOrganizerState(_snapshot(phase: 2, turnout: 10));
    expect(state, isA<OrganizerClosed>());
    final closed = state as OrganizerClosed;
    expect(closed.finalized, isTrue);
    expect(closed.revealWindowElapsed, isTrue);
    expect(closed.nextAction!.labelKey, 'action.organizer.publishResults');
    expect(closed.nextAction!.enabled, isTrue);
  });

  test('phase 2 blind, reveal window still open → finalize disabled with '
      'the honest reason', () {
    final state = synthesizeOrganizerState(
      _snapshot(
        phase: 2,
        module: OrganizerModule.blindVote,
        revealDeadline: 2000,
      ),
      nowSeconds: () => 1000,
    );
    final closed = state as OrganizerClosed;
    expect(closed.finalized, isFalse);
    expect(closed.nextAction!.labelKey, 'action.organizer.finalize');
    expect(
      closed.nextAction!.disabledReasonKey,
      'reason.organizer.revealWindowOpen',
    );
  });

  test('phase 2 blind, window elapsed → finalize enabled', () {
    final state = synthesizeOrganizerState(
      _snapshot(
        phase: 2,
        module: OrganizerModule.blindVote,
        revealDeadline: 500,
      ),
      nowSeconds: () => 1000,
    );
    expect((state as OrganizerClosed).nextAction!.enabled, isTrue);
  });

  test('unknown module (newer wire name) still renders — falls back without '
      'throwing', () {
    final state = synthesizeOrganizerState(
      _snapshot(phase: 1, module: null, turnout: 1),
    );
    expect(state, isA<OrganizerVotingOpen>());
  });
}
