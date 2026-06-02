import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../data/models/pending_voter.dart';
import '../../core/dot_grid_background.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/view_state.dart';
import 'live_host_view_model.dart';

/// Organizer dashboard for a live in-person meeting: a rotating QR (signed
/// ticket) that voters scan, a live queue of pending voters, face-to-face
/// confirm (registers their commitment on-chain), and the voting phase controls.
class LiveHostScreen extends StatefulWidget {
  final String address;
  const LiveHostScreen({super.key, required this.address});
  @override
  State<LiveHostScreen> createState() => _LiveHostScreenState();
}

class _LiveHostScreenState extends State<LiveHostScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => context.read<LiveHostViewModel>().load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DotGridBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: Consumer<LiveHostViewModel>(
                builder: (context, vm, _) => switch (vm.state) {
                  ViewState.idle || ViewState.loading => const Center(
                      child: CircularProgressIndicator(color: Db.segnale)),
                  ViewState.error => _Error(message: vm.error ?? 'Unknown error'),
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
  final LiveHostViewModel vm;
  const _Body({required this.vm});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _header(context),
          const SizedBox(height: 20),
          if (!vm.canHost)
            _banner(Icons.lock_outline,
                'Read-only — a dev signer (DEV_PRIVATE_KEY) or owner wallet is required to host.'),
          LayoutBuilder(builder: (context, c) {
            final qr = _QrPanel(vm: vm);
            final queue = _QueuePanel(vm: vm);
            if (c.maxWidth > 840) {
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: qr),
                const SizedBox(width: 16),
                Expanded(child: queue),
              ]);
            }
            return Column(children: [qr, const SizedBox(height: 20), queue]);
          }),
          const SizedBox(height: 20),
          _PhaseControls(vm: vm),
          if (vm.actionMsg != null)
            _line(Icons.check_circle, Db.success, vm.actionMsg!),
          if (vm.actionError != null)
            _line(Icons.error_outline, Db.amber, vm.actionError!),
        ]),
      ),
    );
  }

  Widget _header(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 12),
        child: Row(children: [
          Expanded(
            child: InkWell(
              onTap: () => context.canPop() ? context.pop() : context.go('/'),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.arrow_back, size: 14, color: Db.mute),
                const SizedBox(width: 6),
                Flexible(
                  child: Text('BACK',
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: dbLabel(size: 11, tracking: 0.16)),
                ),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: Db.segnale,
            child: Text('LIVE · HOST',
                style: dbSans(11, 800, Db.void_, letterSpacing: 1.6)),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: const BoxDecoration(
              color: Db.slate,
              border: Border.fromBorderSide(BorderSide(color: Db.rule)),
            ),
            child: Text(shortAddr(vm.pollAddress),
                style: dbMono(11, Db.mute, letterSpacing: 0.5)),
          ),
        ]),
      );

  Widget _banner(IconData icon, String text) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Db.slate,
          border: Border(left: BorderSide(color: Db.segnale, width: 3)),
        ),
        child: Row(children: [
          Icon(icon, size: 18, color: Db.segnale),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: dbMono(12, Db.chalkDim, height: 1.4))),
        ]),
      );

  Widget _line(IconData icon, Color color, String text) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: dbMono(12, color))),
        ]),
      );
}

class _QrPanel extends StatelessWidget {
  final LiveHostViewModel vm;
  const _QrPanel({required this.vm});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Db.slate,
        border: Border.fromBorderSide(BorderSide(color: Db.rule)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.qr_code_2, size: 16, color: Db.mute),
          const SizedBox(width: 8),
          Text('SCAN TO JOIN', style: dbSectionTitle),
          const Spacer(),
          Text('${vm.secondsLeft}s', style: dbMono(13, Db.segnale, wght: 700)),
        ]),
        const SizedBox(height: 16),
        Center(
          child: Container(
            padding: const EdgeInsets.all(14),
            color: Colors.white,
            child: vm.ticketUrl == null
                ? const SizedBox(
                    width: 220, height: 220, child: ColoredBox(color: Colors.white))
                : QrImageView(
                    data: vm.ticketUrl!,
                    version: QrVersions.auto,
                    size: 220,
                    backgroundColor: Colors.white,
                  ),
          ),
        ),
        const SizedBox(height: 14),
        Text('Rotates every 25s. Voters scan, generate an ephemeral identity, '
            'and show you a 4-digit code to confirm face-to-face.',
            style: dbMono(11, Db.mute, height: 1.5)),
        if (vm.orgPubKey != null) ...[
          const SizedBox(height: 10),
          Text('ORG KEY', style: dbLabel(size: 9)),
          const SizedBox(height: 3),
          Text('${vm.orgPubKey!.substring(0, 16)}…',
              style: dbMono(10, Db.muteDim)),
        ],
      ]),
    );
  }
}

