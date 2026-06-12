import 'package:core_storage/identity_store.dart';
import 'package:core_storage/network_config_store.dart';
import 'package:design_system/dot_grid_background.dart';
import 'package:design_system/theme.dart';
import 'package:flutter/material.dart';

import 'pass/voting_pass_controller.dart';
import 'pass/voting_pass_section.dart';
import 'receipts/receipts_section.dart';
import 'receipts/receipts_store.dart';
import 'settings/settings_section.dart';

/// The YOU space (spec §4.1): voting pass, receipts archive, verify entry
/// and settings on one surface. Pure feature widget — every dependency is
/// injected by the shell's thin `you_space_screen.dart` glue (stores from
/// DI, the AppState identity/capability hooks as callbacks, navigation as a
/// callback), so this package never imports the router or provider.
class YouSpaceView extends StatefulWidget {
  final IdentityStore identityStore;

  /// Awaited after every pass change — production wires
  /// `AppState.refreshIdentity` so guards see the new identity presence.
  final Future<void> Function() onPassChanged;

  /// Registration-code derivation; `null` where no prover exists.
  final RegistrationCodeDeriver? deriveRegistrationCode;

  final ReceiptsStore receiptsStore;

  /// Open `/you/verify`, optionally pre-filled from a receipt.
  final void Function(String? pollAddress, String? receiptCode) onOpenVerify;

  final NetworkConfigStore networkConfigStore;

  /// R2f capability re-probe hook (`AppState.refreshCapabilities`).
  final Future<void> Function() onNetworkConfigChanged;
  final Future<bool> Function() checkChain;
  final Future<bool> Function() checkRelayer;
  final bool canProve;
  final String? appVersion;

  const YouSpaceView({
    super.key,
    required this.identityStore,
    required this.onPassChanged,
    required this.receiptsStore,
    required this.onOpenVerify,
    required this.networkConfigStore,
    required this.onNetworkConfigChanged,
    required this.checkChain,
    required this.checkRelayer,
    required this.canProve,
    this.deriveRegistrationCode,
    this.appVersion,
  });

  @override
  State<YouSpaceView> createState() => _YouSpaceViewState();
}

class _YouSpaceViewState extends State<YouSpaceView> {
  late final VotingPassController _passController = VotingPassController(
    store: widget.identityStore,
    onPassChanged: widget.onPassChanged,
    deriveRegistrationCode: widget.deriveRegistrationCode,
  );

  @override
  void initState() {
    super.initState();
    _passController.load();
  }

  @override
  void dispose() {
    _passController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: DotGridBackground(
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
              children: [
                Text('YOU', style: dbHero(48)),
                const SizedBox(height: 10),
                Text(
                  'Your voting pass, your receipts, your settings. Nothing '
                  'here leaves this device unless you share it.',
                  style: dbSans(14, 400, Db.chalkDim, height: 1.6),
                ),
                const SizedBox(height: 24),
                VotingPassSection(controller: _passController),
                const SizedBox(height: 28),
                ReceiptsSection(
                  store: widget.receiptsStore,
                  onOpenVerify: widget.onOpenVerify,
                ),
                const SizedBox(height: 28),
                SettingsSection(
                  networkConfigStore: widget.networkConfigStore,
                  onNetworkConfigChanged: widget.onNetworkConfigChanged,
                  checkChain: widget.checkChain,
                  checkRelayer: widget.checkRelayer,
                  canProve: widget.canProve,
                  appVersion: widget.appVersion,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
