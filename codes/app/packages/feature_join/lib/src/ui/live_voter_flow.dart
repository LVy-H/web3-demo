/// Live-voter flow (spec §4.2): a thin renderer over core_domain's
/// [LiveVoterMachine]. One widget, one switch — every machine state has
/// exactly one screen, and every screen offers only that state's legal
/// actions, so the UI cannot dispatch an illegal event by construction.
///
/// Copy rules (spec §3 principle 5): zero crypto jargon. The confirmation
/// code is "show this to the host"; proving is "generating your private
/// vote"; the receipt is "your receipt".
library;

import 'dart:async';

import 'package:core_domain/journeys/journey.dart';
import 'package:core_domain/journeys/live_journeys.dart';
import 'package:design_system/theme.dart';
import 'package:flutter/material.dart';

import 'qr_scan_sheet.dart';

/// Renders the live-voter journey for an already-constructed machine. The
/// host screen owns the machine's lifecycle (create on mount, dispose on
/// unmount); this widget only listens and dispatches.
class LiveVoterFlow extends StatefulWidget {
  final LiveVoterMachine machine;

  /// Router shim: receives a location string ('/you' for receipts, '/vote'
  /// after leaving). Injected so tests record navigations instead of
  /// needing a router.
  final ValueChanged<String> navigate;

  /// Test seam for the ticket scanner; defaults to the camera QR sheet.
  final Future<String?> Function(BuildContext context)? scanTicket;

  const LiveVoterFlow({
    super.key,
    required this.machine,
    required this.navigate,
    this.scanTicket,
  });

  @override
  State<LiveVoterFlow> createState() => _LiveVoterFlowState();
}

class _LiveVoterFlowState extends State<LiveVoterFlow> {
  StreamSubscription<LiveVoterState>? _sub;
  final TextEditingController _ticket = TextEditingController();
  int? _selectedOption;

