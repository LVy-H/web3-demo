/// The sealed-until-reveal (commit–reveal) poll surface: a thin renderer of
/// the [BlindJourneyMachine]'s current state.
///
/// The audit fixes render as structure: the vote-key backup gate blocks
/// everything until acknowledged, the confirmation deadline is a live
/// countdown enforced client-side, and the unrecoverable cases are honest
/// panels — never generic errors.
library;

import 'dart:async';

import 'package:core_domain/journeys/blind_journey.dart';
import 'package:core_domain/journeys/journey.dart';
import 'package:core_domain/journeys/voter_journey.dart' show SingleChoice;
import 'package:design_system/theme.dart';
import 'package:design_system/widgets/results_bars.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../copy.dart';
import '../widgets/ballots/ballots.dart';
import '../widgets/vote_chrome.dart';

class BlindJourneyScreen extends StatefulWidget {
  final BlindJourneyMachine machine;
  final String title;

  /// Loads the poll's option labels for the lock-in ballot.
  final Future<List<String>> Function() loadOptions;

  /// Loads `(options, revealed tally)` for the final results panel.
  final Future<(List<String>, List<BigInt>)> Function()? loadTally;

  const BlindJourneyScreen({
    super.key,
    required this.machine,
    required this.title,
    required this.loadOptions,
    this.loadTally,
  });

  static const saltGateKey = Key('blind-salt-gate');
  static const saltCopyKey = Key('blind-salt-copy');
  static const saltAckKey = Key('blind-salt-acknowledge');
  static const countdownKey = Key('blind-reveal-countdown');

  @override
  State<BlindJourneyScreen> createState() => _BlindJourneyScreenState();
}

class _BlindJourneyScreenState extends State<BlindJourneyScreen> {
  StreamSubscription<BlindState>? _sub;
  Timer? _countdown;
  Future<List<String>>? _options;
  Future<(List<String>, List<BigInt>)>? _tally;
  int? _selectedOption;

  BlindJourneyMachine get machine => widget.machine;

