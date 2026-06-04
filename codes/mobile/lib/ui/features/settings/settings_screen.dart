import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../../config.dart';
import '../../../data/services/chain_writer.dart';
import '../../../data/services/proof_service_factory.dart';
import '../../../data/services/relay_client.dart';
import '../../core/dot_grid_background.dart';
import '../../core/format.dart';
import '../../core/signing_explainer.dart';
import '../../core/theme.dart';

/// The Settings "Signer" value, resolved to the *active* signing path. Pure so
/// it can be unit-tested. Priority: local dev-signer → wallet-free sponsored
/// relayer → wallet fallback. `sponsoredReady == null` means the relayer probe
/// is still in flight.
String signerStatusLabel({
  required bool canSign,
  required String? signerAddress,
  required bool? sponsoredReady,
}) {
  if (canSign) return 'dev signer · ${shortAddr(signerAddress ?? '')}';
  if (sponsoredReady == null) return '…';
  if (sponsoredReady) return 'wallet-free (sponsored relayer)';
  return 'wallet (connect to sign)';
}

/// Read-only diagnostics + about: the network the app talks to, how it signs and
/// proves, the identity shortcut, and the app version. A release-readiness aid.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _version = '…';
  bool? _sponsoredReady; // null while the relayer probe is in flight

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform()
        .then((info) {
          if (mounted) {
            setState(() => _version = '${info.version}+${info.buildNumber}');
          }
        })
        .catchError((_) {
          if (mounted) setState(() => _version = AppConfig.chainId.toString());
        });
    // Probe the relayer so the signer row can tell the truth about the
    // wallet-free sponsored path instead of implying a wallet is required.
    context
        .read<RelayClient>()
        .getRelayerInfo()
        .then((info) {
          if (mounted) {
            setState(
              () => _sponsoredReady = info != null && info.registry != null,
            );
          }
        })
        .catchError((_) {
          if (mounted) setState(() => _sponsoredReady = false);
        });
  }

  static String _host(String url) => Uri.tryParse(url)?.host ?? url;

  String get _proving {
    if (proofServiceAvailable) {
      return AppConfig.desktopProverEnabled ? 'desktop (Node sidecar)' : 'web';
    }
    return 'read-only (no prover)';
  }

  @override
  Widget build(BuildContext context) {
    final writer = context.read<ChainWriter>();
    final signer = signerStatusLabel(
      canSign: writer.canSign,
      signerAddress: writer.signerAddress,
      sponsoredReady: _sponsoredReady,
    );
    return Scaffold(
      body: DotGridBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text('SETTINGS', style: dbHero(44)),
                  const SizedBox(height: 20),
                  _section('NETWORK', [
                    _row('Chain', '${AppConfig.chainId}'),
                    _row('RPC', _host(AppConfig.rpcUrl)),
                    _row('Relayer', _host(AppConfig.relayerUrl)),
                    _row('Registry', shortAddr(AppConfig.registryAddress)),
                  ]),
                  const SizedBox(height: 18),
                  _section('SIGNING & PROVING', [
                    _row('Signer', signer),
                    _row('Proving', _proving),
                    _linkRow(
                      'How signing works',
                      () => showSigningExplainerSheet(context),
                    ),
                  ]),
                  const SizedBox(height: 18),
                  _section('IDENTITY', [
                    _linkRow('Manage identity', () => context.go('/identity')),
                  ]),
                  const SizedBox(height: 18),
                  _section('ABOUT', [
                    _row('App', 'Tessera'),
                    _row('Version', _version),
                    _row('Protocol', 'Semaphore v4 (ZK)'),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> rows) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: dbLabel(size: 10, tracking: 0.16)),
      const SizedBox(height: 8),
      Container(
        decoration: const BoxDecoration(
          color: Db.slate,
          border: Border.fromBorderSide(BorderSide(color: Db.rule)),
        ),
        child: Column(children: rows),
      ),
    ],
  );

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    // Both sides are Flexible with ellipsis so the row can't overflow when
    // the system font scale is enlarged (the label used to be fixed-width
    // and pushed the row past the edge at textScale > 1.0 on narrow phones).
    // The Spacer keeps the value pinned to the right edge when both fit.
    child: Row(
      children: [
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: dbSans(13, 600, Db.chalkDim),
          ),
        ),
        const SizedBox(width: 12),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: dbMono(12, Db.chalk),
          ),
        ),
      ],
    ),
  );

  Widget _linkRow(String label, VoidCallback onTap) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      // Expanded label so it ellipsizes under an enlarged font scale instead
      // of pushing the trailing arrow off the right edge.
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: dbSans(13, 600, Db.chalk),
            ),
          ),
          const SizedBox(width: 12),
          const Icon(Icons.arrow_forward, size: 14, color: Db.segnale),
        ],
      ),
    ),
  );
}
