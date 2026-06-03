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
import 'approval_vote_view_model.dart';

/// Approval-vote poll detail (module `approval-vote`) — Dark Bauhaus. A sibling
/// of the M1 anon surface, with one behavioral difference: the ballot is
/// MULTI-SELECT — the voter approves any number of options (checkboxes), which
/// the view-model packs into a bitmask. Results are per-option APPROVALS, so the
/// percentage denominator is the voter count (participants), not the sum of
/// approvals (which can exceed the voter count by design).
class ApprovalPollScreen extends StatefulWidget {
  final String address;
  const ApprovalPollScreen({super.key, required this.address});
  @override
  State<ApprovalPollScreen> createState() => _ApprovalPollScreenState();
}

class _ApprovalPollScreenState extends State<ApprovalPollScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<ApprovalVoteViewModel>().load(),
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
              child: Consumer<ApprovalVoteViewModel>(
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
              '${snapshot.participantCount} REGISTERED · APPROVE ANY NUMBER OF OPTIONS',
              style: dbLabel(size: 11, tracking: 0.1),
            ),
            const SizedBox(height: 24),
            LayoutBuilder(
              builder: (context, c) {
                final results = _ResultsBars(snapshot: snapshot);
                if (snapshot.state != 1) return results;
                final vote = _ApprovalArea(options: snapshot.options);
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
            'ZK · APPROVAL',
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
    // Approvals are NON-EXCLUSIVE — a voter can approve many options, so the sum
    // of per-option counts can exceed the voter count. The correct % denominator
    // is the number of voters (participantCount), passed explicitly to
    // ResultsBars so each bar reads "X of N voters approved".
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
              Text('APPROVALS', style: dbSectionTitle),
              const Spacer(),
              Text('$voters VOTERS', style: dbLabel(size: 11, tracking: 0.05)),
            ],
          ),
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
            total: voters,
            emptyLabel: 'No approvals yet',
          ),
        ],
      ),
    );
  }
}

// ── Approval ballot area (web has a prover; native/desktop read-only) ────────

class _ApprovalArea extends StatelessWidget {
  final List<String> options;
  const _ApprovalArea({required this.options});
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
    return _ApprovalForm(options: options);
  }
}

class _ApprovalForm extends StatefulWidget {
  final List<String> options;
  const _ApprovalForm({required this.options});
  @override
  State<_ApprovalForm> createState() => _ApprovalFormState();
}

class _ApprovalFormState extends State<_ApprovalForm> {
  final _seed = TextEditingController();
  final _approved = <int>{}; // set of approved option indices
  bool _fromSavedIdentity = false;
  Timer? _regDebounce;

  @override
  void initState() {
    super.initState();
    // Prefill from the saved identity so voting doesn't need pasting (SP2).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final saved = await context.read<IdentityStore>().read();
      if (!mounted || saved == null || saved.isEmpty || _seed.text.isNotEmpty) {
        return;
      }
      setState(() {
        _seed.text = saved;
        _fromSavedIdentity = true;
      });
      // A programmatic `text =` doesn't fire onChanged, so the common path
      // (a saved identity) would never get checked — kick it off explicitly.
      context.read<ApprovalVoteViewModel>().checkRegistration(saved.trim());
    });
  }

  // Debounce the registration check on each keystroke; an empty field clears
  // any prior status (and cancels a pending check) so no stale panel lingers.
  void _onSeedChanged(String value) {
    setState(() => _fromSavedIdentity = false);
    _regDebounce?.cancel();
    final seed = value.trim();
    final vm = context.read<ApprovalVoteViewModel>();
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
    final vm = context.watch<ApprovalVoteViewModel>();
    // Disable cast when no option is approved (the contract's EmptyBallot guard)
    // or no identity is entered or a cast is in flight.
    final canCast =
        _approved.isNotEmpty && _seed.text.trim().isNotEmpty && !vm.isBusy;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Db.slate,
        border: Border.fromBorderSide(BorderSide(color: Db.rule)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('APPROVE OPTIONS', style: dbSectionTitle),
          const SizedBox(height: 6),
          Text(
            'Check every option you approve of — approve as many as you like.',
            style: dbMono(11, Db.mute, height: 1.5),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < widget.options.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _CheckTile(
              label: widget.options[i],
              color: Db.optionColor(i),
              checked: _approved.contains(i),
              onTap: vm.isBusy
                  ? null
                  : () => setState(() {
                      if (!_approved.add(i)) _approved.remove(i);
                    }),
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
              ApprovalVoteStatus.proving => 'GENERATING PROOF…',
              ApprovalVoteStatus.relaying => 'SUBMITTING…',
              _ => null,
            },
            enabled: canCast,
            approvedCount: _approved.length,
            onTap: canCast
                ? () => context.read<ApprovalVoteViewModel>().castApproval(
                    identitySeed: _seed.text.trim(),
                    approvedIndices: Set<int>.from(_approved),
                  )
                : null,
          ),
          if (vm.status == ApprovalVoteStatus.success)
            _statusLine(
              Icons.check_circle,
              Db.success,
              'BALLOT COUNTED · ${vm.txHash ?? ''}',
            ),
          if (vm.status == ApprovalVoteStatus.error)
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

// Proactive registration status shown above the CAST button (identical pattern
// to M1): a spinner while checking, a green "ready" chip when registered, or an
// amber panel with the voter's commitment (copyable) when they're not.
class _RegistrationStatus extends StatelessWidget {
  final ApprovalVoteViewModel vm;
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

class _CheckTile extends StatelessWidget {
  final String label;
  final Color color;
  final bool checked;
  final VoidCallback? onTap;
  const _CheckTile({
    required this.label,
    required this.color,
    required this.checked,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: checked ? color.withValues(alpha: 0.12) : Db.void_,
        border: Border.all(
          color: checked ? color : Db.rule,
          width: checked ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            checked ? Icons.check_box : Icons.check_box_outline_blank,
            color: checked ? color : Db.mute,
            size: 18,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: dbSans(15, 600, Db.chalk))),
        ],
      ),
    ),
  );
}

class _CastButton extends StatelessWidget {
  final bool enabled;
  final String? busyLabel;
  final int approvedCount;
  final VoidCallback? onTap;
  const _CastButton({
    required this.enabled,
    required this.approvedCount,
    this.busyLabel,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final label =
        busyLabel ??
        (enabled
            ? 'CAST APPROVAL BALLOT ($approvedCount) →'
            : '[ SELECT AT LEAST ONE OPTION ]');
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
            child: Text('RETRY', style: dbLabel(size: 11, color: Db.chalk)),
          ),
        ],
      ),
    ),
  );
}
