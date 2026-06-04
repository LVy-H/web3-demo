import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../data/models/poll_snapshot.dart';
import '../../../data/services/identity_store.dart';
import '../../../data/services/proof_service_factory.dart';
import '../../core/dot_grid_background.dart';
import '../../core/format.dart';
import '../../core/poll_header.dart';
import '../../core/share_poll_sheet.dart';
import '../../core/theme.dart';
import '../../core/view_state.dart';
import '../../widgets/results_bars.dart';
import 'quadratic_vote_view_model.dart';

/// Quadratic-voting poll detail (module `quadratic-vote`) — Dark Bauhaus. A
/// sibling of the M4 ranked surface, with two behavioral differences:
///
/// 1. BALLOT: instead of an ordered prefix, the voter spends a FIXED budget of
///    CREDITS (100) across the options with per-option steppers; casting `vᵢ`
///    votes for option `i` costs `vᵢ²`. A live budget meter (`spent = Σ vᵢ²`,
///    `remaining = 100 - spent`) disables a `+` once the next increment would
///    exceed the budget (so a single option caps at v=10, and `[10,1]` is
///    blocked). The allocation state lives on the view-model, not here.
///
/// 2. RESULTS (the OPPOSITE of ranked): `getResults()` IS authoritative for QV —
///    the option with the highest vote-sum is the actual winner (no off-chain
///    replay). So this screen DOES crown the leader (`highlightLeader: true`,
///    the default). The results caption is state-aware: provisional ("Current …
///    ahead") during the Voting phase, final ("Final … winner") once Ended.
///    It deliberately does NOT carry over ranked's "not the final winner"
///    warning — that caption is wrong here.
class QuadraticPollScreen extends StatefulWidget {
  final String address;
  const QuadraticPollScreen({super.key, required this.address});
  @override
  State<QuadraticPollScreen> createState() => _QuadraticPollScreenState();
}

