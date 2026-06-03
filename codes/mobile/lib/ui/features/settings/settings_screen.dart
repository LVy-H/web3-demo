import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../../config.dart';
import '../../../data/services/chain_writer.dart';
import '../../../data/services/proof_service_factory.dart';
import '../../core/dot_grid_background.dart';
import '../../core/format.dart';
import '../../core/theme.dart';

/// Read-only diagnostics + about: the network the app talks to, how it signs and
/// proves, the identity shortcut, and the app version. A release-readiness aid.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _version = '…';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) {
        setState(() => _version = '${info.version}+${info.buildNumber}');
      }
    }).catchError((_) {
      if (mounted) setState(() => _version = AppConfig.chainId.toString());
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
    final signer = writer.canSign
        ? 'dev signer · ${shortAddr(writer.signerAddress ?? '')}'
        : 'wallet (connect to sign)';
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
            decoration: BoxDecoration(
              color: Db.slate,
              border: Border.fromBorderSide(BorderSide(color: Db.rule)),
            ),
            child: Column(children: rows),
          ),
        ],
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(children: [
          Text(label, style: dbSans(13, 600, Db.chalkDim)),
          const Spacer(),
          Flexible(
            child: Text(value,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: dbMono(12, Db.chalk)),
          ),
        ]),
      );

  Widget _linkRow(String label, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(children: [
            Text(label, style: dbSans(13, 600, Db.chalk)),
            const Spacer(),
            Icon(Icons.arrow_forward, size: 14, color: Db.segnale),
          ]),
        ),
      );
}
