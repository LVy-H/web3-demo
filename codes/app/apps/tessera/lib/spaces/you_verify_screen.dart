// R3 replaces this file with the real verify surface (receipt checks,
// contextual after-cast verification). The router does not change when it
// does — only this file.
import 'package:design_system/theme.dart';
import 'package:flutter/material.dart';

import 'space_placeholder.dart';

class YouVerifyScreen extends StatelessWidget {
  final String? poll;
  final String? nullifier;

  const YouVerifyScreen({super.key, this.poll, this.nullifier});

  @override
  Widget build(BuildContext context) => SpacePlaceholder(
    title: 'VERIFY',
    caption: 'Check a receipt — R3 placeholder',
    showBack: true,
    children: [
      PlaceholderRow(label: 'poll', value: poll ?? '(prompted in R3)'),
      PlaceholderRow(label: 'receipt', value: nullifier ?? '(prompted in R3)'),
      const SizedBox(height: 12),
      Text(
        'Receipt verification lands here in R3.',
        style: dbSans(13, 400, Db.chalkDim),
      ),
    ],
  );
}
