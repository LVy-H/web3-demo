// R3 refines the copy here (jargon-free pass); the screen itself — the
// honest "this device can't do that" exit for guard blocks — is structural
// and stays.
import 'package:design_system/theme.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'space_placeholder.dart';

/// Honest copy for known guard reason keys (spec §4.3). Unknown keys fall
/// back to the key itself so a new reason is never silently blank.
String copyForReason(String reasonKey) => switch (reasonKey) {
  'reason.prove.platformUnsupported' || 'reason.prove.unavailable' =>
    "Voting from this device isn't supported yet — vote on the web or "
        'Android.',
  'reason.relayer.unreachable' =>
    'The voting service could not be reached from this device.',
  _ => reasonKey,
};

class BlockedScreen extends StatelessWidget {
  final String reasonKey;
  final String? from;

  const BlockedScreen({super.key, required this.reasonKey, this.from});

  @override
  Widget build(BuildContext context) => SpacePlaceholder(
    title: 'NOT ON THIS DEVICE',
    caption: 'Honest capability surface',
    showBack: true,
    children: [
      Text(copyForReason(reasonKey), style: dbSans(15, 500, Db.chalk)),
      const SizedBox(height: 16),
      PlaceholderRow(label: 'reason', value: reasonKey),
      if (from != null) PlaceholderRow(label: 'tried', value: from!),
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton(
          onPressed: () => context.go('/vote'),
          child: const Text('SEE WHAT YOU CAN DO HERE'),
        ),
      ),
    ],
  );
}
