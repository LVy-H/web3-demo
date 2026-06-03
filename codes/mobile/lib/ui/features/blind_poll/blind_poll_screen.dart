import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/models/blind_snapshot.dart';
import '../../core/dot_grid_background.dart';
import '../../core/format.dart';
import '../../core/poll_header.dart';
import '../../core/theme.dart';
import '../../core/view_state.dart';
import '../../widgets/results_bars.dart';
import 'blind_poll_view_model.dart';

/// M2 blind (commit-reveal) poll detail. Shows phase + revealed tally and drives
/// the lifecycle: register → commit (hidden) → reveal, plus the owner's start /
/// end / finalize. Writes go through the dev-signer; read-only without one.
class BlindPollScreen extends StatefulWidget {
  final String address;
  const BlindPollScreen({super.key, required this.address});
  @override
  State<BlindPollScreen> createState() => _BlindPollScreenState();
}

class _BlindPollScreenState extends State<BlindPollScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => context.read<BlindPollViewModel>().load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DotGridBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: Consumer<BlindPollViewModel>(
                builder: (context, vm, _) => switch (vm.state) {
                  ViewState.idle || ViewState.loading => const Center(
                      child: CircularProgressIndicator(color: Db.segnale)),
                  ViewState.error => _Error(
                      message: vm.error ?? 'Unknown error', onRetry: vm.load),
                  ViewState.loaded => _Body(vm: vm),
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final BlindPollViewModel vm;
  const _Body({required this.vm});

  @override
  Widget build(BuildContext context) {
    final s = vm.snapshot!;
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(context, s),
            const SizedBox(height: 20),
            _PhaseStrip(state: s.state),
            const SizedBox(height: 16),
            Text(
              '${s.participantCount} REGISTERED · ${s.totalRevealed} REVEALED',
              style: dbLabel(size: 11, tracking: 0.1),
            ),
            const SizedBox(height: 24),
            LayoutBuilder(builder: (context, c) {
              final results = _ResultsBars(snapshot: s);
              final action = _ActionPanel(vm: vm);
              if (c.maxWidth > 840) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: results),
                    const SizedBox(width: 16),
                    Expanded(child: action),
                  ],
                );
              }
              return Column(children: [
                results,
                const SizedBox(height: 20),
                action,
              ]);
            }),
            const SizedBox(height: 24),
            Text('OWNER', style: dbLabel(size: 10)),
            const SizedBox(height: 4),
            Text(s.owner, style: dbMono(11, Db.mute, letterSpacing: 0.4)),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, BlindSnapshot s) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 12),
        child: pollDetailHeaderRow(
          context: context,
          badgeLabel: 'BLIND · COMMIT-REVEAL',
          badgeColor: Db.amber,
          shortAddr: shortAddr(s.address),
        ),
      );
}

class _PhaseStrip extends StatelessWidget {
  final int state;
  const _PhaseStrip({required this.state});
  static const _labels = ['REGISTRATION', 'VOTING', 'ENDED'];

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
            border: Border.fromBorderSide(BorderSide(color: Db.rule))),
        child: Row(children: [
          for (var i = 0; i < 3; i++)
            Expanded(
              child: Container(
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: i == state
                      ? Db.amber
                      : (i < state ? Db.slate : Db.void_),
                  border: i < 2
                      ? const Border(right: BorderSide(color: Db.rule))
                      : null,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(_labels[i],
                      style: dbSans(11, 800,
                          i == state ? Db.void_ : Db.mute,
                          letterSpacing: 11 * 0.16)),
                ),
              ),
            ),
        ]),
      );
}

class _ResultsBars extends StatelessWidget {
  final BlindSnapshot snapshot;
  const _ResultsBars({required this.snapshot});
  @override
  Widget build(BuildContext context) {
    final total = snapshot.totalRevealed;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Db.slate,
        border: Border.fromBorderSide(BorderSide(color: Db.rule)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          resultsTitleRow(
              icon: Icons.bar_chart,
              title: 'REVEALED TALLY',
              trailing: '$total REVEALED'),
          const SizedBox(height: 18),
          ResultsBars(
            options: [
              for (var i = 0; i < snapshot.options.length; i++)
                (
                  label: snapshot.options[i],
                  count: i < snapshot.results.length
                      ? snapshot.results[i]
                      : BigInt.zero,
                ),
            ],
            total: total,
            // Reveal-specific copy in place of the generic "No votes yet" so the
            // zero state explains *why* the tally is empty.
            emptyLabel: 'Votes are hidden until voters reveal after voting ends.',
          ),
        ],
      ),
    );
  }
}

/// Phase-aware action surface. Stateful only for the option selection used by
/// the commit step.
class _ActionPanel extends StatefulWidget {
  final BlindPollViewModel vm;
  const _ActionPanel({required this.vm});
  @override
  State<_ActionPanel> createState() => _ActionPanelState();
}

