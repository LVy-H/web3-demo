import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/dot_grid_background.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import 'live_vote_view_model.dart';
import 'qr_scan_sheet.dart';

/// Live-meeting VOTER. Scan/paste the organizer's QR ticket → mint an ephemeral
/// identity → show the 4-digit code face-to-face → wait to be confirmed → cast an
/// anonymous vote. Proving runs on web (or desktop with the Node sidecar); where
/// neither is available it says so.
class LiveVoteScreen extends StatefulWidget {
  final String address;
  const LiveVoteScreen({super.key, required this.address});
  @override
  State<LiveVoteScreen> createState() => _LiveVoteScreenState();
}

class _LiveVoteScreenState extends State<LiveVoteScreen> {
  final _ticket = TextEditingController();
  int? _selected;

  @override
  void initState() {
    super.initState();
    final vm = context.read<LiveVoteViewModel>();
    if (vm.ticket != null) _ticket.text = vm.ticket!;
  }

  @override
  void dispose() {
    _ticket.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<LiveVoteViewModel>();
    return Scaffold(
      body: DotGridBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  _header(context),
                  const SizedBox(height: 18),
                  if (!vm.canVote)
                    _banner(Icons.lock_outline,
                        'Live voting needs the prover (web, or desktop with the Node sidecar). This build is read-only.')
                  else
                    ..._stage(context, vm),
                  if (vm.error != null) ...[
                    const SizedBox(height: 14),
                    _banner(Icons.error_outline, vm.error!, color: Db.amber),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _stage(BuildContext context, LiveVoteViewModel vm) {
    switch (vm.stage) {
      case LiveVoteStage.needsTicket:
      case LiveVoteStage.error:
        return [
          Text('JOIN A LIVE VOTE', style: dbHero(34)),
          const SizedBox(height: 10),
          Text('Scan the organizer\'s QR (or paste its link/ticket below), then '
              'show them the code on the next screen.',
              style: dbSans(13, 400, Db.chalkDim, height: 1.5)),
          const SizedBox(height: 18),
          // Camera scan: only offered where a camera exists (mobile). On web /
          // desktop `cameraScanSupported` is false, so this is absent and the
          // paste field below is the sole — and verified — input. The scanned
          // value flows through the same setTicket → join path as paste, with
          // NO new parsing (extractTicket handles tessera://…?t=… and bare).
          if (cameraScanSupported) ...[
            _scanButton(context, vm),
            const SizedBox(height: 14),
          ],
          // The paste field is ALWAYS available (the verified fallback), and the
          // only input when the camera is unsupported or permission is denied.
          _field('TICKET / QR LINK', _ticket, 'paste the scanned value'),
          const SizedBox(height: 14),
          _button('JOIN', () {
            vm.setTicket(_ticket.text);
            vm.join();
          }),
        ];
      case LiveVoteStage.joining:
        return [_busy('Minting your identity…')];
      case LiveVoteStage.pending:
        return [
          Text('SHOW THIS CODE', style: dbLabel(size: 11, tracking: 0.16)),
          const SizedBox(height: 10),
          Center(
            child: Text(vm.code ?? '----',
                style: dbMono(64, Db.segnale, wght: 700, letterSpacing: 8)),
          ),
          const SizedBox(height: 14),
          Text('Show this 4-digit code to the organizer. Once they confirm you '
              'face-to-face, voting unlocks automatically.',
              style: dbMono(12, Db.mute, height: 1.5)),
          const SizedBox(height: 14),
          Row(children: [
            const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Db.segnale)),
            const SizedBox(width: 10),
            Text('waiting for confirmation…', style: dbMono(11, Db.muteDim)),
          ]),
        ];
      case LiveVoteStage.registered:
        return [
          _banner(Icons.verified, 'Confirmed — cast your anonymous vote.',
              color: Db.success),
          const SizedBox(height: 16),
          for (var i = 0; i < vm.options.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _option(vm.options[i], Db.optionColor(i), _selected == i,
                () => setState(() => _selected = i)),
          ],
          const SizedBox(height: 16),
          _button('CAST ANONYMOUS VOTE',
              _selected == null ? null : () => vm.castVote(_selected!)),
        ];
      case LiveVoteStage.proving:
        return [_busy('Generating zero-knowledge proof…')];
      case LiveVoteStage.relaying:
        return [_busy('Submitting your vote…')];
      case LiveVoteStage.done:
        return [
          _banner(Icons.check_circle,
              'Vote counted${vm.txHash != null ? ' · ${shortAddr(vm.txHash!)}' : ''}.',
              color: Db.success),
        ];
    }
  }

  /// "Scan QR" affordance shown next to the paste field on mobile. Opens the
  /// camera scanner sheet; on a decoded value, drives the same join path.
  Widget _scanButton(BuildContext context, LiveVoteViewModel vm) => SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => _openScanner(context, vm),
          icon: const Icon(Icons.qr_code_scanner, size: 18, color: Db.segnale),
          label: Text('SCAN QR',
              style: dbSans(13, 800, Db.segnale, letterSpacing: 1.2)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Db.segnale),
            shape: const RoundedRectangleBorder(),
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      );

