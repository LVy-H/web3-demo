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
    if (!w.configured) return const _Hint(label: 'WALLET · SET WC_PROJECT_ID');
    if (w.error != null) return const _Hint(label: 'WALLET UNAVAILABLE');
    if (!w.ready) return const _Hint(label: 'WALLET…');
    return AppKitModalConnectButton(appKit: w.modal!);
  }
}

class _Hint extends StatelessWidget {
  final String label;
  const _Hint({required this.label});
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
          Text(label, style: dbLabel(size: 11, tracking: 0.1)),
        ]),
      );
}
