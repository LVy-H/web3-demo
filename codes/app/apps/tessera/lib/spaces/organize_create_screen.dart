// R3 replaces this file with the real create flow (sponsored creation as THE
// path when no signer; spec §4.3). The router does not change when it does —
// only this file.
import 'package:core_domain/journeys/capabilities.dart';
import 'package:design_system/theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'space_placeholder.dart';

/// Guard policy: this route is a PASS-THROUGH even when no signer path
/// exists (no dev signer, relayer unreachable) — the screen renders the
/// disabled state with the honest why-not, instead of the router hiding it.
class OrganizeCreateScreen extends StatelessWidget {
  const OrganizeCreateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final capabilities = context.watch<AppState>().capabilities;
    final hasSignerPath = capabilities.canSign || capabilities.relayerAvailable;
    final whyNot =
        capabilities.reasonFor(Capability.relayer) ??
        capabilities.reasonFor(Capability.sign) ??
        'reason.sign.noSigner';

    return SpacePlaceholder(
      title: 'CREATE',
      caption: 'Create a poll — R3 placeholder',
      showBack: true,
      children: [
        if (hasSignerPath)
          Text(
            'Creation is available on this device. The real create flow '
            'lands in R3.',
            style: dbSans(13, 400, Db.chalkDim),
          )
        else ...[
          Text(
            'Creating a poll needs a connection this device does not have '
            'right now.',
            style: dbSans(13, 400, Db.chalkDim),
          ),
          const SizedBox(height: 12),
          PlaceholderRow(label: 'why', value: whyNot),
        ],
      ],
    );
  }
}