  @override
  void initState() {
    super.initState();
    // "Left" is terminal with nothing to render — route home instead.
    _sub = widget.machine.states.listen((state) {
      if (state is LiveVoterLeft) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.navigate('/vote');
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticket.dispose();
    super.dispose();
  }

  /// All button taps funnel here. The machine throws [JourneyViolation] on
  /// an event that is illegal for the CURRENT state; with async handlers a
  /// stale tap (state advanced between render and tap) is reachable, so it
  /// is swallowed here — the rebuild that follows shows the new state's own
  /// actions. Anything else propagates (a real programming error).
  Future<void> _advance(JourneyEvent event) async {
    try {
      await widget.machine.advance(event);
    } on JourneyViolation {
      // Stale tap; the stream rebuild already rendered the new state.
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<LiveVoterState>(
      stream: widget.machine.states,
      initialData: widget.machine.state,
      builder: (context, snapshot) {
        final state = snapshot.data ?? widget.machine.state;
        return switch (state) {
          LiveVoterNeedsTicket() => _needsTicket(state),
          LiveVoterJoiningInProgress() => _wait('Joining the session…'),
          LiveVoterPending() => _pending(state),
          LiveVoterStalled() => _stalled(state),
          LiveVoterJoinFailed() => _joinFailed(state),
          LiveVoterAdmitted() => _wait('You’re in!'),
          LiveVoterWaitingForOpen() => _waitingForOpen(),
          LiveVoterBallotOpen() => _ballot(state),
          LiveVoterProvingInProgress() => _wait(
            'Generating your private vote (~10 s)…',
          ),
          LiveVoterCastInProgress() => _wait('Sending your vote…'),
          LiveVoterCastFailed() => _castFailed(),
          LiveVoterDone() => _done(state),
          LiveVoterLeft() => const SizedBox.shrink(),
        };
      },
    );
  }

  // ── needsTicket ──────────────────────────────────────────────────────

  Widget _needsTicket(LiveVoterNeedsTicket state) {
    return _Section(
      label: 'JOIN THE ROOM',
      children: [
        Text(
          'Scan the QR on the host’s screen, or paste the invite.',
          style: dbMono(12, Db.chalkDim, height: 1.5),
        ),
        const SizedBox(height: 20),
        if (state.capabilities.canScanQr) ...[
          _BigButton(
            key: const Key('live-scan-ticket'),
            icon: Icons.qr_code_scanner,
            label: 'SCAN THE HOST’S QR',
            onPressed: () async {
              final scan = widget.scanTicket ?? showJoinScanSheet;
              final raw = await scan(context);
              if (raw == null || raw.trim().isEmpty) return;
              await _advance(LiveTicketProvided(raw));
            },
          ),
          const SizedBox(height: 14),
        ],
        TextField(
          key: const Key('live-ticket-field'),
          controller: _ticket,
          style: dbMono(13, Db.chalk),
          decoration: InputDecoration(
            hintText: 'Paste the invite here',
            hintStyle: dbMono(13, Db.muteDim),
            filled: true,
            fillColor: Db.slate3,
            enabledBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: Db.rule),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: Db.segnale),
            ),
          ),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) unawaited(_advance(LiveTicketProvided(v)));
          },
        ),
        const SizedBox(height: 10),
        _GhostButton(
          key: const Key('live-ticket-join'),
          label: 'JOIN',
          onPressed: () {
            final v = _ticket.text;
            if (v.trim().isNotEmpty) unawaited(_advance(LiveTicketProvided(v)));
          },
        ),
      ],
    );
  }

  // ── pending: the BIG code ────────────────────────────────────────────

  Widget _pending(LiveVoterPending state) {
    return _Section(
      label: 'SHOW THIS TO THE HOST',
      children: [
        Center(
          child: Text(
            state.confirmationCode,
            key: const Key('live-confirmation-code'),
            style: dbMono(72, Db.chalk, wght: 700, letterSpacing: 18),
          ),
        ),
        const SizedBox(height: 24),
        const _Liveness(),
        const SizedBox(height: 10),
        Text(
          'The host checks your code and lets you in. Keep this screen open.',
          textAlign: TextAlign.center,
          style: dbMono(11, Db.muteDim, height: 1.5),
        ),
      ],
    );
  }

  // ── stalled: always a way out ────────────────────────────────────────

  Widget _stalled(LiveVoterStalled state) {
    final (title, body) = switch (state.reason) {
      LiveVoterStallReason.pendingTimeout => (
        'STILL WAITING…',
        'The host hasn’t let you in yet. Catch their attention and show '
            'your code again, or rejoin with a fresh QR.',
      ),
      LiveVoterStallReason.hostGone => (
        'CAN’T REACH THE HOST',
        'The session looks closed on the host’s side. Ask the host to '
            'reopen it, then rejoin.',
      ),
      LiveVoterStallReason.pollEnded => (
        'VOTING HAS ENDED',
        'This session closed before your vote went in.',
      ),
    };
    final canRetry = state.reason != LiveVoterStallReason.pollEnded;
    return _Section(
      label: title,
      accent: Db.amber,
      children: [
        Text(body, style: dbMono(12, Db.chalk, height: 1.55)),
        const SizedBox(height: 22),
        if (canRetry) ...[
          _BigButton(
            key: const Key('live-retry'),
            icon: Icons.refresh,
            label: 'TRY AGAIN',
            onPressed: () => _advance(const Retry()),
          ),
          const SizedBox(height: 10),
          _GhostButton(
            key: const Key('live-rescan'),
            label: 'SCAN A NEW QR',
            onPressed: () => _advance(const LiveRescanRequested()),
          ),
          const SizedBox(height: 10),
        ],
        _GhostButton(
          key: const Key('live-leave'),
          label: 'LEAVE',
          onPressed: () => _advance(const LiveLeaveRequested()),
        ),
      ],
    );
  }

  Widget _joinFailed(LiveVoterJoinFailed state) {
    return _Section(
      label: 'THAT INVITE DIDN’T WORK',
      accent: Db.segnale,
      children: [
        Text(
          'The invite may have expired — they only last a moment. '
          'Try again, or scan a fresh QR from the host’s screen.',
          style: dbMono(12, Db.chalk, height: 1.55),
        ),
        const SizedBox(height: 22),
        _BigButton(
          key: const Key('live-retry'),
          icon: Icons.refresh,
          label: 'TRY AGAIN',
          onPressed: () => _advance(const Retry()),
        ),
        const SizedBox(height: 10),
        _GhostButton(
          key: const Key('live-rescan'),
          label: 'SCAN A NEW QR',
          onPressed: () => _advance(const LiveRescanRequested()),
        ),
      ],
    );
  }

  // ── admitted / waiting ───────────────────────────────────────────────

  Widget _waitingForOpen() {
    return _Section(
      label: 'YOU’RE IN',
      accent: Db.success,
      children: [
        const Center(
          child: Icon(Icons.check_circle_outline, color: Db.success, size: 56),
        ),
        const SizedBox(height: 18),
        Text(
          'You’re in — waiting for the host to open voting.',
          key: const Key('live-waiting-copy'),
          textAlign: TextAlign.center,
          style: dbSans(15, 600, Db.chalk, height: 1.4),
        ),
        const SizedBox(height: 8),
        Text(
          'The ballot appears here by itself. Keep this screen open.',
          textAlign: TextAlign.center,
          style: dbMono(11, Db.muteDim, height: 1.5),
        ),
      ],
    );
  }

  // ── ballot ───────────────────────────────────────────────────────────

  Widget _ballot(LiveVoterBallotOpen state) {
    final action = state.nextAction;
    final selected = _selectedOption;
    final castEnabled = (action?.enabled ?? false) && selected != null;
    return _Section(
      label: 'CAST YOUR VOTE',
      children: [
        for (var i = 0; i < state.admission.options.length; i++) ...[
          _OptionRow(
            key: Key('live-option-$i'),
            index: i,
            label: state.admission.options[i],
            selected: selected == i,
            onTap: () => setState(() => _selectedOption = i),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 14),
        _BigButton(
          key: const Key('live-cast'),
          icon: Icons.how_to_vote,
          label: 'CAST VOTE',
          onPressed: castEnabled
              ? () => _advance(LiveCastRequested(selected))
              : null,
        ),
        if (action != null && !action.enabled) ...[
          const SizedBox(height: 10),
          Text(
            'Voting from this device isn’t supported yet — use the web '
            'or an Android phone.',
            style: dbMono(11, Db.amber, height: 1.5),
          ),
        ],
        const SizedBox(height: 10),
        Text(
          'Your vote is private — nobody can see which option you picked.',
          style: dbMono(11, Db.muteDim, height: 1.5),
        ),
      ],
    );
  }

  Widget _castFailed() {
    return _Section(
      label: 'YOUR VOTE DIDN’T GO THROUGH',
      accent: Db.segnale,
      children: [
        Text(
          'Nothing was counted. Check your connection and try again.',
          style: dbMono(12, Db.chalk, height: 1.55),
        ),
        const SizedBox(height: 22),
        _BigButton(
          key: const Key('live-retry'),
          icon: Icons.refresh,
          label: 'TRY AGAIN',
          onPressed: () => _advance(const Retry()),
        ),
      ],
    );
  }

  // ── done ─────────────────────────────────────────────────────────────

  Widget _done(LiveVoterDone state) {
    return _Section(
      label: 'VOTE COUNTED',
      accent: Db.success,
      children: [
        const Center(
          child: Icon(Icons.verified_outlined, color: Db.success, size: 56),
        ),
        const SizedBox(height: 18),
        Text(
          'Your vote is in.',
          textAlign: TextAlign.center,
          style: dbSans(18, 800, Db.chalk),
        ),
        const SizedBox(height: 14),
        Text('YOUR RECEIPT', style: dbLabel()),
        const SizedBox(height: 6),
        Text(
          state.txHash,
          key: const Key('live-receipt'),
          style: dbMono(11, Db.chalkDim, height: 1.4),
        ),
        const SizedBox(height: 22),
        _BigButton(
          key: const Key('live-receipts'),
          icon: Icons.receipt_long,
          label: 'SEE YOUR RECEIPTS',
          onPressed: () => widget.navigate('/you'),
        ),
      ],
    );
  }

  // ── shared chrome ────────────────────────────────────────────────────

  Widget _wait(String message) {
    return _Section(
      label: 'ONE MOMENT',
      children: [
        const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Db.segnale,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          message,
          textAlign: TextAlign.center,
          style: dbMono(12, Db.chalkDim, height: 1.5),
        ),
      ],
    );
  }
}

