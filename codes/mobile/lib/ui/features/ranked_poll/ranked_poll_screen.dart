import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../data/models/poll_snapshot.dart';
import '../../../data/services/identity_store.dart';
import '../../../data/services/proof_service_factory.dart';
import '../../core/dot_grid_background.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/view_state.dart';
import '../../widgets/results_bars.dart';
import 'ranked_vote_view_model.dart';

/// Ranked-choice (instant-runoff) poll detail (module `ranked-vote`) — Dark
/// Bauhaus. A sibling of the M3 approval surface, with one behavioral
/// difference: the ballot is an ORDERED PREFIX — the voter ranks their top-k
/// options (drag to reorder), which the view-model packs into a packed ranking.
///
/// CRITICAL labelling rule (spec, load-bearing): the results card is the
/// ROUND-1 FIRST-PREFERENCE tally, NOT the winner. The instant-runoff winner is
/// computed off-chain by replaying the full ballots. This screen never crowns
/// the first-pref leader (no trophy — `highlightLeader: false`) and labels the
/// card "First-choice tally — not the final winner".
class RankedPollScreen extends StatefulWidget {
  final String address;
  const RankedPollScreen({super.key, required this.address});
  @override
  State<RankedPollScreen> createState() => _RankedPollScreenState();
}

class _RankedPollScreenState extends State<RankedPollScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<RankedVoteViewModel>().load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DotGridBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: Consumer<RankedVoteViewModel>(
                builder: (context, vm, _) => switch (vm.state) {
                  ViewState.idle || ViewState.loading => Center(
                      child: CircularProgressIndicator(color: Db.segnale),
                    ),
                  ViewState.error => _ErrorView(
                      message: vm.error ?? 'Unknown error',
                      onRetry: vm.load,
                    ),
                  ViewState.loaded => _Body(snapshot: vm.snapshot!),
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
  final PollSnapshot snapshot;
  const _Body({required this.snapshot});

  String get _shortAddr => shortAddr(snapshot.address);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(shortAddr: _shortAddr),
            const SizedBox(height: 20),
            _PhaseStrip(state: snapshot.state),
            const SizedBox(height: 16),
            Text(
              '${snapshot.participantCount} REGISTERED · RANK YOUR TOP OPTIONS IN ORDER',
              style: dbLabel(size: 11, tracking: 0.1),
            ),
            const SizedBox(height: 24),
            LayoutBuilder(
              builder: (context, c) {
                final results = _ResultsBars(snapshot: snapshot);
                if (snapshot.state != 1) return results;
                final vote = _RankedArea(options: snapshot.options);
                // Side-by-side on wide screens (desktop/web), stacked on mobile.
                if (c.maxWidth > 840) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: results),
                      const SizedBox(width: 16),
                      Expanded(child: vote),
                    ],
                  );
                }
                return Column(
                  children: [results, const SizedBox(height: 20), vote],
                );
              },
            ),
            const SizedBox(height: 24),
            Text('OWNER', style: dbLabel(size: 10)),
            const SizedBox(height: 4),
            Text(
              snapshot.owner,
              style: dbMono(11, Db.mute, letterSpacing: 0.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String shortAddr;
  const _Header({required this.shortAddr});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 12),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () => context.canPop() ? context.pop() : context.go('/'),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_back, size: 14, color: Db.mute),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'BACK TO POLLS',
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: dbLabel(size: 11, tracking: 0.16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: Db.oltremare,
              child: Text(
                'ZK · RANKED',
                style: dbSans(11, 800, Db.void_, letterSpacing: 2.0),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Db.slate,
                border: Border.fromBorderSide(BorderSide(color: Db.rule)),
              ),
              child: Text(
                shortAddr,
                style: dbMono(11, Db.mute, letterSpacing: 0.5),
              ),
            ),
          ],
        ),
      );
}

