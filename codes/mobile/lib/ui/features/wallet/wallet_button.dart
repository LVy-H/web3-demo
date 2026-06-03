import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:reown_appkit/reown_appkit.dart';

import '../../../data/services/wallet_service.dart';
import '../../core/theme.dart';

/// Connect-Wallet button backed by the app-level [WalletService], so the same
/// session is shared with the Create screen. Shows a hint when the platform is
/// unsupported or WC_PROJECT_ID is unset; the connect/sign flow itself is only
/// verifiable on a real device/browser with a wallet (not headlessly).
class WalletButton extends StatefulWidget {
  const WalletButton({super.key});
  @override
  State<WalletButton> createState() => _WalletButtonState();
}

class _WalletButtonState extends State<WalletButton> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<WalletService>().ensureInit(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final w = context.watch<WalletService>();
    if (!w.supported) return const SizedBox.shrink();
    // Concise, non-jargon labels — the old 'WALLET · SET WC_PROJECT_ID' was a
    // fixed-width pill that overflowed any tight Row (drawer, create banner).
    if (!w.configured) return const _Hint(label: 'WALLET NOT CONFIGURED');
    if (w.error != null) return const _Hint(label: 'WALLET UNAVAILABLE');
    if (!w.ready) return const _Hint(label: 'CONNECTING WALLET…');
    return AppKitModalConnectButton(appKit: w.modal!);
  }
}

/// Non-interactive status pill shown when the wallet can't connect (unconfigured
/// / errored / still initializing). Root-hardened against overflow: the label is
/// [Flexible] with an ellipsis so the pill shrinks to fit any tight Row instead
/// of overflowing (it used to be a fixed-width `Row(mainAxisSize: min)` with no
/// ellipsis). The icon stays fixed; only the text gives way.
@visibleForTesting
class WalletHintPill extends StatelessWidget {
  final String label;
  const WalletHintPill({super.key, required this.label});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: const BoxDecoration(
          color: Db.slate3,
          border: Border.fromBorderSide(BorderSide(color: Db.rule)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.account_balance_wallet_outlined,
              size: 13, color: Db.mute),
          const SizedBox(width: 8),
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: dbLabel(size: 11, tracking: 0.1)),
          ),
        ]),
      );
}

/// Internal alias kept for the call sites above.
class _Hint extends StatelessWidget {
  final String label;
  const _Hint({required this.label});
  @override
  Widget build(BuildContext context) => WalletHintPill(label: label);
}