class _QueuePanel extends StatelessWidget {
  final LiveHostViewModel vm;
  const _QueuePanel({required this.vm});
  @override
  Widget build(BuildContext context) {
    final pending = vm.queue.where((v) => v.status == 'pending').toList();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Db.slate,
        border: Border.fromBorderSide(BorderSide(color: Db.rule)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.groups_outlined, size: 16, color: Db.mute),
          const SizedBox(width: 8),
          Text('PENDING QUEUE', style: dbSectionTitle),
          const Spacer(),
          Text('${pending.length}', style: dbLabel(size: 11, tracking: 0.05)),
        ]),
        const SizedBox(height: 16),
        if (pending.isEmpty)
          Text('No one waiting. Share the QR to gather voters.',
              style: dbMono(11, Db.mute, height: 1.5))
        else
          for (final v in pending) ...[
            _VoterRow(v: v, busy: vm.busy, onConfirm: () => vm.confirm(v)),
            const SizedBox(height: 10),
          ],
      ]),
    );
  }
}

class _VoterRow extends StatelessWidget {
  final PendingVoter v;
  final bool busy;
  final VoidCallback onConfirm;
  const _VoterRow(
      {required this.v, required this.busy, required this.onConfirm});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: const BoxDecoration(
          color: Db.void_,
          border: Border.fromBorderSide(BorderSide(color: Db.rule)),
        ),
        child: Row(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('CODE', style: dbLabel(size: 9)),
            const SizedBox(height: 2),
            Text(v.confirmationCode,
                style: dbMono(22, Db.segnale, wght: 700, letterSpacing: 2)),
          ]),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'id ${v.ephemeralIdentityCommitment.length > 12 ? '${v.ephemeralIdentityCommitment.substring(0, 12)}…' : v.ephemeralIdentityCommitment}',
              style: dbMono(10, Db.muteDim),
            ),
          ),
          InkWell(
            onTap: busy ? null : onConfirm,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              color: busy ? Db.slate : Db.success,
              child: Text('CONFIRM',
                  style: dbSans(11, 800, busy ? Db.mute : Db.void_,
                      letterSpacing: 1.0)),
            ),
          ),
        ]),
      );
}

class _PhaseControls extends StatelessWidget {
  final LiveHostViewModel vm;
  const _PhaseControls({required this.vm});
  @override
  Widget build(BuildContext context) {
    if (!vm.canHost) return const SizedBox.shrink();
    return Row(children: [
      Expanded(
        child: _btn('START VOTING', vm.busy ? null : vm.startVoting),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _btn('END VOTING', vm.busy ? null : vm.endVoting, secondary: true),
      ),
    ]);
  }

  Widget _btn(String label, VoidCallback? onTap, {bool secondary = false}) =>
      InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: secondary ? Db.void_ : (onTap != null ? Db.segnale : Db.void_),
            border: Border.all(
                color: onTap != null ? (secondary ? Db.rule : Db.segnale) : Db.rule),
          ),
          child: Text(label,
              style: dbSans(12, 800,
                  secondary ? Db.chalkDim : (onTap != null ? Db.void_ : Db.mute),
                  letterSpacing: 1.1)),
        ),
      );
}

class _Error extends StatelessWidget {
  final String message;
  const _Error({required this.message});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off, color: Db.segnale, size: 40),
            const SizedBox(height: 12),
            Text("COULDN'T START THE SESSION",
                style: dbLabel(size: 12, color: Db.chalk)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: dbMono(12, Db.mute)),
          ]),
        ),
      );
}
