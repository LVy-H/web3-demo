// R3 replaces this file with the real You space (voting pass, receipts
// archive, verify-anything, settings). The router does not change when it
// does — only this file.
import 'package:design_system/theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'space_placeholder.dart';

class YouSpaceScreen extends StatelessWidget {
  const YouSpaceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return SpacePlaceholder(
      title: 'YOU',
      caption: 'Pass, receipts, settings — R3 placeholder',
      children: [
        PlaceholderRow(
          label: 'voting pass',
          value: appState.hasIdentity ? 'present on this device' : 'none yet',
        ),
        PlaceholderRow(
          label: 'capabilities',
          value: appState.capabilities.toString(),
        ),
        const SizedBox(height: 12),
        Text(
          'Your voting pass, receipts and verification land here in R3.',
          style: dbSans(13, 400, Db.chalkDim),
        ),
      ],
    );
  }
}
