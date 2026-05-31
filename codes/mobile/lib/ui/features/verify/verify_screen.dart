import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/dot_grid_background.dart';
import '../../core/theme.dart';
import 'verify_view_model.dart';

/// Public receipt verifier — enter a poll address + nullifier; confirm a vote
/// was counted without revealing the option. Supports deep links
/// (/verify?poll=…&nullifier=…) that prefill + auto-check.
class VerifyScreen extends StatefulWidget {
  final String? initialPoll;
  final String? initialNullifier;
  const VerifyScreen({super.key, this.initialPoll, this.initialNullifier});
  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  late final _poll = TextEditingController(text: widget.initialPoll ?? '');
  late final _nullifier =
      TextEditingController(text: widget.initialNullifier ?? '');

  @override
  void initState() {
    super.initState();
    if ((widget.initialPoll ?? '').isNotEmpty &&
        (widget.initialNullifier ?? '').isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _run());
    }
  }

  @override
  void dispose() {
    _poll.dispose();
    _nullifier.dispose();
    super.dispose();
  }

  void _run() => context
      .read<VerifyViewModel>()
      .verify(_poll.text, _nullifier.text);

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<VerifyViewModel>();
    return Scaffold(
      body: DotGridBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () =>
                          context.canPop() ? context.pop() : context.go('/'),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.arrow_back, size: 14, color: Db.mute),
                        const SizedBox(width: 6),
                        Text('BACK', style: dbLabel(size: 11, tracking: 0.16)),
                      ]),
                    ),
                    const SizedBox(height: 20),
                    Text('VERIFY', style: dbHero(56)),
                    const SizedBox(height: 10),
                    Text(
                      'Confirm a vote was counted — without revealing who voted or which option.',
                      style: dbSans(14, 400, Db.chalkDim, height: 1.6),
                    ),
                    const SizedBox(height: 24),
                    _field('POLL ADDRESS', _poll, '0x…'),
                    const SizedBox(height: 16),
                    _field('NULLIFIER', _nullifier, 'decimal string'),
                    const SizedBox(height: 18),
                    _VerifyButton(
                      busy: vm.verdict == VerifyVerdict.checking,
                      onTap: _run,
                    ),
                    const SizedBox(height: 20),
                    _Verdict(vm: vm),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController c, String hint) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: dbLabel(size: 10)),
          const SizedBox(height: 8),
          TextField(
            controller: c,
            style: dbMono(13, Db.chalk),
            cursorColor: Db.segnale,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: Db.void_,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              hintText: hint,
              hintStyle: dbMono(12, Db.mute),
              enabledBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: Db.rule)),
              focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: Db.segnale)),
            ),
          ),
        ],
      );
}

class _VerifyButton extends StatelessWidget {
  final bool busy;
  final VoidCallback onTap;
  const _VerifyButton({required this.busy, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: busy ? null : onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 15),
          alignment: Alignment.center,
          color: Db.segnale,
          child: Text(busy ? 'CHECKING…' : 'VERIFY RECEIPT',
              style: dbSans(13, 800, Db.void_, letterSpacing: 13 * 0.14)),
        ),
      );
}

class _Verdict extends StatelessWidget {
  final VerifyViewModel vm;
  const _Verdict({required this.vm});

  @override
  Widget build(BuildContext context) {
    switch (vm.verdict) {
      case VerifyVerdict.idle:
        return const SizedBox.shrink();
      case VerifyVerdict.checking:
        return const Padding(
          padding: EdgeInsets.only(top: 8),
          child: CircularProgressIndicator(color: Db.segnale),
        );
      case VerifyVerdict.verified:
        return _panel(Db.success, Icons.verified, 'VOTE VERIFIED',
            'This nullifier appears on-chain — the vote was counted. The option chosen is not revealed.');
      case VerifyVerdict.notFound:
        return _panel(Db.mute, Icons.help_outline, 'NOT FOUND',
            'No vote with this nullifier in this poll. Check the poll address and nullifier.');
      case VerifyVerdict.error:
        return _panel(Db.segnale, Icons.error_outline, 'ERROR',
            vm.error ?? 'Verification failed.');
    }
  }

  Widget _panel(Color color, IconData icon, String title, String body) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Db.slate,
          border: Border(left: BorderSide(color: color, width: 3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(title, style: dbSans(13, 800, color, letterSpacing: 1.4)),
          ]),
          const SizedBox(height: 8),
          Text(body, style: dbMono(12, Db.chalkDim, height: 1.5)),
        ]),
      );
}
