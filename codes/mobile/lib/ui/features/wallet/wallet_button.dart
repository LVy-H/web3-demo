import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:reown_appkit/reown_appkit.dart';

import '../../../config.dart';
import '../../core/theme.dart';

/// Reown AppKit (WalletConnect) connect button. Cross-platform connect-wallet
/// flow — pairs with MetaMask-mobile and any wallet on web + Android/iOS + macOS.
///
/// Platform reality: reown supports web/mobile/macOS, NOT Linux/Windows desktop,
/// so the button hides there. Needs a Reown projectId (--dart-define WC_PROJECT_ID);
/// without one it shows a hint rather than initializing. The connect/sign flow
/// must be verified on a real browser/device with a wallet — it can't be tested
/// headlessly.
bool get walletSupported =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS;

class WalletButton extends StatefulWidget {
  const WalletButton({super.key});
  @override
  State<WalletButton> createState() => _WalletButtonState();
}

class _WalletButtonState extends State<WalletButton> {
  ReownAppKitModal? _modal;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (walletSupported && AppConfig.walletConnectProjectId.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _init());
    }
  }

  Future<void> _init() async {
    try {
      final modal = ReownAppKitModal(
        context: context,
        projectId: AppConfig.walletConnectProjectId,
        metadata: const PairingMetadata(
          name: 'ZK Vote',
          description: 'Anonymous ZK voting',
          url: 'https://zkvote.app',
          icons: ['https://avatars.githubusercontent.com/u/37784886'],
        ),
      );
      await modal.init();
      if (mounted) setState(() => _modal = modal);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!walletSupported) return const SizedBox.shrink();
    if (AppConfig.walletConnectProjectId.isEmpty) {
      return _Hint(label: 'WALLET · SET WC_PROJECT_ID');
    }
    if (_error != null) return const _Hint(label: 'WALLET UNAVAILABLE');
    if (_modal == null) return const _Hint(label: 'WALLET…');
    return AppKitModalConnectButton(appKit: _modal!);
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
