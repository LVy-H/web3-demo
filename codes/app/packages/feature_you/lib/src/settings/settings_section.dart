import 'package:core_chain/config.dart';
import 'package:core_storage/network_config_store.dart';
import 'package:design_system/theme.dart';
import 'package:flutter/material.dart';

import '../widgets/you_widgets.dart';
import 'about_screen.dart';
import 'diagnostics_screen.dart';
import 'network_settings_screen.dart';

/// The settings block of the YOU space: network, diagnostics, about. Each
/// row pushes a plain page route — settings sub-pages are not deep-link
/// surfaces, so they stay off the router table (which R3 must not touch).
class SettingsSection extends StatelessWidget {
  final NetworkConfigStore networkConfigStore;

  /// R2f's capability re-probe hook (AppState.refreshCapabilities), run
  /// after a network-config save.
  final Future<void> Function() onNetworkConfigChanged;
  final Future<bool> Function() checkChain;
  final Future<bool> Function() checkRelayer;
  final bool canProve;
  final String? appVersion;

  const SettingsSection({
    super.key,
    required this.networkConfigStore,
    required this.onNetworkConfigChanged,
    required this.checkChain,
    required this.checkRelayer,
    required this.canProve,
    this.appVersion,
  });

  void _push(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const YouSectionLabel('SETTINGS'),
      const SizedBox(height: 8),
      YouRowsPanel(
        rows: [
          YouLinkRow(
            label: 'Network',
            detail: AppConfig.isOverridden ? 'custom' : 'defaults',
            onTap: () => _push(
              context,
              NetworkSettingsScreen(
                store: networkConfigStore,
                onConfigChanged: onNetworkConfigChanged,
              ),
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Db.ruleSoft),
          YouLinkRow(
            label: 'Diagnostics',
            onTap: () => _push(
              context,
              DiagnosticsScreen(
                checkChain: checkChain,
                checkRelayer: checkRelayer,
                canProve: canProve,
              ),
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Db.ruleSoft),
          YouLinkRow(
            label: 'About',
            onTap: () => _push(context, AboutScreen(version: appVersion)),
          ),
        ],
      ),
    ],
  );
}
