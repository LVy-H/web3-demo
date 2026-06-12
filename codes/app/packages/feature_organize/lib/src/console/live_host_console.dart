/// The run-event console (spec §4.1: "the live-host console is this same
/// dashboard's run-event mode"), a thin renderer of [LiveHostMachine]:
///
///   loading → sessionOpen (rotating QR ticket + admit queue)
///           → votingOpen (turnout) → closed
///
/// Every button dispatches a machine event; phase order is enforced by the
/// machine's transition table, not by the widget — START VOTING is honestly
/// disabled (with the reason) until someone is admitted, and the legacy
/// orderless phase buttons are unrepresentable here.
library;

import 'dart:async';

import 'package:core_domain/journeys/journey.dart';
import 'package:core_domain/journeys/live_journeys.dart';
import 'package:design_system/dot_grid_background.dart';
import 'package:design_system/theme.dart';
import 'package:flutter/material.dart';

import '../organize_copy.dart';
import '../qr/qr_view.dart';

class LiveHostConsole extends StatefulWidget {
  static const Key ticketQrKey = Key('console-ticket-qr');
  static const Key startVotingKey = Key('console-start-voting');
  static const Key startDisabledReasonKey = Key('console-start-reason');
  static const Key closeKey = Key('console-close');
  static const Key doneKey = Key('console-done');

  final LiveHostPort port;
  final LiveTicker ticker;
  final Duration pollInterval;
  final Duration rotateEvery;

  /// Leave the console (back to the ORGANIZE dashboard).
  final VoidCallback onExit;

  const LiveHostConsole({
    super.key,
    required this.port,
    required this.onExit,
    this.ticker = const SystemLiveTicker(),
    this.pollInterval = const Duration(seconds: 2),
    this.rotateEvery = const Duration(seconds: 25),
  });

  @override
  State<LiveHostConsole> createState() => _LiveHostConsoleState();
}

