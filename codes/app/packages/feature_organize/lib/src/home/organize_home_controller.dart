/// ORGANIZE home state: the polls this device runs, each presented through
/// its ORGANIZER JOURNEY state (spec §4.1 — "dashboard card: phase, turnout,
/// next action").
///
/// Cold-loaded polls can't replay the in-session journey machine (it starts
/// at the draft), so the controller synthesizes the matching
/// [OrganizerDeployedState] from on-chain truth — the journey state TYPES
/// stay the single source of what the organizer may do next
/// ([JourneyState.nextAction]), whether the state came from a live machine
/// or a snapshot.
library;

import 'package:core_domain/journeys/journey.dart';
import 'package:core_domain/journeys/organizer_journey.dart';
import 'package:flutter/foundation.dart';

import '../ports/organizer_console_port.dart';

/// Build the journey state matching a cold [RunPollSnapshot].
OrganizerDeployedState synthesizeOrganizerState(
  RunPollSnapshot snapshot, {
  MinRosterPolicy minRoster = const MinRosterPolicy(),
  int Function()? nowSeconds,
}) {
  final now =
      (nowSeconds ?? (() => DateTime.now().millisecondsSinceEpoch ~/ 1000))();
  // Cold loads keep the conservative spec defaults (unlisted + sealed): the
  // chain is not re-asked for the creation-time policy, and the sealed
  // default only ever UNDER-shows (turnout, not tallies) until close.
  final spec = OrganizerPollSpec(
    module: snapshot.module ?? OrganizerModule.anonVote,
    title: snapshot.title,
  );
  final smallGroup = snapshot.roster < minRoster.threshold;
  switch (snapshot.phase) {
    case 0:
      return OrganizerRegistrationOpen(
        pollAddress: snapshot.pollAddress,
        spec: spec,
        rosterCount: snapshot.roster,
        fetchPending: false,
        cancellation: CancellationToken(),
      );
    case 1:
      return OrganizerVotingOpen(
        pollAddress: snapshot.pollAddress,
        spec: spec,
        rosterCount: snapshot.roster,
        turnout: snapshot.turnout,
        smallGroupWarning: smallGroup,
        fetchPending: false,
        cancellation: CancellationToken(),
      );
    default:
      final blind = snapshot.module == OrganizerModule.blindVote;
      return OrganizerClosed(
        pollAddress: snapshot.pollAddress,
        spec: spec,
        rosterCount: snapshot.roster,
        turnout: snapshot.turnout,
        smallGroupWarning: smallGroup,
        finalized: !blind || snapshot.finalized,
        revealWindowElapsed:
            !blind ||
            (snapshot.revealDeadline > 0 && now >= snapshot.revealDeadline),
        fetchPending: false,
        cancellation: CancellationToken(),
      );
  }
}

/// One dashboard card's data.
class OrganizerDashboardEntry {
  final RunPollSnapshot snapshot;

  /// The journey state the card renders (synthesized from [snapshot], or
  /// replaced by [OrganizerPublished] after a publish action).
  final OrganizerState state;

  /// A phase action for this poll is in flight.
  final bool busy;

  /// Organizer-facing error text from the last failed action, if any.
  final String? actionError;

  const OrganizerDashboardEntry({
    required this.snapshot,
    required this.state,
    this.busy = false,
    this.actionError,
  });

  String get pollAddress => snapshot.pollAddress;

  OrganizerDashboardEntry copyWith({
    RunPollSnapshot? snapshot,
    OrganizerState? state,
    bool? busy,
    String? actionError,
    bool clearError = false,
  }) => OrganizerDashboardEntry(
    snapshot: snapshot ?? this.snapshot,
    state: state ?? this.state,
    busy: busy ?? this.busy,
    actionError: clearError ? null : (actionError ?? this.actionError),
  );
}

/// Loads and refreshes the dashboard; runs each card's ONE next action.
class OrganizeHomeController extends ChangeNotifier {
  final OrganizerConsolePort port;
  final MinRosterPolicy minRoster;

  OrganizeHomeController({
    required this.port,
    this.minRoster = const MinRosterPolicy(),
  });

  bool _loading = false;
  String? _loadError;
  List<OrganizerDashboardEntry> _entries = const [];
  bool _disposed = false;

  bool get loading => _loading;
  String? get loadError => _loadError;
  List<OrganizerDashboardEntry> get entries => _entries;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    _loading = true;
    _loadError = null;
    _notify();
    try {
      final snapshots = await port.loadCreatedPolls();
      _entries = [
        for (final snapshot in snapshots)
          OrganizerDashboardEntry(
            snapshot: snapshot,
            state: synthesizeOrganizerState(snapshot, minRoster: minRoster),
          ),
      ];
    } catch (_) {
      _loadError =
          'Your polls could not be loaded. Check the connection and pull '
          'to refresh.';
    } finally {
      _loading = false;
      _notify();
    }
  }

  /// Run [entry]'s current next action (start voting / close / finalize /
  /// publish). Failures land in [OrganizerDashboardEntry.actionError]; the
  /// busy flag is always released (the historical stuck-busy class).
  Future<void> runNextAction(OrganizerDashboardEntry entry) async {
    final index = _entries.indexWhere(
      (e) => e.pollAddress == entry.pollAddress,
    );
    if (index < 0 || entry.busy) return;
    _entries = [..._entries]
      ..[index] = entry.copyWith(busy: true, clearError: true);
    _notify();
    try {
      switch (entry.state) {
        case OrganizerRegistrationOpen():
          await port.startVoting(entry.pollAddress);
          await _refreshEntry(entry.pollAddress);
        case OrganizerVotingOpen():
          await port.endVoting(entry.pollAddress);
          await _refreshEntry(entry.pollAddress);
        case OrganizerClosed(:final spec, :final finalized)
            when spec.module == OrganizerModule.blindVote && !finalized:
          await port.finalize(entry.pollAddress);
          await _refreshEntry(entry.pollAddress);
        case OrganizerClosed():
          final results = await port.fetchResults(entry.pollAddress);
          _replace(
            entry.pollAddress,
            (e) => e.copyWith(
              busy: false,
              state: OrganizerPublished(
                pollAddress: e.pollAddress,
                spec: (e.state as OrganizerDeployedState).spec,
                results: results,
                turnout: e.snapshot.turnout,
                smallGroupWarning: e.snapshot.roster < minRoster.threshold,
              ),
            ),
          );
        default:
          _replace(entry.pollAddress, (e) => e.copyWith(busy: false));
      }
    } catch (error) {
      _replace(
        entry.pollAddress,
        (e) => e.copyWith(busy: false, actionError: '$error'),
      );
    }
    _notify();
  }

  Future<void> _refreshEntry(String pollAddress) async {
    final snapshot = await port.loadPoll(pollAddress);
    _replace(pollAddress, (e) {
      if (snapshot == null) return e.copyWith(busy: false);
      return OrganizerDashboardEntry(
        snapshot: snapshot,
        state: synthesizeOrganizerState(snapshot, minRoster: minRoster),
      );
    });
  }

  void _replace(
    String pollAddress,
    OrganizerDashboardEntry Function(OrganizerDashboardEntry) update,
  ) {
    final index = _entries.indexWhere((e) => e.pollAddress == pollAddress);
    if (index < 0) return;
    _entries = [..._entries]..[index] = update(_entries[index]);
  }
}
