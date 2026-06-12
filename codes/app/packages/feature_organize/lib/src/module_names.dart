/// Module naming for organizers — by what each one DOES, never by its
/// engine name (spec §3 principle 5).
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

/// One line under the picker label: what voters will do.
String moduleBlurb(OrganizerModule module) => switch (module) {
  OrganizerModule.anonVote => 'Each voter picks exactly one option.',
  OrganizerModule.approvalVote =>
    'Voters approve as many options as they like.',
  OrganizerModule.rankedVote =>
    'Voters order the options from favorite down (up to 8 options).',
  OrganizerModule.quadraticVote =>
    'Voters split a 100-point budget across options (up to 8).',
  OrganizerModule.surveyVote => 'Several questions, each with its own options.',
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