class _PhaseStrip extends StatelessWidget {
  final int state; // 0 reg, 1 voting, 2 ended
  const _PhaseStrip({required this.state});
  static const _labels = ['REGISTRATION', 'VOTING', 'ENDED'];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.fromBorderSide(BorderSide(color: Db.rule)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < 3; i++)
            Expanded(
              child: Container(
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: i == state
                      ? Db.segnale
                      : (i < state ? Db.slate : Db.void_),
                  border: i < 2
                      ? Border(right: BorderSide(color: Db.rule))
                      : null,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (i < state) ...[
                        Icon(Icons.check, size: 13, color: Db.mute),
                        const SizedBox(width: 6),
                      ] else if (i > state) ...[
                        Text(
                          '0${i + 1}',
                          style: dbMono(11, Db.muteDim, wght: 700),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        _labels[i],
                        style: dbSans(
                          11,
                          800,
                          i == state ? Db.void_ : Db.mute,
                          letterSpacing: 11 * 0.16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ResultsBars extends StatelessWidget {
  final PollSnapshot snapshot;
  const _ResultsBars({required this.snapshot});
  @override
  Widget build(BuildContext context) {
    // These are ROUND-1 FIRST-PREFERENCE counts (the contract tallies only each
    // ballot's first choice). The first-pref leader is frequently NOT the
    // instant-runoff winner — so this card is labelled accordingly and crowns
    // NOBODY (`highlightLeader: false`). The % denominator is the voter count
    // (every voter contributes exactly one first preference).
    final voters = snapshot.participantCount;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Db.slate,
        border: Border.fromBorderSide(BorderSide(color: Db.rule)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bar_chart, size: 16, color: Db.mute),
              const SizedBox(width: 8),
              Text('FIRST CHOICES', style: dbSectionTitle),
              const Spacer(),
              Text('$voters VOTERS', style: dbLabel(size: 11, tracking: 0.05)),
            ],
          ),
          const SizedBox(height: 6),
          // The load-bearing caption: these bars are NOT the outcome.
          Row(
            children: [
              Icon(Icons.info_outline, size: 13, color: Db.amber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'First-choice tally — not the final winner. The instant-runoff '
                  'winner is computed off-chain by transferring votes as low '
                  'options are eliminated.',
                  style: dbMono(11, Db.amber, height: 1.4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ResultsBars(
            highlightLeader: false, // first-pref leader is NOT the winner
            options: [
              for (var i = 0; i < snapshot.options.length; i++)
                (
                  label: snapshot.options[i],
                  count: i < snapshot.results.length
                      ? snapshot.results[i]
                      : BigInt.zero,
                ),
            ],
            total: voters,
            emptyLabel: 'No first-choice votes yet',
          ),
        ],
      ),
    );
  }
}

// ── Ranked ballot area (web has a prover; native/desktop read-only) ──────────

class _RankedArea extends StatelessWidget {
  final List<String> options;
  const _RankedArea({required this.options});
  @override
  Widget build(BuildContext context) {
    if (!proofServiceAvailable) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Db.slate,
          border: Border.fromBorderSide(BorderSide(color: Db.rule)),
        ),
        child: Row(
          children: [
            Icon(Icons.lock_outline, color: Db.mute, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Voting runs in the web app (mobile coming soon). This build is read-only.',
                style: dbMono(12, Db.mute, height: 1.5),
              ),
            ),
          ],
        ),
      );
    }
    return _RankedForm(options: options);
  }
}

class _RankedForm extends StatefulWidget {
  final List<String> options;
  const _RankedForm({required this.options});
  @override
  State<_RankedForm> createState() => _RankedFormState();
}

class _RankedFormState extends State<_RankedForm> {
  final _seed = TextEditingController();

  /// The voter's ranking, in preference order (index 0 = top choice). Holds the
  /// option INDICES the voter has ranked so far — a prefix of the options. Options
  /// not in this list are unranked.
  final List<int> _ranked = <int>[];

  bool _fromSavedIdentity = false;
  Timer? _regDebounce;

