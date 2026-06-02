import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../data/services/poll_creator.dart';
import '../../../data/services/wallet_service.dart';
import '../../core/dot_grid_background.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../wallet/wallet_button.dart';

/// Create an anon-vote poll from mobile. Signs `PollRegistry.createPoll` through
/// the connected wallet (via [WalletService]). Deploy is gated on a wallet
/// connection; on-chain creation needs a chain the mobile wallet can reach
/// (a public testnet — not the host-local Hardhat node).
class CreateScreen extends StatefulWidget {
  const CreateScreen({super.key});
  @override
  State<CreateScreen> createState() => _CreateScreenState();
}

class _CreateScreenState extends State<CreateScreen> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _options = <TextEditingController>[
    TextEditingController(text: 'Yes'),
    TextEditingController(text: 'No'),
  ];
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    for (final c in _options) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _deploy(WalletService w) async {
    final creator = context.read<PollCreator>();
    final title = _title.text.trim();
    final opts =
        _options.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
    if (title.isEmpty || opts.length < 2) {
      _snack('Add a title and at least two options.');
      return;
    }
    setState(() => _busy = true);
    try {
      // Dev-signer (DEV_PRIVATE_KEY) bypasses wallet connection for local dev.
      final tx = creator.canSign
          ? await creator.createAnonPoll(
              title: title, description: _desc.text.trim(), options: opts)
          : await w.createPoll(
              title: title, description: _desc.text.trim(), options: opts);
      if (!mounted) return;
      _snack('Deploy sent · ${shortAddr(tx)}');
      context.canPop() ? context.pop() : context.go('/');
    } catch (e) {
      if (mounted) _snack('Deploy failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m, style: dbMono(12, Db.chalk)),
        backgroundColor: Db.slate,
      ));

  @override
  Widget build(BuildContext context) {
    final w = context.watch<WalletService>();
    final devSigner = context.read<PollCreator>().canSign;
    return Scaffold(
      body: DotGridBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text('CREATE', style: dbHero(48)),
                  const SizedBox(height: 10),
                  Text(
                    'Deploy an anonymous anon-vote poll, signed by your wallet.',
                    style: dbSans(13, 400, Db.chalkDim, height: 1.5),
                  ),
                  const SizedBox(height: 20),
                  _walletBanner(w, devSigner),
                  const SizedBox(height: 22),
                  _field('TITLE', _title, 'Adopt the new logo?'),
                  const SizedBox(height: 16),
                  _field('DESCRIPTION', _desc, 'Optional context', maxLines: 3),
                  const SizedBox(height: 20),
                  Text('OPTIONS', style: dbLabel(size: 10, tracking: 0.16)),
                  const SizedBox(height: 10),
                  for (var i = 0; i < _options.length; i++) _optionRow(i),
                  const SizedBox(height: 6),
                  _addOptionButton(),
                  const SizedBox(height: 28),
                  _deployButton(w, devSigner),
                  const SizedBox(height: 14),
                  Text(
                    devSigner
                        ? 'Dev signer active (DEV_PRIVATE_KEY) — deploys are '
                            'signed locally and broadcast straight to the '
                            'configured RPC. No wallet needed.'
                        : 'Creating a poll signs an on-chain transaction. A phone '
                            'wallet can only broadcast to a chain it can reach — '
                            'use a public testnet, not the host-local Hardhat node.',
                    style: dbMono(10, Db.muteDim, height: 1.6),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _walletBanner(WalletService w, bool devSigner) {
    if (devSigner) {
      final addr = context.read<PollCreator>().signer ?? '';
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Db.slate,
          border: Border(left: BorderSide(color: Db.success, width: 3)),
        ),
        child: Row(children: [
          const Icon(Icons.vpn_key_outlined, size: 18, color: Db.success),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Dev signer active\n$addr',
                style: dbMono(11, Db.chalkDim, height: 1.5)),
          ),
        ]),
      );
    }
    final connected = w.isConnected;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Db.slate,
        border: Border(
            left: BorderSide(
                color: connected ? Db.success : Db.segnale, width: 3)),
      ),
      child: Row(children: [
        Icon(
            connected
                ? Icons.check_circle_outline
                : Icons.account_balance_wallet_outlined,
            size: 18,
            color: connected ? Db.success : Db.segnale),
        const SizedBox(width: 12),
        Expanded(
          child: connected
              ? Text('Wallet connected\n${w.address ?? ''}',
                  style: dbMono(11, Db.chalkDim, height: 1.5))
              : Text('Connect a wallet to deploy',
                  style: dbSans(13, 600, Db.chalk)),
        ),
        if (!connected) const WalletButton(),
      ]),
    );
  }

  Widget _field(String label, TextEditingController c, String hint,
          {int maxLines = 1}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: dbLabel(size: 10, tracking: 0.16)),
        const SizedBox(height: 8),
        TextField(
          controller: c,
          maxLines: maxLines,
          style: dbSans(15, 600, Db.chalk),
          cursorColor: Db.segnale,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: Db.slate3,
            hintText: hint,
            hintStyle: dbSans(14, 400, Db.muteDim),
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

  Widget _optionRow(int i) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Text('0${i + 1}', style: dbMono(13, Db.mute, wght: 700)),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _options[i],
              style: dbSans(14, 600, Db.chalk),
              cursorColor: Db.segnale,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: Db.slate3,
                hintText: 'Option ${i + 1}',
                hintStyle: dbSans(13, 400, Db.muteDim),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                enabledBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(color: Db.rule)),
                focusedBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(color: Db.segnale)),
              ),
            ),
          ),
          if (_options.length > 2)
            IconButton(
              icon: const Icon(Icons.close, size: 16, color: Db.mute),
              onPressed: () => setState(() => _options.removeAt(i).dispose()),
            ),
        ]),
      );

  Widget _addOptionButton() => Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () =>
              setState(() => _options.add(TextEditingController())),
          icon: const Icon(Icons.add, size: 15, color: Db.chalkDim),
          label:
              Text('ADD OPTION', style: dbLabel(size: 11, color: Db.chalkDim)),
        ),
      );

  Widget _deployButton(WalletService w, bool devSigner) {
    final canDeploy = devSigner || w.isConnected;
    final enabled = canDeploy && !_busy;
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: enabled ? () => _deploy(w) : null,
        style: FilledButton.styleFrom(
          backgroundColor: Db.segnale,
          disabledBackgroundColor: Db.slate,
          foregroundColor: Db.chalk,
          shape: const RoundedRectangleBorder(),
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        child: Text(
          _busy
              ? 'DEPLOYING…'
              : (devSigner
                  ? 'DEPLOY POLL (DEV SIGNER)'
                  : (w.isConnected ? 'DEPLOY POLL' : 'CONNECT WALLET FIRST')),
          style: dbSans(13, 800, canDeploy ? Db.chalk : Db.mute,
              letterSpacing: 1.4),
        ),
      ),
    );
  }
}