  @override
  void initState() {
    super.initState();
    _sub = machine.states.listen((_) {
      if (mounted) setState(_syncCountdown);
    });
    _syncCountdown();
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  /// One ticking timer, alive exactly while the reveal window is open: keeps
  /// the countdown honest and dispatches [Timeout] the moment it expires —
  /// client-side deadline enforcement, not an on-chain surprise.
  void _syncCountdown() {
    final state = machine.state;
    if (state is BlindRevealWindow) {
      _countdown ??= Timer.periodic(const Duration(seconds: 1), (_) {
        final s = machine.state;
        if (s is! BlindRevealWindow) return;
        if (s.isExpired) {
          unawaited(machine.advance(const Timeout()));
        } else if (mounted) {
          setState(() {});
        }
      });
    } else {
      _countdown?.cancel();
      _countdown = null;
    }
  }

  void _advance(JourneyEvent event) => unawaited(machine.advance(event));

  bool get _canRefresh => switch (machine.state) {
    BlindRegistered() ||
    BlindVotingOpen() ||
    BlindCommitted() ||
    BlindRevealed() => true,
    _ => false,
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      backgroundColor: Colors.transparent,
      actions: [
        if (_canRefresh)
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh, size: 20, color: Db.mute),
            onPressed: () => _advance(const Refresh()),
          ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
          children: [
            Text(
              'SEALED UNTIL REVEAL',
              style: dbLabel(size: 10, color: Db.segnale),
            ),
            const SizedBox(height: 6),
            Text(
              widget.title.isEmpty ? 'VOTE' : widget.title,
              style: dbSans(28, 800, Db.chalk, height: 1.05),
            ),
            const SizedBox(height: 8),
            Text(
              'Choices stay hidden until everyone confirms after voting '
              'closes. Heads up: your confirmed choice becomes public at '
              'the end.',
              style: dbMono(10, Db.mute, height: 1.5),
            ),
            const SizedBox(height: 18),
            ..._body(machine.state),
          ],
        ),
      ),
    ),
    // The ONE primary action stays pinned — never scrolled out of reach.
    bottomNavigationBar: switch (_footerAction(machine.state)) {
      null => null,
      final action => SafeArea(
        minimum: const EdgeInsets.fromLTRB(24, 8, 24, 20),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: action,
          ),
        ),
      ),
    },
  );

  Widget? _footerAction(BlindState state) => switch (state) {
    BlindRegistrationOpen(:final nextAction) => PrimaryActionButton(
      action: nextAction!,
      onPressed: () => _advance(const BlindRegisterRequested()),
    ),
    BlindRegistered(:final nextAction) => PrimaryActionButton(
      action: nextAction!,
      onPressed: null,
    ),
    BlindVotingOpen() => PrimaryActionButton(
      action: _selectedOption == null
          ? const NextAction(
              labelKey: 'action.commitVote',
              type: NextActionType.submit,
              disabledReasonKey: 'reason.noSelection',
            )
          : const NextAction(
              labelKey: 'action.commitVote',
              type: NextActionType.submit,
            ),
      onPressed: _selectedOption == null
          ? null
          : () => _advance(BlindCommitRequested(_selectedOption!)),
    ),
    BlindCommitted(:final backupAcknowledged) when backupAcknowledged =>
      PrimaryActionButton(action: state.nextAction!, onPressed: null),
    BlindRevealWindow(:final nextAction) => PrimaryActionButton(
      action: nextAction!,
      onPressed: state.isExpired
          ? null
          : () => _advance(const BlindRevealRequested()),
    ),
    BlindRevealed(:final nextAction) => PrimaryActionButton(
      action: nextAction!,
      onPressed: null,
    ),
    _ => null,
  };

  List<Widget> _body(BlindState state) => switch (state) {
    BlindLoadInProgress() => const [ProgressPanel(title: 'LOADING THIS VOTE…')],
    BlindRegisterInProgress() => const [ProgressPanel(title: 'JOINING…')],
    BlindCommitInProgress() => const [
      ProgressPanel(title: 'LOCKING IN YOUR VOTE…'),
    ],
    BlindRevealCheckInProgress() => const [
      ProgressPanel(title: 'CHECKING THE CONFIRMATION WINDOW…'),
    ],
    BlindRevealInProgress() => const [
      ProgressPanel(title: 'CONFIRMING YOUR VOTE…'),
    ],
    BlindRegistrationOpen() => [
      VotePanel(
        child: Text(
          'Join now — voting opens once the organizer starts it.',
          style: dbMono(11, Db.mute, height: 1.6),
        ),
      ),
    ],
    BlindRegistered() => [
      VotePanel(
        child: Text(
          'You’re in. Voting hasn’t opened yet — refresh to check.',
          style: dbMono(11, Db.mute, height: 1.6),
        ),
      ),
    ],
    BlindVotingOpen() => [
      const VoteSectionLabel('PICK ONE OPTION'),
      _optionsBallot(),
    ],
    BlindCommitted(:final receipt, :final backupAcknowledged) =>
      backupAcknowledged
          ? [
              VotePanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'LOCKED IN',
                      style: dbSans(13, 800, Db.success, letterSpacing: 0.8),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Your choice is sealed. When voting closes, come back '
                      'to confirm it so it counts.',
                      style: dbMono(11, Db.mute, height: 1.6),
                    ),
                  ],
                ),
              ),
            ]
          : [_saltGate(receipt!)],
    BlindRevealWindow(:final remaining) => [
      VotePanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'CONFIRM YOUR VOTE SO IT COUNTS',
              style: dbSans(13, 800, Db.chalk, letterSpacing: 0.8),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.timer_outlined, size: 16, color: Db.segnale),
                const SizedBox(width: 8),
                Text(
                  'TIME LEFT  ${_fmt(remaining)}',
                  key: BlindJourneyScreen.countdownKey,
                  style: dbMono(13, Db.segnale, wght: 700, letterSpacing: 1),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'If the window closes before you confirm, your vote can’t be '
              'counted.',
              style: dbMono(11, Db.mute, height: 1.5),
            ),
          ],
        ),
      ),
    ],
    BlindRevealed() => [
      VotePanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'YOUR VOTE IS CONFIRMED',
              style: dbSans(13, 800, Db.success, letterSpacing: 0.8),
            ),
            const SizedBox(height: 6),
            Text(
              'Waiting for the organizer to publish the final results.',
              style: dbMono(11, Db.mute, height: 1.6),
            ),
          ],
        ),
      ),
    ],
    BlindResults() => [_tallyCard()],
    BlindMissedReveal(:final copyKey) => [_honestEnd(copyKey)],
    BlindSaltMissing(:final copyKey) => [_honestEnd(copyKey)],
    BlindCannotParticipate(:final copyKey) => [_honestEnd(copyKey)],
    final JourneyErrorState error => [
      ErrorPanel(
        messageKey: error.messageKey,
        onRetry: () => _advance(error.recoveryEvent),
      ),
    ],
  };

  Widget _optionsBallot() {
    _options ??= widget.loadOptions();
    return FutureBuilder<List<String>>(
      future: _options,
      builder: (context, snap) {
        final options = snap.data;
        if (options == null) {
          return const ProgressPanel(title: 'LOADING OPTIONS…');
        }
        return SingleChoiceBallot(
          options: options,
          initial: _selectedOption == null
              ? null
              : SingleChoice(_selectedOption!),
          onChanged: (spec) => setState(
            () => _selectedOption = (spec as SingleChoice?)?.optionIndex,
          ),
        );
      },
    );
  }

  /// The vote-key backup gate: the salt exists ONLY on this device, and the
  /// journey will not move on until the voter saves or acknowledges it.
  Widget _saltGate(SaltReceipt receipt) => VotePanel(
    key: BlindJourneyScreen.saltGateKey,
    color: Db.slate3,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.key, size: 18, color: Db.amber),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'SAVE YOUR VOTE KEY',
                style: dbSans(14, 800, Db.chalk, letterSpacing: 0.8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'This key confirms your vote after voting closes. It exists ONLY '
          'on this device — if you lose it, your vote can never be counted. '
          'Copy it somewhere safe now.',
          style: dbMono(11, Db.chalkDim, height: 1.6),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Db.void_,
            border: Border.all(color: Db.rule),
          ),
          child: Text(
            receipt.saltHex,
            style: dbMono(11, Db.chalk, height: 1.5),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            OutlinedButton.icon(
              key: BlindJourneyScreen.saltCopyKey,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: receipt.saltHex));
                _advance(const BlindExportSaltRequested());
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: Db.segnale,
                side: const BorderSide(color: Db.segnale),
                shape: const RoundedRectangleBorder(),
              ),
              icon: const Icon(Icons.copy, size: 14),
              label: Text('COPY KEY', style: dbMono(11, Db.segnale, wght: 700)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                key: BlindJourneyScreen.saltAckKey,
                onTap: () => _advance(const BlindSaltBackupAcknowledged()),
                child: Container(
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Db.void_,
                    border: Border.all(color: Db.rule),
                  ),
                  child: Text(
                    'I’VE SAVED IT',
                    style: dbSans(11, 800, Db.chalkDim, letterSpacing: 1),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _tallyCard() {
    final loader = widget.loadTally;
    if (loader == null) {
      return VotePanel(
        child: Text(
          'The final results are published.',
          style: dbMono(11, Db.mute, height: 1.6),
        ),
      );
    }
    _tally ??= loader();
    return FutureBuilder<(List<String>, List<BigInt>)>(
      future: _tally,
      builder: (context, snap) {
        final data = snap.data;
        if (data == null) {
          return const ProgressPanel(title: 'LOADING RESULTS…');
        }
        final (options, counts) = data;
        return VotePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const VoteSectionLabel('FINAL RESULTS'),
              ResultsBars(
                options: [
                  for (var i = 0; i < options.length; i++)
                    (
                      label: options[i],
                      count: i < counts.length ? counts[i] : BigInt.zero,
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _honestEnd(String copyKey) => VotePanel(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.block, size: 18, color: Db.mute),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            voteCopy(copyKey),
            style: dbSans(13, 600, Db.chalkDim, height: 1.5),
          ),
        ),
      ],
    ),
  );

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}
