import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../data/models/poll_snapshot.dart';
import '../../core/theme.dart';
import '../../core/view_state.dart';
import 'poll_detail_view_model.dart';

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