  @override
  void initState() {
    super.initState();
    // Prefill from the saved identity so voting doesn't need pasting.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final saved = await context.read<IdentityStore>().read();
      if (!mounted || saved == null || saved.isEmpty || _seed.text.isNotEmpty) {
        return;
      }
      setState(() {
        _seed.text = saved;
        _fromSavedIdentity = true;
      });
      // A programmatic `text =` doesn't fire onChanged — kick the check off.
      context.read<RankedVoteViewModel>().checkRegistration(saved.trim());
    });
  }

  void _onSeedChanged(String value) {
    setState(() => _fromSavedIdentity = false);
    _regDebounce?.cancel();
    final seed = value.trim();
    final vm = context.read<RankedVoteViewModel>();
    if (seed.isEmpty) {
      vm.clearRegistration();
      return;
    }
    _regDebounce = Timer(
      const Duration(milliseconds: 600),
      () => vm.checkRegistration(seed),
    );
  }

  @override
  void dispose() {
    _regDebounce?.cancel();
    _seed.dispose();
    super.dispose();
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(m, style: dbMono(12, Db.chalk)),
          backgroundColor: Db.slate,
        ),
      );

  List<int> get _unranked => [
        for (var i = 0; i < widget.options.length; i++)
          if (!_ranked.contains(i)) i,
      ];

  void _addToRanking(int option) => setState(() => _ranked.add(option));

  void _removeFromRanking(int option) =>
      setState(() => _ranked.remove(option));

  void _reorder(int oldIndex, int newIndex) => setState(() {
        // ReorderableListView convention: a downward move yields newIndex one
        // past the target slot.
        if (newIndex > oldIndex) newIndex -= 1;
        final option = _ranked.removeAt(oldIndex);
        _ranked.insert(newIndex, option);
      });

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<RankedVoteViewModel>();
    // Disable cast when nothing is ranked (the contract's EmptyBallot guard) or
    // no identity is entered or a cast is in flight.
    final canCast =
        _ranked.isNotEmpty && _seed.text.trim().isNotEmpty && !vm.isBusy;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Db.slate,
        border: Border.fromBorderSide(BorderSide(color: Db.rule)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('RANK YOUR OPTIONS', style: dbSectionTitle),
          const SizedBox(height: 6),
          Text(
            'Tap to add an option to your ranking, then drag to reorder — '
            'top is your first choice. Rank as few or as many as you like.',
            style: dbMono(11, Db.mute, height: 1.5),
          ),
          const SizedBox(height: 14),
          _RankedList(
            ranked: _ranked,
            options: widget.options,
            onReorder: vm.isBusy ? null : _reorder,
            onRemove: vm.isBusy ? null : _removeFromRanking,
          ),
          if (_unranked.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('UNRANKED', style: dbLabel(size: 10)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in _unranked)
                  _UnrankedChip(
                    label: widget.options[option],
                    color: Db.optionColor(option),
                    onTap: vm.isBusy ? null : () => _addToRanking(option),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          if (_fromSavedIdentity)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(Icons.fingerprint, size: 13, color: Db.success),
                  const SizedBox(width: 6),
                  Text(
                    'using your saved identity',
                    style: dbLabel(size: 10, color: Db.success),
                  ),
                ],
              ),
            ),
          TextField(
            controller: _seed,
            onChanged: _onSeedChanged,
            style: dbMono(13, Db.chalk),
            cursorColor: Db.segnale,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              filled: true,
              fillColor: Db.void_,
              hintText: 'paste your invite token / identity seed',
              hintStyle: dbMono(12, Db.mute),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: Db.rule),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: Db.segnale),
              ),
            ),
          ),
          _RegistrationStatus(vm: vm, onCopy: _snack),
          const SizedBox(height: 14),
          _CastButton(
            busyLabel: switch (vm.status) {
              RankedVoteStatus.proving => 'GENERATING PROOF…',
              RankedVoteStatus.relaying => 'SUBMITTING…',
              _ => null,
            },
            enabled: canCast,
            rankedCount: _ranked.length,
            onTap: canCast
                ? () => context.read<RankedVoteViewModel>().castRanked(
                      identitySeed: _seed.text.trim(),
                      ranking: List<int>.from(_ranked),
                    )
                : null,
          ),
          if (vm.status == RankedVoteStatus.success)
            _statusLine(
              Icons.check_circle,
              Db.success,
              'BALLOT COUNTED · ${vm.txHash ?? ''}',
            ),
          if (vm.status == RankedVoteStatus.error)
            _statusLine(
              Icons.error_outline,
              Db.segnale,
              vm.castError ?? 'Ballot failed',
            ),
        ],
      ),
    );
  }

  Widget _statusLine(IconData icon, Color color, String text) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: dbMono(12, color))),
          ],
        ),
      );
}

/// The voter's ordered ranking as a drag-to-reorder list. Each row shows its
/// rank number (1 = top choice), the option label, a drag handle, and a remove
/// button. Empty until the voter adds an option from the UNRANKED chips.
class _RankedList extends StatelessWidget {
  final List<int> ranked;
  final List<String> options;
  final void Function(int oldIndex, int newIndex)? onReorder;
  final void Function(int option)? onRemove;
  const _RankedList({
    required this.ranked,
    required this.options,
    required this.onReorder,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (ranked.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
        decoration: BoxDecoration(
          color: Db.void_,
          border: Border.all(color: Db.rule),
        ),
        child: Text(
          'No options ranked yet — tap an option below to add it.',
          style: dbMono(11, Db.mute, height: 1.4),
        ),
      );
    }
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      onReorder: onReorder ?? (_, _) {},
      itemCount: ranked.length,
      itemBuilder: (context, i) {
        final option = ranked[i];
        return _RankRow(
          key: ValueKey('rank-$option'),
          index: i,
          label: options[option],
          color: Db.optionColor(option),
          onRemove: onRemove == null ? null : () => onRemove!(option),
        );
      },
    );
  }
}

