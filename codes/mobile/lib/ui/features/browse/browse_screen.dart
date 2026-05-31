import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../data/models/poll_info.dart';
import '../../core/theme.dart';
import '../../core/view_state.dart';
import 'browse_view_model.dart';

/// Browse all polls (the member app's home). Reads [BrowseViewModel] from the
/// widget tree and renders loading / error / empty / list states.
class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key});

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  @override
  void initState() {
    super.initState();
    // Kick the initial load after first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BrowseViewModel>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Polls',
            style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.5)),
      ),
      body: Consumer<BrowseViewModel>(
        builder: (context, vm, _) => switch (vm.state) {
          ViewState.idle ||
          ViewState.loading =>
            const Center(child: CircularProgressIndicator(color: Db.segnale)),
          ViewState.error => _ErrorView(
              message: vm.error ?? 'Unknown error',
              onRetry: vm.load,
            ),
          ViewState.loaded => vm.polls.isEmpty
              ? const _EmptyView()
              : RefreshIndicator(
                  color: Db.segnale,
                  onRefresh: vm.load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: vm.polls.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _PollCard(poll: vm.polls[i]),
                  ),
                ),
        },
      ),
    );
  }
}

class _PollCard extends StatelessWidget {
  final PollInfo poll;
  const _PollCard({required this.poll});

  String get _shortAddr {
    final a = poll.pollAddress;
    return a.length > 12 ? '${a.substring(0, 6)}…${a.substring(a.length - 4)}' : a;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.go('/poll/${poll.pollAddress}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _ModuleChip(moduleType: poll.moduleType),
                  const Spacer(),
                  Text(_shortAddr, style: dbMonoLabel),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                poll.title.isEmpty ? '(untitled)' : poll.title,
                style: const TextStyle(
                  color: Db.chalk,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (poll.description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  poll.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Db.chalkDim, fontSize: 14),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ModuleChip extends StatelessWidget {
  final String moduleType;
  const _ModuleChip({required this.moduleType});

  @override
  Widget build(BuildContext context) {
    final isAnon = moduleType == 'anon-vote';
    final color = isAnon ? Db.oltremare : Db.success;
    final label = isAnon ? 'ANONYMOUS' : 'BLIND';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: Db.fontMono,
          fontSize: 10,
          letterSpacing: 1.4,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();
  @override
  Widget build(BuildContext context) => const Center(
        child: Text('No polls yet', style: TextStyle(color: Db.mute)),
      );
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
              const Text("Couldn't load polls",
                  style: TextStyle(color: Db.chalk, fontWeight: FontWeight.w700)),
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
