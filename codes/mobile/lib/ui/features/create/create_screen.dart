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

/// Module type the Create screen can deploy. `anonVote` is the single-choice
/// default; `approvalVote` is the multi-select bitmask module. `blindVote` is
/// shown for discoverability but DISABLED here — its `initialize` needs a
/// reveal-window param the mobile create flow doesn't collect yet, so deploying
/// it from mobile is web-only (selecting it must never mis-deploy an anon poll).
enum _ModuleType { anonVote, approvalVote, blindVote }

class _CreateScreenState extends State<CreateScreen> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _options = <TextEditingController>[
    TextEditingController(text: 'Yes'),
    TextEditingController(text: 'No'),
  ];
  _ModuleType _module = _ModuleType.anonVote;
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
      // Module dispatch: approval-vote deploys the bitmask module; everything
      // else is the anon single-choice module. (Blind is disabled in the picker
      // so it can't reach here.)
      final String tx;
      if (creator.canSign) {
        tx = _module == _ModuleType.approvalVote
            ? await creator.createApprovalPoll(
                title: title, description: _desc.text.trim(), options: opts)
            : await creator.createAnonPoll(
                title: title, description: _desc.text.trim(), options: opts);
      } else {
        // The wallet path only deploys anon-vote today; approval over the wallet
        // path is a follow-up (the dev-signer is the supported approval create).
        tx = await w.createPoll(
            title: title, description: _desc.text.trim(), options: opts);
      }
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
                    'Deploy an anonymous poll — pick the voting type, then sign.',
                    style: dbSans(13, 400, Db.chalkDim, height: 1.5),
                  ),
                  const SizedBox(height: 20),
                  _walletBanner(w, devSigner),
                  const SizedBox(height: 22),
                  Text('VOTING TYPE', style: dbLabel(size: 10, tracking: 0.16)),
                  const SizedBox(height: 10),
                  _modulePicker(devSigner),
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

  // Module-type picker: anon (default) / approval / blind. Approval deploys the
  // multi-select bitmask module (the `approval-vote` string Browse uses to
  // dispatch the approval screen). Blind is shown but disabled — see [_ModuleType].
  // Approval create needs the dev-signer (the wallet path is anon-only today),
  // so when [devSigner] is false the approval tile is also disabled with a hint.
  Widget _modulePicker(bool devSigner) {
    final tiles = <Widget>[
      _moduleTile(
        type: _ModuleType.anonVote,
        title: 'Anonymous — single choice',
        subtitle: 'Pick exactly one option. (anon-vote)',
        icon: Icons.radio_button_checked,
        accent: Db.segnale,
        enabled: true,
      ),
      _moduleTile(
        type: _ModuleType.approvalVote,
        title: 'Approval — multi-select',
        subtitle: devSigner
            ? 'Approve any number of options; the tally counts every approval. '
                '(approval-vote)'
            : 'Needs the dev-signer to deploy from mobile. (approval-vote)',
        icon: Icons.check_box,
        accent: Db.oltremare,
        enabled: devSigner,
      ),
      _moduleTile(
        type: _ModuleType.blindVote,
        title: 'Blind — commit-reveal',
        subtitle: 'Create on the web app (needs a reveal window). (blind-vote)',
        icon: Icons.lock_clock,
        accent: Db.amber,
        enabled: false,
      ),
    ];
    return Column(children: [
      for (var i = 0; i < tiles.length; i++) ...[
        if (i > 0) const SizedBox(height: 8),
        tiles[i],
      ],
    ]);
  }

  Widget _moduleTile({
    required _ModuleType type,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accent,
    required bool enabled,
  }) {
    final selected = _module == type && enabled;
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: InkWell(
        onTap: enabled ? () => setState(() => _module = type) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: selected ? accent.withValues(alpha: 0.10) : Db.slate3,
            border: Border.all(
                color: selected ? accent : Db.rule, width: selected ? 2 : 1),
          ),
          child: Row(children: [
            Icon(icon, size: 18, color: selected ? accent : Db.mute),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: dbSans(14, 700, Db.chalk)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: dbMono(10, Db.mute, height: 1.4)),
                ],
              ),
            ),
            if (!enabled)
              const Icon(Icons.lock_outline, size: 14, color: Db.muteDim)
            else
              Icon(
                  selected
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 16,
                  color: selected ? accent : Db.muteDim),
          ]),
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
