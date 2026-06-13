/// Module naming for organizers — by what each one DOES, never by its
/// engine name (spec §3 principle 5).
///
/// The CREATE picker (spec 2026-06-13 vote-type-selection-design) groups the
/// **five deployable ballot types** an organizer chooses between by the GOAL
/// they serve, and shows each card's one-line differentiator at all times so
/// the organizer can compare before picking. Sealing (commit–reveal,
/// [OrganizerModule.blindVote]) is NOT offered at create — the relayer's
/// sponsored allow-list refuses it (it would be a ghost), so [BallotGroup]
/// excludes it and the picker never lists it; deferred to R5 (sealed-ballots).
/// Its [moduleDisplayName]/[moduleBlurb] entries remain for the vote and
/// organize-home flows, which still render EXISTING blind polls.
library;

import 'package:core_domain/journeys/organizer_journey.dart';

/// The picker label for [module].
String moduleDisplayName(OrganizerModule module) => switch (module) {
  OrganizerModule.anonVote => 'Pick one',
  OrganizerModule.approvalVote => 'Approve any',
  OrganizerModule.rankedVote => 'Rank them',
  OrganizerModule.quadraticVote => 'Split 100 points',
  OrganizerModule.surveyVote => 'Questionnaire',
  OrganizerModule.blindVote => 'Sealed until reveal',
};

/// One line under the picker label: the differentiator that tells an organizer
/// when to reach for this ballot type. Shown on every card, always — not only
/// once selected.
String moduleBlurb(OrganizerModule module) => switch (module) {
  OrganizerModule.anonVote =>
    'Everyone picks one option; most votes wins. Best for two clear choices.',
  OrganizerModule.rankedVote =>
    'Voters put options in order; finds a true majority — avoids '
        'vote-splitting when 3+ options are similar.',
  OrganizerModule.approvalVote =>
    "Voters tick every option they'd accept; the most broadly liked wins.",
  OrganizerModule.surveyVote =>
    'Several questions at once — collects answers, not a single winner.',
  OrganizerModule.quadraticVote =>
    'Voters spread a budget to show how much they care — caring a lot '
        'costs more.',
  OrganizerModule.blindVote =>
    'Choices stay hidden until everyone reveals after voting closes.',
};

/// Resolve a registry wire name (`anon-vote`, …) back to its module, or null
/// for an unknown/newer wire name.
OrganizerModule? moduleForWireName(String wireName) {
  for (final module in OrganizerModule.values) {
    if (module.wireName == wireName) return module;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Goal grouping (drives the CREATE picker)
// ---------------------------------------------------------------------------

/// The goal an organizer is trying to serve when they reach for a ballot type.
/// The picker renders one section per group, in declaration order.
enum BallotGroup {
  /// Pick a single winner from a set of options.
  decideWinner('DECIDE ON A WINNER'),

  /// Collect answers to one or more questions (no winner).
  gatherOpinions('GATHER OPINIONS'),

  /// Express intensity / allocate a shared budget across options.
  prioritize('PRIORITIZE & ALLOCATE');

  /// The section header shown above this group's cards.
  final String label;

  const BallotGroup(this.label);

  /// The ballot-type modules in this group, in display order. **Never**
  /// includes [OrganizerModule.blindVote] — sealed/commit-reveal creation is
  /// not offered (the relayer refuses it); deferred to R5 (sealed-ballots).
  List<OrganizerModule> get modules => switch (this) {
    BallotGroup.decideWinner => const [
      OrganizerModule.anonVote,
      OrganizerModule.rankedVote,
      OrganizerModule.approvalVote,
    ],
    BallotGroup.gatherOpinions => const [OrganizerModule.surveyVote],
    BallotGroup.prioritize => const [OrganizerModule.quadraticVote],
  };

  /// The ballot type the goal chooser lands on when an organizer picks this
  /// group: the group's first (recommended) module — "Pick one" for
  /// [decideWinner], "Questionnaire" for [gatherOpinions], "Split 100 points"
  /// for [prioritize]. Every group declares at least one module, so this is
  /// always defined.
  OrganizerModule get recommendedModule => modules.first;

  /// The plain-words intent the goal chooser shows for this group — the
  /// optional one-question aid above the manual picker (spec 2026-06-13 P2).
  String get goalPrompt => switch (this) {
    BallotGroup.decideWinner => 'Decide on one winner',
    BallotGroup.gatherOpinions => 'Gather opinions',
    BallotGroup.prioritize => 'Prioritize / allocate',
  };
}

/// The five selectable ballot types, flattened in picker order (the union of
/// every [BallotGroup]'s modules). [OrganizerModule.blindVote] is deliberately
/// absent.
const List<OrganizerModule> selectableBallotTypes = [
  OrganizerModule.anonVote,
  OrganizerModule.rankedVote,
  OrganizerModule.approvalVote,
  OrganizerModule.surveyVote,
  OrganizerModule.quadraticVote,
];

/// The default ballot type a fresh draft starts on — pre-selected so the
/// organizer never faces an empty picker.
const OrganizerModule recommendedBallotType = OrganizerModule.anonVote;

/// Whether [module] carries the `Recommended` badge (the safe default most
/// small groups want).
bool isRecommendedBallot(OrganizerModule module) =>
    module == recommendedBallotType;

/// Whether [module] carries the `Advanced` badge (more powerful, but needs a
/// word of explanation before a first-time organizer reaches for it).
bool isAdvancedBallot(OrganizerModule module) =>
    module == OrganizerModule.quadraticVote;
