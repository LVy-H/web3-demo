/// Organizer-facing copy for the ORGANIZE space (spec §3 principle 5).
///
/// One table from journey localization keys to plain language. Organizer copy
/// may say "voter list", "turnout", "results policy" — it NEVER says
/// Semaphore, nullifier, commitment, module, or relayer (the sponsoring
/// service is "the sponsoring service").
library;

const Map<String, String> _copy = {
  // ── organizer journey actions ──
  'action.organizer.deployPoll': 'CREATE POLL',
  'action.organizer.deploying': 'CREATING…',
  'action.organizer.distribute': 'DISTRIBUTE',
  'action.organizer.startVoting': 'START VOTING',
  'action.organizer.startingVoting': 'STARTING…',
  'action.organizer.endVoting': 'CLOSE VOTING',
  'action.organizer.endingVoting': 'CLOSING…',
  'action.organizer.finalize': 'FINALIZE RESULTS',
  'action.organizer.finalizing': 'FINALIZING…',
  'action.organizer.publishResults': 'PUBLISH RESULTS',
  'action.organizer.publishing': 'PUBLISHING…',
  'action.retry': 'TRY AGAIN',

  // ── organizer journey disabled/why-not reasons ──
  'reason.organizer.noSignerPath':
      'Creating a poll needs the sponsoring service or a signing key — '
      'this device has neither right now.',
  'reason.organizer.draftIncomplete':
      'Add a title and at least two answer options to continue.',
  'reason.organizer.revealWindowOpen':
      'The reveal window is still open — finalizing now would cut off '
      'voters who haven’t revealed yet.',

  // ── created-state notices (spec §5 privacy defaults) ──
  'notice.organizer.createdUnlisted':
      'Your poll is private — only people you share it with can find it. '
      'Distribute the link, QR, or code to open it up.',
  'notice.organizer.createdListed':
      'Your poll is listed in the public directory, and anyone with the '
      'link, QR, or code can open it too.',

  // ── organizer journey errors ──
  'error.organizer.deployFailed':
      'Your poll could not be created. Nothing was published — '
      'you can try again or keep editing.',
  'error.organizer.startVotingFailed': 'Voting could not be started.',
  'error.organizer.endVotingFailed': 'Voting could not be closed.',
  'error.organizer.finalizeFailed': 'The results could not be finalized.',
  'error.organizer.publishFailed': 'The results could not be loaded.',

  // ── live host (run-event console) ──
  'action.loading': 'SETTING UP…',
  'action.confirming': 'ADMITTING…',
  'action.startVoting': 'START VOTING',
  'action.startingVoting': 'STARTING…',
  'action.closeVoting': 'CLOSE VOTING',
  'action.closing': 'CLOSING…',
  'reason.liveHost.noAdmittedVoters': 'Admit at least one voter first.',
  'error.liveHost.loadFailed':
      'The session could not be set up. Check the connection and try again.',
  'error.liveHost.confirmFailed': 'That voter could not be admitted.',
  'error.liveHost.startVotingFailed': 'Voting could not be started.',
  'error.liveHost.closeFailed': 'The vote could not be closed.',
};

/// Resolve a journey localization [key] to organizer-facing copy. Unknown
/// keys fall back to the key itself so a missing entry is visible in the UI
/// and tests, never silently blank.
String organizeCopy(String key) => _copy[key] ?? key;
