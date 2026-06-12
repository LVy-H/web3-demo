/// Jargon-free voter copy (Revolution spec §3 principle 5).
///
/// One lookup from the journey machines' localization keys to the words a
/// voter actually sees. The banned vocabulary — Semaphore, commitment,
/// nullifier, module, relayer — never appears in any value here; a test
/// (`test/copy_test.dart`) enforces it.
library;

/// Voter-facing copy for a journey label / reason / message key. Unknown keys
/// fall back to a generic phrase instead of leaking the raw key.
String voteCopy(String key) => _copy[key] ?? _fallback;

/// Every voter-facing string in the table — the no-jargon test sweeps this.
Iterable<String> get allVoteCopyValues => _copy.values;

const _fallback = 'Something needs your attention.';

const Map<String, String> _copy = {
  // ── shared actions ────────────────────────────────────────────────────
  'action.loading': 'LOADING…',
  'action.retry': 'TRY AGAIN',
  'action.checkingEligibility': 'CHECKING YOUR ACCESS…',
  'action.requestJoin': 'ASK TO JOIN',
  'action.joining': 'JOINING…',
  'action.recheckRegistration': 'CHECK AGAIN',
  'action.waitForOpen': 'WAITING FOR VOTING TO OPEN',
  'action.castVote': 'CAST YOUR VOTE',
  'action.casting': 'SENDING YOUR VOTE…',
  'action.cancel': 'CANCEL',
  'action.viewReceipt': 'VIEW YOUR RECEIPT',
  'action.viewResults': 'SEE RESULTS',

  // ── reasons (honest disabled surfaces) ────────────────────────────────
  'reason.noSelection': 'Make your choice first.',
  'reason.registrationClosed': 'Joining is closed for this vote.',
  'reason.relayerUnavailable': 'The voting service can’t be reached right now.',
  'reason.relayer.unreachable':
      'The voting service can’t be reached right now.',
  'reason.relayer.probing':
      'Still checking the voting service — give it a moment.',
  'reason.deviceCannotProve':
      'Voting from this device isn’t supported yet — '
      'use the web app or an Android phone.',
  'reason.prove.platformUnsupported':
      'Voting from this device isn’t supported yet — '
      'use the web app or an Android phone.',
  'reason.resultsSealedUntilClose': 'Results open when voting closes.',

  // ── errors (always with a way out) ────────────────────────────────────
  'error.loadFailed': 'Could not load this vote. Check your connection.',
  'error.joinFailed': 'Could not join this vote. Try again.',
  'error.registrationStillPending':
      'You’re almost in — your join is still being confirmed.',
  'error.proofFailed': 'Could not prepare your private vote. Try again.',
  'error.relayFailed': 'Your vote did not go through. Try again.',

  // ── blind (sealed-until-reveal) journey ───────────────────────────────
  'action.register': 'JOIN THIS VOTE',
  'action.registering': 'JOINING…',
  'action.waitingForVotingOpen': 'WAITING FOR VOTING TO OPEN',
  'action.commitVote': 'LOCK IN YOUR VOTE',
  'action.committing': 'LOCKING IN…',
  'action.backUpSalt': 'SAVE YOUR VOTE KEY',
  'action.waitingForPollEnd': 'LOCKED IN — WAITING FOR VOTING TO CLOSE',
  'action.checkingRevealWindow': 'CHECKING THE CONFIRMATION WINDOW…',
  'action.revealVote': 'CONFIRM YOUR VOTE',
  'action.revealing': 'CONFIRMING…',
  'action.waitingForResults': 'WAITING FOR FINAL RESULTS',
  'reason.revealDeadlinePassed': 'The confirmation window has closed.',
  'error.blind.loadFailed': 'Could not load this vote. Check your connection.',
  'error.blind.registerFailed': 'Could not join this vote. Try again.',
  'error.blind.commitFailed': 'Could not lock in your vote. Try again.',
  'error.blind.revealCheckFailed':
      'Could not check the confirmation window. Try again.',
  'error.blind.revealFailed': 'Could not confirm your vote. Try again.',
  'copy.blind.missedReveal':
      'The confirmation window closed before this vote was confirmed, '
      'so it can’t be counted. Deadlines here are final.',
  'copy.blind.saltMissing':
      'Your vote key isn’t on this device, so this vote can’t be '
      'confirmed. The key only ever existed on the device that locked '
      'the vote in.',
  'copy.blind.registrationClosed':
      'Joining closed before you joined, so you can’t take part in '
      'this vote.',
  'copy.blind.endedWithoutCommit':
      'Voting closed before you locked in a choice, so you can’t take '
      'part in this vote.',
};

/// Jargon-free poll-kind label for a registry module-type id (spec §3
/// principle 5: poll types are named by what they do). Voters never see the
/// raw id.
String voteKindLabel(String moduleType) => switch (moduleType) {
  'anon-vote' => 'PICK ONE',
  'approval-vote' => 'APPROVE ANY',
  'ranked-vote' => 'RANK THEM',
  'quadratic-vote' => 'SPLIT 100 POINTS',
  'survey-vote' => 'QUESTIONNAIRE',
  'blind-vote' => 'SEALED UNTIL REVEAL',
  'live-vote' => 'LIVE SESSION',
  _ => 'VOTE',
};
