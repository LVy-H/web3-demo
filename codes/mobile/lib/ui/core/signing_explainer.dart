import 'package:flutter/material.dart';

import 'theme.dart';

/// A themed bottom sheet that explains Tessera's signing model in one place,
/// leading with the reassurance that matters most: **you don't need a wallet.**
///
/// The create screen already shows the *active* path inline; this is the
/// holistic "what are my options" view, reusable from Settings (and later the
/// vote flow). Static content — no providers, no async — so it is trivially
/// widget-testable and can't fail at runtime.
Future<void> showSigningExplainerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Db.void_,
    builder: (_) => const _SigningExplainerSheet(),
  );
}

class _SigningExplainerSheet extends StatelessWidget {
  const _SigningExplainerSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'HOW SIGNING WORKS',
                    style: dbLabel(size: 12, tracking: 0.16),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Db.mute, size: 20),
                    splashRadius: 18,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                "You don't need a wallet.",
                style: dbSans(20, 800, Db.chalk, height: 1.2),
              ),
              const SizedBox(height: 8),
              Text(
                'Tessera is wallet-free by design. Your vote is always your own '
                'anonymous ZK proof — these paths only decide who pays the gas '
                'and submits the transaction for you.',
                style: dbMono(12, Db.mute, height: 1.55),
              ),
              const SizedBox(height: 20),
              _path(
                accent: Db.success,
                icon: Icons.bolt_outlined,
                tag: 'DEFAULT',
                title: 'Wallet-free (sponsored relayer)',
                body:
                    'A relayer pays the gas and submits for you. Nothing to '
                    'install, no keys to manage — just create, join, and vote.',
              ),
              const SizedBox(height: 12),
              _path(
                accent: Db.segnale,
                icon: Icons.vpn_key_outlined,
                tag: 'LOCAL DEV',
                title: 'Local dev-signer',
                body:
                    'A DEV_PRIVATE_KEY that signs directly on a local chain. '
                    'For development only — never shipped to users.',
              ),
              const SizedBox(height: 12),
              _path(
                accent: Db.mute,
                icon: Icons.account_balance_wallet_outlined,
                tag: 'ADVANCED',
                title: 'Connect a wallet',
                body:
                    'Optional. Sign with your own wallet (WalletConnect) on a '
                    'public network — a device-only advanced path, pending '
                    'public-testnet deployment.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _path({
    required Color accent,
    required IconData icon,
    required String tag,
    required String title,
    required String body,
  }) => Container(
    decoration: BoxDecoration(
      color: Db.slate,
      border: Border(left: BorderSide(color: accent, width: 3)),
    ),
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: dbSans(13, 700, Db.chalk),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(tag, style: dbLabel(size: 9, color: accent)),
          ],
        ),
        const SizedBox(height: 8),
        Text(body, style: dbMono(11, Db.mute, height: 1.5)),
      ],
    ),
  );
}