  Future<void> _openScanner(BuildContext context, LiveVoteViewModel vm) async {
    final raw = await showQrScanSheet(
      context,
      title: 'SCAN QR TICKET',
      hint: "Point the camera at the organizer's QR. Can't scan? Close this and "
          "paste the link/ticket below instead.",
    );
    if (raw == null) return; // dismissed / camera unavailable → paste still works
    onScanned(vm, raw);
  }

  /// Test seam: feed a raw scanned string through the SAME wiring as paste —
  /// reflect it into the paste field (so it's visible/editable) then
  /// setTicket → join. No QR parsing here; `extractTicket` (in setTicket) does
  /// it. Exposed (not private) so a widget test can drive scan→join without a
  /// real camera platform channel.
  @visibleForTesting
  void onScanned(LiveVoteViewModel vm, String raw) {
    _ticket.text = raw;
    vm.setTicket(raw);
    vm.join();
  }

  Widget _header(BuildContext context) => Row(children: [
        Expanded(
          child: InkWell(
            onTap: () => context.canPop() ? context.pop() : context.go('/'),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.arrow_back, size: 14, color: Db.mute),
              const SizedBox(width: 6),
              Flexible(
                child: Text('BACK',
                    maxLines: 1,
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
          child: Text('LIVE · VOTE',
              style: dbSans(11, 800, Db.void_, letterSpacing: 1.6)),
        ),
      ]);

  Widget _busy(String label) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(children: [
          const CircularProgressIndicator(color: Db.segnale),
          const SizedBox(height: 16),
          Text(label, style: dbMono(12, Db.chalkDim)),
        ]),
      );

  Widget _banner(IconData icon, String text, {Color color = Db.segnale}) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Db.slate,
          border: Border(left: BorderSide(color: color, width: 3)),
        ),
        child: Row(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: dbMono(12, Db.chalkDim, height: 1.4))),
        ]),
      );

  Widget _field(String label, TextEditingController c, String hint) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: dbLabel(size: 10, tracking: 0.16)),
        const SizedBox(height: 8),
        TextField(
          controller: c,
          style: dbMono(12, Db.chalk),
          cursorColor: Db.segnale,
          maxLines: 2,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: Db.slate3,
            hintText: hint,
            hintStyle: dbMono(11, Db.muteDim),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            enabledBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: Db.rule)),
            focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: Db.segnale)),
          ),
        ),
      ]);

  Widget _option(String label, Color color, bool selected, VoidCallback onTap) =>
      InkWell(
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

  Widget _button(String label, VoidCallback? onTap) => SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: Db.segnale,
            disabledBackgroundColor: Db.slate,
            foregroundColor: Db.void_,
            shape: const RoundedRectangleBorder(),
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: Text(label,
              style: dbSans(13, 800, onTap != null ? Db.void_ : Db.mute,
                  letterSpacing: 1.2)),
        ),
      );
}