class _QuadraticPollScreenState extends State<QuadraticPollScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<QuadraticVoteViewModel>().load(),
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
              child: Consumer<QuadraticVoteViewModel>(
                builder: (context, vm, _) => switch (vm.state) {
                  ViewState.idle || ViewState.loading => const Center(
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
            _Header(shortAddr: _shortAddr, address: snapshot.address),
            const SizedBox(height: 20),
            _PhaseStrip(state: snapshot.state),
            const SizedBox(height: 16),
            Text(
              '${snapshot.participantCount} REGISTERED · SPEND YOUR CREDITS — '
              'MORE VOTES ON ONE OPTION COST QUADRATICALLY MORE',
              style: dbLabel(size: 11, tracking: 0.1),
            ),
            const SizedBox(height: 24),
            LayoutBuilder(
              builder: (context, c) {
                final results = _ResultsBars(snapshot: snapshot);
                if (snapshot.state != 1) return results;
                final vote = _QuadraticArea(options: snapshot.options);
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
  final String address;
  const _Header({required this.shortAddr, required this.address});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 12),
    child: pollDetailHeaderRow(
      context: context,
      badgeLabel: 'ZK · QUADRATIC',
      badgeColor: Db.oltremare,
      shortAddr: shortAddr,
      onShare: () => showSharePollSheet(
        context,
        address: address,
        module: 'quadratic-vote',
      ),
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
      decoration: const BoxDecoration(
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
                      ? const Border(right: BorderSide(color: Db.rule))
                      : null,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (i < state) ...[
                        const Icon(Icons.check, size: 13, color: Db.mute),
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
    // These are the AUTHORITATIVE per-option vote sums (the contract tallies the
    // votes vᵢ each ballot allocated). Unlike ranked, getResults() IS the
    // outcome — the option with the highest sum is the actual winner — so this
    // card DOES crown the leader (`highlightLeader: true`, the default). The %
    // denominator is the SUM of all votes (ResultsBars' default), since a voter
    // casts many votes, not one.
    //
    // Caption is state-aware: during Voting the tally is a live snapshot so we
    // call it "Current … ahead"; once Ended the tally is sealed so we say
    // "Final … winner". Crowning (highlightLeader) is correct in both phases
    // because QV is a linear vote-sum — the on-chain leader is always the
    // leading option regardless of phase.
    final isEnded = snapshot.state == 2;
    final caption = isEnded
        ? 'Final per-option vote totals — the on-chain tally is '
              'authoritative; the leading option is the winner.'
        : 'Current per-option vote totals — the on-chain tally is '
              'authoritative; the leading option is ahead.';
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
            title: 'VOTE TOTALS',
            trailing: '${snapshot.participantCount} VOTERS',
          ),
          const SizedBox(height: 6),
          // State-aware caption: provisional during voting, final when ended.
          Row(
            children: [
              const Icon(Icons.verified_outlined, size: 13, color: Db.success),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  caption,
                  style: dbMono(11, Db.success, height: 1.4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ResultsBars(
            // QV winner IS the max vote-sum, so crown the leader (default true).
            highlightLeader: true,
            options: [
              for (var i = 0; i < snapshot.options.length; i++)
                (
                  label: snapshot.options[i],
                  count: i < snapshot.results.length
                      ? snapshot.results[i]
                      : BigInt.zero,
                ),
            ],
            // No explicit total → share of all votes cast (a voter casts many).
            emptyLabel: 'No votes allocated yet',
          ),
        ],
      ),
    );
  }
}

// ── Quadratic ballot area (web has a prover; native/desktop read-only) ───────

class _QuadraticArea extends StatelessWidget {
  final List<String> options;
  const _QuadraticArea({required this.options});
  @override
  Widget build(BuildContext context) {
    if (!proofServiceAvailable) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Db.slate,
          border: Border.fromBorderSide(BorderSide(color: Db.rule)),
        ),
        child: Row(
          children: [
            const Icon(Icons.lock_outline, color: Db.mute, size: 18),
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
    return _QuadraticForm(options: options);
  }
}

class _QuadraticForm extends StatefulWidget {
  final List<String> options;
  const _QuadraticForm({required this.options});
  @override
  State<_QuadraticForm> createState() => _QuadraticFormState();
}

class _QuadraticFormState extends State<_QuadraticForm> {
  final _seed = TextEditingController();

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
      context.read<QuadraticVoteViewModel>().checkRegistration(saved.trim());
    });
  }

  void _onSeedChanged(String value) {
    setState(() => _fromSavedIdentity = false);
    _regDebounce?.cancel();
    final seed = value.trim();
    final vm = context.read<QuadraticVoteViewModel>();
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

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<QuadraticVoteViewModel>();
    // Disable cast when nothing is allocated (the contract's EmptyBallot guard)
    // or no identity is entered or a cast is in flight.
    final canCast = vm.canCast && _seed.text.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Db.slate,
        border: Border.fromBorderSide(BorderSide(color: Db.rule)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ALLOCATE YOUR VOTES', style: dbSectionTitle),
          const SizedBox(height: 6),
          Text(
            'Spend your ${vm.credits} credits with the steppers below. Casting '
            'v votes for an option costs v² credits, so v=10 on one option uses '
            'your whole budget. Spread or concentrate — your call.',
            style: dbMono(11, Db.mute, height: 1.5),
          ),
          const SizedBox(height: 14),
          _BudgetMeter(vm: vm),
          const SizedBox(height: 14),
          for (var i = 0; i < widget.options.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _OptionStepper(
              label: widget.options[i],
              color: Db.optionColor(i),
              votes: i < vm.votes.length ? vm.votes[i] : 0,
              cost: i < vm.votes.length ? vm.votes[i] * vm.votes[i] : 0,
              canIncrement: vm.canIncrement(i),
              canDecrement: vm.canDecrement(i),
              onIncrement: vm.isBusy ? null : () => vm.increment(i),
              onDecrement: vm.isBusy ? null : () => vm.decrement(i),
            ),
          ],
          const SizedBox(height: 16),
          if (_fromSavedIdentity)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(Icons.fingerprint, size: 13, color: Db.success),
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
              enabledBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: Db.rule),
              ),
              focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: Db.segnale),
              ),
            ),
          ),
          _RegistrationStatus(vm: vm, onCopy: _snack),
          const SizedBox(height: 14),
          _CastButton(
            busyLabel: switch (vm.status) {
              QuadraticVoteStatus.proving => 'GENERATING PROOF…',
              QuadraticVoteStatus.relaying => 'SUBMITTING…',
              _ => null,
            },
            enabled: canCast,
            totalVotes: vm.totalAllocated,
            onTap: canCast
                ? () => context.read<QuadraticVoteViewModel>().castQuadratic(
                    identitySeed: _seed.text.trim(),
                  )
                : null,
          ),
          if (vm.status == QuadraticVoteStatus.success)
            _statusLine(
              Icons.check_circle,
              Db.success,
              'BALLOT COUNTED · ${vm.txHash ?? ''}',
            ),
          if (vm.status == QuadraticVoteStatus.error)
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

/// The live budget meter: `SPENT = Σ vᵢ²` / `REMAINING = CREDITS - spent`, with
/// a fill bar. Turns amber when the budget is fully spent (no more increments
/// possible). Reads straight off the view-model so it updates on every stepper
/// tap.
class _BudgetMeter extends StatelessWidget {
  final QuadraticVoteViewModel vm;
  const _BudgetMeter({required this.vm});

