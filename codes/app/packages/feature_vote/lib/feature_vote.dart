/// Tessera VOTE space (R3): the voter home (needs-you / waiting / done +
/// the opt-in public directory), the journey-state poll surfaces for the
/// proof and sealed-until-reveal modules, and the production port adapters
/// that drive the core_domain journey machines.
library;

export 'src/copy.dart' show allVoteCopyValues, voteCopy, voteKindLabel;
export 'src/data/known_polls_store.dart';
export 'src/data/listed_polls_reader.dart'
    show ListedPoll, ListedPollsReader, ResultsPolicyReader;
export 'src/data/survey_reader.dart';
export 'src/ports/ballot_encoding.dart';
export 'src/ports/blind_port_adapter.dart';
export 'src/ports/server_voter_port_adapter.dart';
export 'src/ports/voter_port_adapter.dart';
export 'src/screens/blind_journey_screen.dart';
export 'src/screens/poll_journey_screen.dart';
export 'src/screens/vote_home_screen.dart';
export 'src/widgets/ballots/ballots.dart';
export 'src/widgets/vote_chrome.dart';

/// Workspace-wiring smoke constant (kept from the R3 scaffold).
const String featureVotePackageName = 'feature_vote';
