/// The ORGANIZE space (spec §4.1): the polls this device runs, one dashboard
/// card each — phase, roster/turnout, the ONE next action — with CREATE as
/// the primary entry. Pure feature widget: every dependency is injected by
/// the shell's thin `organize_space_screen.dart` glue; this package never
/// imports the router or provider.
library;

import 'package:core_domain/journeys/organizer_journey.dart';
import 'package:design_system/dot_grid_background.dart';
import 'package:design_system/theme.dart';
import 'package:feature_join/feature_join.dart' show shareLinkForPoll;
import 'package:flutter/material.dart';

import '../ports/organizer_console_port.dart';
import '../share/distribute_sheet.dart';
import 'organize_home_controller.dart';
import 'organizer_poll_card.dart';

class OrganizeSpaceView extends StatefulWidget {
  static const Key createButtonKey = Key('organize-create');
  static const Key emptyStateKey = Key('organize-empty');

  final OrganizerConsolePort port;

  /// NFC hardware present — gates the share sheet's NFC tile (spec §4.3).
  final bool nfcAvailable;

  /// Open the create flow (`/organize/create` in production).
  final VoidCallback onCreate;

  /// Open the run-event console for a poll (`/live/:address/host`).
  final void Function(String pollAddress) onRunEvent;

  final MinRosterPolicy minRoster;

  const OrganizeSpaceView({
    super.key,
    required this.port,
    required this.nfcAvailable,
    required this.onCreate,
    required this.onRunEvent,
    this.minRoster = const MinRosterPolicy(),
  });

  @override
  State<OrganizeSpaceView> createState() => _OrganizeSpaceViewState();
}

class _OrganizeSpaceViewState extends State<OrganizeSpaceView> {
  late final OrganizeHomeController _controller = OrganizeHomeController(
    port: widget.port,
    minRoster: widget.minRoster,
  );

  @override
  void initState() {
    super.initState();
    _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: DotGridBackground(
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListenableBuilder(
              listenable: _controller,
              builder: (context, _) => RefreshIndicator(
                onRefresh: _controller.load,
                color: Db.segnale,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
                  children: [
                    Text('ORGANIZE', style: dbHero(48)),
                    const SizedBox(height: 10),
                    Text(
                      'The polls and events you run. New polls start '
                      'private — only people you share them with can '
                      'find them.',
                      style: dbSans(14, 400, Db.chalkDim, height: 1.6),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      key: OrganizeSpaceView.createButtonKey,
                      style: FilledButton.styleFrom(
                        backgroundColor: Db.segnale,
                        foregroundColor: Db.void_,
                        shape: const RoundedRectangleBorder(),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: widget.onCreate,
                      child: Text('CREATE A POLL', style: dbMono(13, Db.void_)),
                    ),
                    const SizedBox(height: 24),
                    ..._body(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  List<Widget> _body() {
    if (_controller.loading && _controller.entries.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Db.mute,
              ),
            ),
          ),
        ),
      ];
    }
    final loadError = _controller.loadError;
    if (loadError != null) {
      return [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Db.slate3,
            border: Border.all(color: Db.rule),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(loadError, style: dbSans(13, 400, Db.chalkDim)),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _controller.load,
                child: Text('TRY AGAIN', style: dbMono(12, Db.chalk)),
              ),
            ],
          ),
        ),
      ];
    }
    if (_controller.entries.isEmpty) {
      // Empty state → CREATE (spec §4.1: CREATE lives here, as the obvious
      // first step, not behind a hidden tab).
      return [
        Container(
          key: OrganizeSpaceView.emptyStateKey,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Db.slate3,
            border: Border.all(color: Db.rule),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('NOTHING RUNNING YET', style: dbLabel(color: Db.chalkDim)),
              const SizedBox(height: 10),
              Text(
                'Create your first poll above. You choose how people vote, '
                'and nothing is public unless you decide it is.',
                style: dbSans(13, 400, Db.chalkDim, height: 1.5),
              ),
            ],
          ),
        ),
      ];
    }
    return [
      Text('YOUR POLLS', style: dbLabel()),
      const SizedBox(height: 12),
      for (final entry in _controller.entries) _card(entry),
    ];
  }

  Widget _card(OrganizerDashboardEntry entry) {
    final deployed = entry.state;
    if (deployed is! OrganizerDeployedState) return const SizedBox.shrink();
    final phase = entry.snapshot.phase;
    return OrganizerPollCard(
      key: Key('poll-card-${entry.pollAddress}'),
      state: deployed,
      title: entry.snapshot.title,
      busy: entry.busy,
      errorText: entry.actionError,
      onAction: () => _controller.runNextAction(entry),
      // Distribution makes sense while people can still join (registration).
      onDistribute: phase == 0 ? () => _distribute(entry) : null,
      // The run-event console covers admit (phase 0) and live turnout/close
      // (phase 1); a closed poll has nothing live left to run.
      onRunEvent: phase <= 1
          ? () => widget.onRunEvent(entry.pollAddress)
          : null,
    );
  }

  void _distribute(OrganizerDashboardEntry entry) {
    DistributeSheet.show(
      context,
      shareLink: shareLinkForPoll(
        entry.pollAddress,
        module: entry.snapshot.module?.wireName,
      ),
      nfcAvailable: widget.nfcAvailable,
    );
  }
}