  @override
  Widget build(BuildContext context) {
    final spent = vm.spent;
    final credits = vm.credits;
    final frac = (spent / credits).clamp(0.0, 1.0);
    final full = spent >= credits;
    final barColor = full ? Db.amber : Db.success;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        color: Db.void_,
        border: Border.fromBorderSide(BorderSide(color: Db.rule)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('CREDITS SPENT', style: dbLabel(size: 10, tracking: 0.12)),
              const Spacer(),
              Text(
                '$spent',
                style: dbMono(22, barColor, wght: 700, letterSpacing: -0.4),
              ),
              Text(' / $credits', style: dbMono(13, Db.mute)),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 8,
            child: Stack(
              children: [
                const Positioned.fill(child: ColoredBox(color: Db.rule)),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: frac,
                  child: ColoredBox(color: barColor),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            full
                ? 'Budget fully spent — lower an option to reallocate.'
                : '${vm.remaining} credits remaining',
            style: dbMono(11, full ? Db.amber : Db.mute, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// One option row with a − / value / + stepper, the option color, and the live
/// quadratic cost (`v²` credits) for that option. `+` is disabled by
/// [canIncrement] (the next increment would exceed the budget, or hit the 4-bit
/// max); `−` by [canDecrement] (`v == 0`).
class _OptionStepper extends StatelessWidget {
  final String label;
  final Color color;
  final int votes;
  final int cost;
  final bool canIncrement;
  final bool canDecrement;
  final VoidCallback? onIncrement;
  final VoidCallback? onDecrement;
  const _OptionStepper({
    required this.label,
    required this.color,
    required this.votes,
    required this.cost,
    required this.canIncrement,
    required this.canDecrement,
    required this.onIncrement,
    required this.onDecrement,
  });

  @override
  Widget build(BuildContext context) {
    final active = votes > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: active ? color.withValues(alpha: 0.12) : Db.void_,
        border: Border.all(
          color: active ? color : Db.rule,
          width: active ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: dbSans(15, 600, Db.chalk),
                ),
                const SizedBox(height: 2),
                Text(
                  active ? '$votes votes · $cost credits' : 'no votes',
                  style: dbMono(10, active ? color : Db.mute),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _StepBtn(
            icon: Icons.remove,
            enabled: canDecrement && onDecrement != null,
            onTap: canDecrement ? onDecrement : null,
          ),
          Container(
            width: 40,
            alignment: Alignment.center,
            child: Text(
              '$votes',
              style: dbMono(18, Db.chalk, wght: 700, letterSpacing: -0.4),
            ),
          ),
          _StepBtn(
            icon: Icons.add,
            enabled: canIncrement && onIncrement != null,
            onTap: canIncrement ? onIncrement : null,
          ),
        ],
      ),
    );
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback? onTap;
  const _StepBtn({required this.icon, required this.enabled, this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: enabled ? onTap : null,
    child: Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: enabled ? Db.slate : Db.void_,
        border: Border.all(color: enabled ? Db.chalkDim : Db.rule),
      ),
      child: Icon(icon, size: 16, color: enabled ? Db.chalk : Db.muteDim),
    ),
  );
}

// Proactive registration status shown above the CAST button (identical pattern
// to M1/M3/M4): a spinner while checking, a green "ready" chip when registered,
// or an amber panel with the voter's commitment (copyable) when they're not.
class _RegistrationStatus extends StatelessWidget {
  final QuadraticVoteViewModel vm;
  final void Function(String) onCopy;
  const _RegistrationStatus({required this.vm, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    if (vm.checkingRegistration) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          children: [
            const SizedBox(
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
              const Icon(Icons.check, size: 14, color: Db.success),
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
          decoration: const BoxDecoration(
            color: Db.slate,
            border: Border(left: BorderSide(color: Db.amber, width: 3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.error_outline, size: 16, color: Db.amber),
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
                  decoration: const BoxDecoration(
                    color: Db.void_,
                    border: Border.fromBorderSide(BorderSide(color: Db.rule)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
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
  final int totalVotes;
  final VoidCallback? onTap;
  const _CastButton({
    required this.enabled,
    required this.totalVotes,
    this.busyLabel,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final label =
        busyLabel ??
        (enabled
            ? 'CAST QUADRATIC BALLOT ($totalVotes) →'
            : '[ ALLOCATE AT LEAST ONE VOTE ]');
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
          const Icon(Icons.cloud_off, color: Db.segnale, size: 40),
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
              side: const BorderSide(color: Db.rule),
            ),
            child: Text('RETRY', style: dbLabel(size: 11, color: Db.chalk)),
          ),
        ],
      ),
    ),
  );
}
