/// One ORGANIZE dashboard card: a thin renderer of an organizer journey
/// state — phase strip, voter list / turnout, the ONE next action, the
/// small-group honesty chip (spec §4.1, §5).
library;

import 'package:core_domain/journeys/organizer_journey.dart';
import 'package:design_system/theme.dart';
import 'package:design_system/widgets/results_bars.dart';
import 'package:flutter/material.dart';

import '../module_names.dart';
import '../organize_copy.dart';

class OrganizerPollCard extends StatelessWidget {
  static const Key smallGroupChipKey = Key('small-group-chip');
  static const Key nextActionKey = Key('card-next-action');

  /// The journey state this card renders (any deployed state).
  final OrganizerDeployedState state;

  /// Poll title shown on the card ([OrganizerPollSpec.title] is empty on
  /// some cold loads, so the caller passes the registry title explicitly).
  final String title;

  final bool busy;
  final String? errorText;

  /// Runs the state's ONE next action. Null renders the action disabled.
  final VoidCallback? onAction;

  /// Opens the share sheet. Non-null only while distribution makes sense
  /// (created / registration open).
  final VoidCallback? onDistribute;

  /// Opens the run-event console (live admit/start/close).
  final VoidCallback? onRunEvent;

  const OrganizerPollCard({
    super.key,
    required this.state,
    required this.title,
    this.busy = false,
    this.errorText,
    this.onAction,
    this.onDistribute,
    this.onRunEvent,
  });

  @override
  Widget build(BuildContext context) {
    final phase = _phaseLabel(state);
    final action = state.nextAction;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Db.slate,
        border: Border.all(color: Db.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title.isEmpty ? 'Untitled poll' : title,
                  style: dbSans(16, 700, Db.chalk),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              _chip(phase.label, phase.color),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            moduleDisplayName(state.spec.module).toUpperCase(),
            style: dbLabel(),
          ),
          const SizedBox(height: 12),
          _counts(state),
          if (_smallGroupFlagged(state)) ...[
            const SizedBox(height: 10),
            _smallGroupChip(),
          ],
          if (state is OrganizerCreated) ...[
            const SizedBox(height: 10),
            Text(
              organizeCopy((state as OrganizerCreated).noticeKey),
              style: dbSans(12, 400, Db.chalkDim),
            ),
          ],
          if (state is OrganizerPublished) ...[
            const SizedBox(height: 12),
            _publishedResults(state as OrganizerPublished),
          ],
          if (errorText != null) ...[
            const SizedBox(height: 10),
            Text(errorText!, style: dbSans(12, 400, Db.segnale)),
          ],
          if (action != null || onDistribute != null || onRunEvent != null)
            const SizedBox(height: 14),
          Row(
            children: [
              if (action != null)
                Expanded(
                  child: FilledButton(
                    key: nextActionKey,
                    style: FilledButton.styleFrom(
                      backgroundColor: Db.segnale,
                      foregroundColor: Db.void_,
                      shape: const RoundedRectangleBorder(),
                    ),
                    onPressed: (busy || !action.enabled || onAction == null)
                        ? null
                        : onAction,
                    child: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            organizeCopy(action.labelKey),
                            style: dbMono(12, Db.void_),
                          ),
                  ),
                ),
              if (onDistribute != null) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  key: const Key('card-distribute'),
                  onPressed: onDistribute,
                  child: const Icon(Icons.qr_code_2, size: 18),
                ),
              ],
              if (onRunEvent != null) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  key: const Key('card-run-event'),
                  onPressed: onRunEvent,
                  child: const Icon(Icons.sensors, size: 18),
                ),
              ],
            ],
          ),
          if (action?.disabledReasonKey != null) ...[
            const SizedBox(height: 8),
            Text(
              organizeCopy(action!.disabledReasonKey!),
              key: const Key('card-disabled-reason'),
              style: dbSans(12, 400, Db.mute),
            ),
          ],
        ],
      ),
    );
  }

  Widget _counts(OrganizerDeployedState state) {
    final rows = <(String, String)>[];
    switch (state) {
      case OrganizerCreated():
        rows.add(('voter list', 'share to open registration'));
      case OrganizerRegistrationOpen(:final rosterCount):
        rows.add(('voter list', '${rosterCount ?? '—'} registered'));
      case OrganizerVotingOpen(:final rosterCount, :final turnout):
        rows.add(('voter list', '${rosterCount ?? '—'} registered'));
        rows.add((
          'turnout',
          _turnoutText(state.spec.module, turnout, rosterCount),
        ));
      case OrganizerClosed(:final rosterCount, :final turnout):
        rows.add(('voter list', '${rosterCount ?? '—'} registered'));
        rows.add((
          'turnout',
          _turnoutText(state.spec.module, turnout, rosterCount),
        ));
      case OrganizerPublished(:final turnout):
        rows.add((
          'turnout',
          _turnoutText(state.spec.module, turnout, null),
        ));
      default:
        break;
    }
    return Column(
      children: [
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 96,
                  child: Text(label.toUpperCase(), style: dbLabel()),
                ),
                Expanded(child: Text(value, style: dbMono(12, Db.chalk))),
              ],
            ),
          ),
      ],
    );
  }

  /// Turnout phrasing: people for one-ballot modules; marks/points for the
  /// modules whose on-chain counters aren't one-per-voter. Never tallies.
  String _turnoutText(OrganizerModule module, int? turnout, int? roster) {
    if (turnout == null) return '—';
    return switch (module) {
      OrganizerModule.approvalVote => '$turnout approvals',
      OrganizerModule.quadraticVote => '$turnout points placed',
      _ => roster == null ? '$turnout voted' : '$turnout of $roster voted',
    };
  }

  bool _smallGroupFlagged(OrganizerDeployedState state) => switch (state) {
    OrganizerVotingOpen(:final smallGroupWarning) => smallGroupWarning,
    OrganizerClosed(:final smallGroupWarning) => smallGroupWarning,
    OrganizerPublished(:final smallGroupWarning) => smallGroupWarning,
    _ => false,
  };

  Widget _smallGroupChip() => Container(
    key: smallGroupChipKey,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      border: Border.all(color: Db.amber),
      color: Db.slate4,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.warning_amber_outlined, size: 13, color: Db.amber),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            'SMALL GROUP — results can identify people',
            style: dbMono(10, Db.amber),
          ),
        ),
      ],
    ),
  );

  Widget _publishedResults(OrganizerPublished published) => ResultsBars(
    options: [
      for (final entry in published.results.tallies.entries)
        (label: entry.key, count: BigInt.from(entry.value)),
    ],
    highlightLeader:
        published.spec.module != OrganizerModule.rankedVote &&
        published.spec.module != OrganizerModule.surveyVote,
  );

  ({String label, Color color}) _phaseLabel(OrganizerDeployedState state) =>
      switch (state) {
        OrganizerCreated() => (label: 'CREATED', color: Db.oltremare),
        OrganizerRegistrationOpen() ||
        OrganizerStartVotingInProgress() => (
          label: 'REGISTRATION',
          color: Db.oltremare,
        ),
        OrganizerVotingOpen() ||
        OrganizerEndVotingInProgress() => (
          label: 'VOTING OPEN',
          color: Db.success,
        ),
        OrganizerPublished() => (label: 'RESULTS', color: Db.success),
        _ => (label: 'CLOSED', color: Db.mute),
      };

  Widget _chip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(border: Border.all(color: color)),
    child: Text(label, style: dbMono(10, color)),
  );
}
