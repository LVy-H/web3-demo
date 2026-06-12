/// The dashboard-facing read surface on top of [OrganizerJourneyPort].
///
/// The journey port covers the in-session create flow; the ORGANIZE home
/// additionally needs to COLD-LOAD the polls this device already runs
/// (across restarts) with enough truth to synthesize each card's journey
/// state. Production implementation: [RelayOrganizerPort]; tests fake it.
library;

import 'package:core_domain/journeys/organizer_journey.dart';

/// A cold snapshot of one poll this device created, read from the chain.
final class RunPollSnapshot {
  final String pollAddress;
  final String title;

  /// Resolved module, or null when the registry's wire name is unknown to
  /// this build (newer module — the card renders read-only).
  final OrganizerModule? module;

  /// On-chain phase: 0 = registration, 1 = voting, 2 = ended.
  final int phase;

  /// Registered voters (the voter list size).
  final int roster;

  /// Ballots counted so far, or null when not fetched (phase 0).
  final int? turnout;

  /// Blind module only: owner finalize already ran.
  final bool finalized;

  /// Blind module only: reveal deadline (unix seconds), 0 until close.
  final int revealDeadline;

  const RunPollSnapshot({
    required this.pollAddress,
    required this.title,
    required this.module,
    required this.phase,
    required this.roster,
    this.turnout,
    this.finalized = false,
    this.revealDeadline = 0,
  });
}

/// Journey port + the dashboard reads.
abstract interface class OrganizerConsolePort implements OrganizerJourneyPort {
  /// Snapshots of every poll recorded as created by this device, newest
  /// first. Polls that no longer resolve on-chain are skipped, not thrown —
  /// a stale local record must never brick the dashboard.
  Future<List<RunPollSnapshot>> loadCreatedPolls();

  /// Re-read one poll's snapshot (after a phase action).
  Future<RunPollSnapshot?> loadPoll(String pollAddress);
}