class _RankRow extends StatelessWidget {
  final int index; // 0-based position in the ranking
  final String label;
  final Color color;
  final VoidCallback? onRemove;
  const _RankRow({
    super.key,
    required this.index,
    required this.label,
    required this.color,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: index == 0 ? 0 : 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          border: Border.all(color: color, width: 2),
        ),
        child: Row(
          children: [
            // Rank number — 1-based for the voter (slot 0 is "first choice").
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              color: color,
              child: Text(
                '${index + 1}',
                style: dbMono(12, Db.void_, wght: 800),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: dbSans(15, 600, Db.chalk))),
            if (onRemove != null) ...[
              InkWell(
                onTap: onRemove,
                child: Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 16, color: Db.mute),
                ),
              ),
              const SizedBox(width: 4),
            ],
            ReorderableDragStartListener(
              index: index,
              child: Icon(Icons.drag_handle, size: 18, color: Db.mute),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnrankedChip extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback? onTap;
  const _UnrankedChip({
    required this.label,
    required this.color,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Db.void_,
            border: Border.all(color: Db.rule),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 14, color: color),
              const SizedBox(width: 8),
              Text(label, style: dbSans(13, 600, Db.chalk)),
            ],
          ),
        ),
      );
}

// Proactive registration status shown above the CAST button (identical pattern
// to M1/M3): a spinner while checking, a green "ready" chip when registered, or
// an amber panel with the voter's commitment (copyable) when they're not.
class _RegistrationStatus extends StatelessWidget {
  final RankedVoteViewModel vm;
  final void Function(String) onCopy;
  const _RegistrationStatus({required this.vm, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    if (vm.checkingRegistration) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2, color: Db.mute),
            ),
            const SizedBox(width: 10),
            Text('checking…', style: dbMono(11, Db.mute)),
          ],
        ),
      );
    }
    if (vm.isRegistered == true) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Db.success.withValues(alpha: 0.10),
            border: Border.all(color: Db.success),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check, size: 14, color: Db.success),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Registered — ready to vote',
                  style: dbMono(11, Db.success, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (vm.isRegistered == false && vm.myCommitment != null) {
      final commitment = vm.myCommitment!;
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Db.slate,
            border: Border(left: BorderSide(color: Db.amber, width: 3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.error_outline, size: 16, color: Db.amber),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Not registered in this poll. Share your identity commitment '
                      'with the organizer to be added:',
                      style: dbMono(11, Db.chalkDim, height: 1.4),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SelectableText(
                commitment,
                style: dbMono(11, Db.chalk, height: 1.4),
              ),
              const SizedBox(height: 10),
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: commitment));
                  onCopy('Commitment copied to clipboard.');
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Db.void_,
                    border: Border.fromBorderSide(BorderSide(color: Db.rule)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.copy_outlined,
                        size: 14,
                        color: Db.chalkDim,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        'COPY',
                        style: dbLabel(size: 10, color: Db.chalkDim),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _CastButton extends StatelessWidget {
  final bool enabled;
  final String? busyLabel;
  final int rankedCount;
  final VoidCallback? onTap;
  const _CastButton({
    required this.enabled,
    required this.rankedCount,
    this.busyLabel,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final label = busyLabel ??
        (enabled
            ? 'CAST RANKED BALLOT ($rankedCount) →'
            : '[ RANK AT LEAST ONE OPTION ]');
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? Db.segnale : Db.void_,
          border: Border.all(color: enabled ? Db.segnale : Db.rule),
        ),
        child: Text(
          label,
          style: dbSans(
            13,
            800,
            enabled ? Db.void_ : Db.mute,
            letterSpacing: 13 * 0.12,
          ),
        ),
      ),
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
              Icon(Icons.cloud_off, color: Db.segnale, size: 40),
              const SizedBox(height: 12),
              Text(
                "COULDN'T LOAD THIS POLL",
                style: dbLabel(size: 12, color: Db.chalk),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: dbMono(12, Db.mute),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: onRetry,
                style: OutlinedButton.styleFrom(
                  shape: const RoundedRectangleBorder(),
                  side: BorderSide(color: Db.rule),
                ),
                child:
                    Text('RETRY', style: dbLabel(size: 11, color: Db.chalk)),
              ),
            ],
          ),
        ),
      );
}
