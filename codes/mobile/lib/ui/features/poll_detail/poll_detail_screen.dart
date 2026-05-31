import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../data/models/poll_snapshot.dart';
import '../../../data/services/proof_service_factory.dart';
import '../../core/theme.dart';
import '../../core/view_state.dart';
import 'poll_detail_view_model.dart';
import 'vote_view_model.dart';

/// Poll detail — live phase, options, vote tally, participant count. Read-only
/// (voting needs the ProofService, landing later).
class PollDetailScreen extends StatefulWidget {
  final String address;
  const PollDetailScreen({super.key, required this.address});

  @override
  State<PollDetailScreen> createState() => _PollDetailScreenState();
}

class _PollDetailScreenState extends State<PollDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PollDetailViewModel>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
        title: const Text('Poll'),
      ),
      body: Consumer<PollDetailViewModel>(
        builder: (context, vm, _) => switch (vm.state) {
          ViewState.idle ||
          ViewState.loading =>
            const Center(child: CircularProgressIndicator(color: Db.segnale)),
          ViewState.error => _ErrorView(
              message: vm.error ?? 'Unknown error', onRetry: vm.load),
          ViewState.loaded => _PollBody(snapshot: vm.snapshot!),
        },
      ),
    );
  }
}

class _PollBody extends StatelessWidget {
  final PollSnapshot snapshot;
  const _PollBody({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final total = snapshot.totalVotes;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _PhaseBadge(state: snapshot.state, label: snapshot.phaseLabel),
        const SizedBox(height: 16),
        Text(snapshot.address, style: dbMonoLabel),
        const SizedBox(height: 4),
        Text(
          '${snapshot.participantCount} registered · $total votes cast',
          style: const TextStyle(color: Db.chalkDim, fontSize: 13),
        ),
        const SizedBox(height: 24),
        const Text('RESULTS',
            style: TextStyle(
                fontFamily: Db.fontMono,
                fontSize: 11,
                letterSpacing: 1.6,
                color: Db.mute)),
        const SizedBox(height: 12),
        for (var i = 0; i < snapshot.options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ResultBar(
              label: snapshot.options[i],
              count: i < snapshot.results.length
                  ? snapshot.results[i]
                  : BigInt.zero,
              total: total,
              color: _barColor(i),
            ),
          ),
        if (snapshot.state == 1) ...[
          const SizedBox(height: 20),
          _VoteArea(options: snapshot.options),
        ],
        const SizedBox(height: 16),
        const Divider(color: Db.rule),
        const SizedBox(height: 8),
        const Text('OWNER',
            style: TextStyle(
                fontFamily: Db.fontMono,
                fontSize: 10,
                letterSpacing: 1.4,
                color: Db.mute)),
        const SizedBox(height: 4),
        Text(snapshot.owner, style: dbMonoLabel),
      ],
    );
  }

  static const _palette = [
    Db.oltremare,
    Db.segnale,
    Db.success,
    Color(0xFF8A7359),
    Color(0xFF946B87),
  ];
  Color _barColor(int i) => _palette[i % _palette.length];
}

class _PhaseBadge extends StatelessWidget {
  final int state;
  final String label;
  const _PhaseBadge({required this.state, required this.label});

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      0 => Db.oltremare, // Registration
      1 => Db.segnale, // Voting
      2 => Db.mute, // Ended
      _ => Db.mute,
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            fontFamily: Db.fontMono,
            fontSize: 11,
            letterSpacing: 1.6,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    );
  }
}

class _ResultBar extends StatelessWidget {
  final String label;
  final BigInt count;
  final BigInt total;
  final Color color;
  const _ResultBar({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
  });

  double get _fraction =>
      total == BigInt.zero ? 0 : count / total;

  int get _pct => (_fraction * 100).round();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      color: Db.chalk, fontWeight: FontWeight.w600)),
            ),
            Text('$count · $_pct%', style: dbMonoLabel),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Stack(
            children: [
              Container(height: 8, color: Db.ruleSoft),
              FractionallySizedBox(
                widthFactor: _fraction.clamp(0.0, 1.0),
                child: Container(height: 8, color: color),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, color: Db.segnale, size: 40),
              const SizedBox(height: 12),
              const Text("Couldn't load this poll",
                  style:
                      TextStyle(color: Db.chalk, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Db.mute, fontSize: 13)),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      );
}

/// Vote area shown during the Voting phase. On platforms without client-side
/// proving (native/desktop now) it shows a read-only note instead of the form.
class _VoteArea extends StatelessWidget {
  final List<String> options;
  const _VoteArea({required this.options});

  @override
  Widget build(BuildContext context) {
    if (!proofServiceAvailable) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: Db.rule),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          children: [
            Icon(Icons.lock_outline, color: Db.mute, size: 18),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Voting runs in the web app (mobile coming soon). This build is read-only.',
                style: TextStyle(color: Db.mute, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }
    return _VoteForm(options: options);
  }
}

class _VoteForm extends StatefulWidget {
  final List<String> options;
  const _VoteForm({required this.options});
  @override
  State<_VoteForm> createState() => _VoteFormState();
}

class _VoteFormState extends State<_VoteForm> {
  final _seed = TextEditingController();
  int? _selected;

  @override
  void dispose() {
    _seed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<VoteViewModel>();
    final canCast =
        _selected != null && _seed.text.trim().isNotEmpty && !vm.isBusy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('CAST YOUR VOTE',
            style: TextStyle(
                fontFamily: Db.fontMono,
                fontSize: 11,
                letterSpacing: 1.6,
                color: Db.mute)),
        const SizedBox(height: 10),
        for (var i = 0; i < widget.options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _OptionTile(
              label: widget.options[i],
              selected: _selected == i,
              onTap: vm.isBusy ? null : () => setState(() => _selected = i),
            ),
          ),
        const SizedBox(height: 8),
        TextField(
          controller: _seed,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(
              color: Db.chalk, fontFamily: Db.fontMono, fontSize: 13),
          decoration: const InputDecoration(
            labelText: 'Your invite token / identity seed',
            labelStyle: TextStyle(color: Db.mute),
            enabledBorder:
                OutlineInputBorder(borderSide: BorderSide(color: Db.rule)),
            focusedBorder:
                OutlineInputBorder(borderSide: BorderSide(color: Db.oltremare)),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Db.segnale, foregroundColor: Db.chalk),
            onPressed: canCast
                ? () => context.read<VoteViewModel>().castVote(
                      identitySeed: _seed.text.trim(),
                      optionIndex: _selected!,
                    )
                : null,
            child: Text(switch (vm.status) {
              VoteStatus.proving => 'Generating proof…',
              VoteStatus.relaying => 'Submitting…',
              _ => 'Cast anonymous vote',
            }),
          ),
        ),
        if (vm.status == VoteStatus.success)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _StatusLine(
                icon: Icons.check_circle,
                color: Db.success,
                text: 'Vote counted · ${vm.txHash ?? ''}'),
          ),
        if (vm.status == VoteStatus.error)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _StatusLine(
                icon: Icons.error_outline,
                color: Db.segnale,
                text: vm.error ?? 'Vote failed'),
          ),
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  const _OptionTile(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(
              color: selected ? Db.segnale : Db.rule, width: selected ? 2 : 1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected ? Db.segnale : Db.mute,
                size: 18),
            const SizedBox(width: 10),
            Expanded(
                child: Text(label, style: const TextStyle(color: Db.chalk))),
          ],
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _StatusLine(
      {required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
              child:
                  Text(text, style: TextStyle(color: color, fontSize: 13))),
        ],
      );
}
