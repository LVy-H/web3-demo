import 'package:core_chain/config.dart';
import 'package:design_system/dot_grid_background.dart';
import 'package:design_system/format.dart';
import 'package:design_system/theme.dart';
import 'package:flutter/material.dart';

import '../widgets/you_widgets.dart';

/// About: what this app is, which backend it points at, and (when the shell
/// passes one) the build version. No network calls, no secrets.
class AboutScreen extends StatelessWidget {
  /// Build version label (e.g. "0.3.0+1"). Hidden when null — feature_you
  /// has no package_info dependency; the shell may inject one later.
  final String? version;

  const AboutScreen({super.key, this.version});

  static String _host(String url) => Uri.tryParse(url)?.host ?? url;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent),
      body: DotGridBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text('ABOUT', style: dbHero(40)),
                  const SizedBox(height: 8),
                  Text(
                    'Tessera — anonymous voting with receipts anyone can '
                    'check. Your vote is secret; that it was counted is '
                    'public.',
                    style: dbSans(13, 500, Db.chalkDim, height: 1.5),
                  ),
                  const SizedBox(height: 22),
                  const YouSectionLabel('APP'),
                  const SizedBox(height: 8),
                  YouRowsPanel(
                    rows: [
                      const YouInfoRow(label: 'App', value: 'Tessera'),
                      if (version != null)
                        YouInfoRow(label: 'Version', value: version!),
                      const YouInfoRow(
                        label: 'Privacy',
                        value: 'zero-knowledge proofs (Semaphore v4)',
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const YouSectionLabel('BACKEND'),
                  const SizedBox(height: 8),
                  YouRowsPanel(
                    rows: [
                      YouInfoRow(
                        label: 'Mode',
                        value: AppConfig.isOverridden
                            ? 'custom backend'
                            : 'built-in defaults',
                      ),
                      YouInfoRow(label: 'Chain', value: '${AppConfig.chainId}'),
                      YouInfoRow(label: 'RPC', value: _host(AppConfig.rpcUrl)),
                      YouInfoRow(
                        label: 'Relayer',
                        value: _host(AppConfig.relayerUrl),
                      ),
                      YouInfoRow(
                        label: 'Registry',
                        value: shortAddr(AppConfig.registryAddress),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