class _Liveness extends StatelessWidget {
  const _Liveness();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2, color: Db.segnale),
        ),
        const SizedBox(width: 10),
        Text(
          'Waiting for the host to let you in…',
          style: dbMono(12, Db.chalkDim),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String label;
  final Color accent;
  final List<Widget> children;

  const _Section({
    required this.label,
    required this.children,
    this.accent = Db.segnale,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: dbLabel(size: 11, color: accent, tracking: 0.16)),
        const SizedBox(height: 18),
        ...children,
      ],
    );
  }
}

class _BigButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const _BigButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: Db.segnale,
        disabledBackgroundColor: Db.slate4,
        foregroundColor: Db.void_,
        disabledForegroundColor: Db.mute,
        shape: const RoundedRectangleBorder(),
        padding: const EdgeInsets.symmetric(vertical: 18),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label, style: dbMono(13, Db.void_, wght: 700)),
    );
  }
}

class _GhostButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _GhostButton({super.key, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: Db.chalkDim,
        side: const BorderSide(color: Db.rule),
        shape: const RoundedRectangleBorder(),
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
      child: Text(label, style: dbMono(12, Db.chalkDim, wght: 600)),
    );
  }
}

class _OptionRow extends StatelessWidget {
  final int index;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _OptionRow({
    super.key,
    required this.index,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = Db.optionColor(index);
    return Material(
      color: selected ? Db.slate : Db.slate3,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: selected ? color : Db.rule),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected ? color : Db.mute,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: dbSans(15, 600, Db.chalk))),
            ],
          ),
        ),
      ),
    );
  }
}