class _ActionPanelState extends State<_ActionPanel> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    final s = vm.snapshot!;
    final isOwner = s.isOwner(vm.signer);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Db.slate,
        border: Border.fromBorderSide(BorderSide(color: Db.rule)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('YOUR ACTIONS', style: dbSectionTitle),
        const SizedBox(height: 14),
        if (!vm.canWrite)
          _info(Icons.lock_outline,
              'Read-only. Set a dev signer (DEV_PRIVATE_KEY) or connect a wallet to act.')
        else ...[
          ..._phaseActions(vm, s, isOwner),
        ],
        if (vm.actionMsg != null)
          _line(Icons.check_circle, Db.success, vm.actionMsg!),
        if (vm.actionError != null)
          _line(Icons.error_outline, Db.amber, vm.actionError!),
      ]),
    );
  }

  List<Widget> _phaseActions(
      BlindPollViewModel vm, BlindSnapshot s, bool isOwner) {
    switch (s.state) {
      case 0: // Registration
        return [
          if (!s.registered)
            _button('REGISTER TO VOTE', vm.busy ? null : vm.register)
          else
            _info(Icons.how_to_reg, 'You are registered.'),
          if (isOwner) ...[
            const SizedBox(height: 10),
            _button('START VOTING (OWNER)', vm.busy ? null : vm.startVoting,
                secondary: true),
          ],
        ];
      case 1: // Voting
        return [
          if (s.registered && !s.committed) ...[
            for (var i = 0; i < s.options.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _OptionTile(
                label: s.options[i],
                color: Db.optionColor(i),
                selected: _selected == i,
                onTap: vm.busy ? null : () => setState(() => _selected = i),
              ),
            ],
            const SizedBox(height: 14),
            _button(
              'COMMIT VOTE',
              (_selected != null && !vm.busy)
                  ? () => vm.commit(_selected!)
                  : null,
            ),
          ] else if (s.committed)
            _info(Icons.lock, 'Vote committed — hidden until you reveal.')
          else
            _info(Icons.block, 'Registration closed; you are not registered.'),
          if (isOwner) ...[
            const SizedBox(height: 10),
            _button('END VOTING (OWNER)', vm.busy ? null : vm.endVoting,
                secondary: true),
          ],
        ];
      default: // Ended
        return [
          if (s.committed && !s.revealed) ...[
            if (vm.hasSavedCommit)
              _button('REVEAL MY VOTE', vm.busy ? null : vm.reveal)
            else
              _info(Icons.help_outline,
                  "This device has no saved salt — reveal where you committed."),
          ] else if (s.revealed)
            _info(Icons.check_circle, 'Your vote is revealed and tallied.')
          else
            _info(Icons.info_outline, 'You have no committed vote to reveal.'),
          if (s.finalized) ...[
            const SizedBox(height: 10),
            _info(Icons.verified, 'Results finalized.'),
          ] else if (isOwner) ...[
            const SizedBox(height: 10),
            _button('FINALIZE RESULTS (OWNER)', vm.busy ? null : vm.finalize,
                secondary: true),
          ],
        ];
    }
  }

  Widget _button(String label, VoidCallback? onTap, {bool secondary = false}) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: secondary ? Db.void_ : (enabled ? Db.amber : Db.void_),
          border: Border.all(
              color: enabled ? (secondary ? Db.rule : Db.amber) : Db.rule),
        ),
        child: Text(label,
            style: dbSans(
                12,
                800,
                secondary ? Db.chalkDim : (enabled ? Db.void_ : Db.mute),
                letterSpacing: 1.2)),
      ),
    );
  }

  Widget _info(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: Db.mute),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: dbMono(12, Db.chalkDim, height: 1.5))),
        ]),
      );

  Widget _line(IconData icon, Color color, String text) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: dbMono(12, color, height: 1.4))),
        ]),
      );
}

class _OptionTile extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;
  const _OptionTile(
      {required this.label,
      required this.color,
      required this.selected,
      required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.12) : Db.void_,
            border: Border.all(
                color: selected ? color : Db.rule, width: selected ? 2 : 1),
          ),
          child: Row(children: [
            Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected ? color : Db.mute,
                size: 18),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: dbSans(15, 600, Db.chalk))),
          ]),
        ),
      );
}

class _Error extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _Error({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off, color: Db.amber, size: 40),
            const SizedBox(height: 12),
            Text("COULDN'T LOAD THIS POLL",
                style: dbLabel(size: 12, color: Db.chalk)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: dbMono(12, Db.mute)),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                shape: const RoundedRectangleBorder(),
                side: const BorderSide(color: Db.rule),
              ),
              child: Text('RETRY', style: dbLabel(size: 11, color: Db.chalk)),
            ),
          ]),
        ),
      );
}
