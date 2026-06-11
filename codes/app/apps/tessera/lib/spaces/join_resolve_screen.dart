// R3 replaces this file with the real short-code resolver (code → poll
// address via the relayer-hosted table, spec §8 open question 2). The router
// does not change when it does — only this file.
import 'package:design_system/theme.dart';
import 'package:flutter/material.dart';

import 'space_placeholder.dart';

class JoinResolveScreen extends StatelessWidget {
  final String? code;

  const JoinResolveScreen({super.key, this.code});

  @override
  Widget build(BuildContext context) => SpacePlaceholder(
    title: 'JOIN CODE',
    caption: 'Code resolution — R3 placeholder',
    showBack: true,
    children: [
      PlaceholderRow(label: 'code', value: code ?? '(none)'),
      const SizedBox(height: 12),
      Text(
        'Resolving a short code to its poll lands here in R3.',
        style: dbSans(13, 400, Db.chalkDim),
      ),
    ],
  );
}