class _LiveHostConsoleState extends State<LiveHostConsole> {
  late final LiveHostMachine _machine = LiveHostMachine(
    port: widget.port,
    ticker: widget.ticker,
    pollInterval: widget.pollInterval,
    rotateEvery: widget.rotateEvery,
  );
  StreamSubscription<LiveHostState>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = _machine.states.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _machine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _machine.state;
    return Scaffold(
      appBar: AppBar(title: Text('RUN EVENT', style: dbSectionTitle)),
      body: DotGridBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: switch (state) {
                LiveHostLoadingInProgress() => _loading(),
                LiveHostSessionOpen open => _session(
                  ticket: open.ticket,
                  queue: open.queue,
                  action: open.nextAction,
                  confirmingCode: null,
                  starting: false,
                ),
                LiveHostConfirmingInProgress confirming => _session(
                  ticket: confirming.ticket,
                  queue: confirming.queue,
                  action: confirming.nextAction,
                  confirmingCode: confirming.confirmationCode,
                  starting: false,
                ),
                LiveHostStartVotingInProgress starting => _session(
                  ticket: starting.ticket,
                  queue: starting.queue,
                  action: starting.nextAction,
                  confirmingCode: null,
                  starting: true,
                ),
                LiveHostVotingOpen voting => _voting(
                  admitted: voting.admitted,
                  turnout: voting.turnout,
                  closing: false,
                ),
                LiveHostClosingInProgress closing => _voting(
                  admitted: closing.admitted,
                  turnout: closing.turnout,
                  closing: true,
                ),
                LiveHostClosed closed => _closed(closed),
                LiveHostFailed failed => _failed(failed),
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _loading() => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2, color: Db.mute),
      ),
      const SizedBox(height: 16),
      Text('Setting up the room…', style: dbSans(13, 400, Db.chalkDim)),
    ],
  );

  // ── admit phase ──────────────────────────────────────────────────────────

  Widget _session({
    required String ticket,
    required AdmitQueue queue,
    required NextAction? action,
    required String? confirmingCode,
    required bool starting,
  }) => ListView(
    padding: const EdgeInsets.fromLTRB(24, 16, 24, 96),
    children: [
      Text(
        'Voters scan this code to enter. It refreshes by itself.',
        style: dbSans(13, 400, Db.chalkDim, height: 1.5),
      ),
      const SizedBox(height: 16),
      Center(
        child: QrView(
          key: LiveHostConsole.ticketQrKey,
          data: ticket,
          dimension: 240,
        ),
      ),
      const SizedBox(height: 20),
      Row(
        children: [
          _stat('IN THE ROOM', '${queue.admitted}'),
          const SizedBox(width: 12),
          _stat('WAITING', '${queue.pending.length}'),
        ],
      ),
      const SizedBox(height: 16),
      if (queue.pending.isNotEmpty) ...[
        Text('WAITING TO BE LET IN', style: dbLabel()),
        const SizedBox(height: 4),
        Text(
          'Check the code on the voter’s screen, then admit them.',
          style: dbSans(12, 400, Db.chalkDim),
        ),
        const SizedBox(height: 10),
        for (final voter in queue.pending)
          _pendingRow(
            voter,
            busy: confirmingCode == voter.confirmationCode,
            enabled: confirmingCode == null && !starting,
          ),
        const SizedBox(height: 8),
      ],
      const SizedBox(height: 8),
      if (action != null)
        FilledButton(
          key: LiveHostConsole.startVotingKey,
          style: FilledButton.styleFrom(
            backgroundColor: Db.segnale,
            foregroundColor: Db.void_,
            disabledBackgroundColor: Db.slate4,
            disabledForegroundColor: Db.mute,
            shape: const RoundedRectangleBorder(),
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          onPressed:
              (starting || confirmingCode != null || !action.enabled)
              ? null
              : () => _machine.advance(const LiveHostStartVotingRequested()),
          child: starting
              ? Text(
                  organizeCopy('action.startingVoting'),
                  style: dbMono(13, Db.chalk),
                )
              : Text(
                  organizeCopy(action.labelKey),
                  style: dbMono(13, action.enabled ? Db.void_ : Db.mute),
                ),
        ),
      if (!starting && action?.disabledReasonKey != null) ...[
        const SizedBox(height: 8),
        Text(
          organizeCopy(action!.disabledReasonKey!),
          key: LiveHostConsole.startDisabledReasonKey,
          style: dbSans(12, 400, Db.mute),
        ),
      ],
    ],
  );

  Widget _pendingRow(
    PendingLiveVoter voter, {
    required bool busy,
    required bool enabled,
  }) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: Db.slate3,
      border: Border.all(color: Db.rule),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            voter.confirmationCode,
            style: dbMono(16, Db.chalk, wght: 600, letterSpacing: 2),
          ),
        ),
        OutlinedButton(
          key: Key('admit-${voter.confirmationCode}'),
          onPressed: (busy || !enabled)
              ? null
              : () => _machine.advance(
                  LiveHostConfirmRequested(voter.confirmationCode),
                ),
          child: busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('ADMIT', style: dbMono(11, Db.chalk)),
        ),
      ],
    ),
  );

  // ── voting phase ─────────────────────────────────────────────────────────

  Widget _voting({
    required int admitted,
    required int turnout,
    required bool closing,
  }) => ListView(
    padding: const EdgeInsets.fromLTRB(24, 16, 24, 96),
    children: [
      Text('VOTING IS OPEN', style: dbSectionTitle),
      const SizedBox(height: 6),
      Text(
        'The tally stays sealed until you close — this only counts '
        'ballots as they land.',
        style: dbSans(12, 400, Db.chalkDim, height: 1.5),
      ),
      const SizedBox(height: 24),
      Center(
        child: Text(
          '$turnout of $admitted',
          key: const Key('console-turnout'),
          style: dbHero(56),
        ),
      ),
      const SizedBox(height: 4),
      Center(child: Text('HAVE VOTED', style: dbLabel())),
      const SizedBox(height: 32),
      FilledButton(
        key: LiveHostConsole.closeKey,
        style: FilledButton.styleFrom(
          backgroundColor: Db.segnale,
          foregroundColor: Db.void_,
          shape: const RoundedRectangleBorder(),
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        onPressed: closing
            ? null
            : () => _machine.advance(const LiveHostCloseRequested()),
        child: Text(
          organizeCopy(closing ? 'action.closing' : 'action.closeVoting'),
          style: dbMono(13, closing ? Db.chalk : Db.void_),
        ),
      ),
    ],
  );

  // ── closed / failed ──────────────────────────────────────────────────────

  Widget _closed(LiveHostClosed closed) => ListView(
    padding: const EdgeInsets.fromLTRB(24, 16, 24, 96),
    children: [
      Text('VOTING CLOSED', style: dbSectionTitle),
      const SizedBox(height: 16),
      Text(
        '${closed.turnout} of ${closed.admitted} admitted voters cast a '
        'ballot. Results are on this poll’s dashboard card.',
        style: dbSans(13, 400, Db.chalkDim, height: 1.6),
      ),
      const SizedBox(height: 24),
      FilledButton(
        key: LiveHostConsole.doneKey,
        style: FilledButton.styleFrom(
          backgroundColor: Db.segnale,
          foregroundColor: Db.void_,
          shape: const RoundedRectangleBorder(),
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        onPressed: widget.onExit,
        child: Text('BACK TO YOUR POLLS', style: dbMono(13, Db.void_)),
      ),
    ],
  );

  Widget _failed(LiveHostFailed failed) {
    final cause = failed.cause;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 96),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Db.slate3,
            border: Border.all(color: Db.segnale),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                organizeCopy(failed.messageKey),
                style: dbSans(13, 500, Db.chalk, height: 1.5),
              ),
              if (cause != null) ...[
                const SizedBox(height: 8),
                Text(
                  '$cause',
                  key: const Key('console-failed-cause'),
                  style: dbSans(12, 400, Db.chalkDim, height: 1.5),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('console-retry'),
          style: FilledButton.styleFrom(
            backgroundColor: Db.segnale,
            foregroundColor: Db.void_,
            shape: const RoundedRectangleBorder(),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: () => _machine.advance(const Retry()),
          child: Text(
            organizeCopy('action.retry'),
            style: dbMono(12, Db.void_),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: widget.onExit,
          child: Text('LEAVE', style: dbMono(12, Db.chalk)),
        ),
      ],
    );
  }

  Widget _stat(String label, String value) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Db.slate3,
        border: Border.all(color: Db.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: dbLabel()),
          const SizedBox(height: 6),
          Text(value, style: dbMono(22, Db.chalk, wght: 600)),
        ],
      ),
    ),
  );
}
