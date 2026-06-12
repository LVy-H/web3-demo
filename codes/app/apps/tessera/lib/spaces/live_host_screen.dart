// R3 replaces this file with the real live-host console (folded into the
// organizer dashboard's "run event" mode). The router does not change when
// it does — only this file.
import 'package:design_system/theme.dart';
import 'package:flutter/material.dart';

import 'space_placeholder.dart';

class LiveHostScreen extends StatelessWidget {
  final String address;

  const LiveHostScreen({super.key, required this.address});

  @override
  Widget build(BuildContext context) => SpacePlaceholder(
    title: 'RUN EVENT',
    caption: 'Live host console — R3 placeholder',
    showBack: true,
    children: [
      PlaceholderRow(label: 'session', value: address),
      const SizedBox(height: 12),
      Text(
        'Admitting voters, opening and closing the vote land here in R3, '
        'driven by the liveHost journey machine.',
        style: dbSans(13, 400, Db.chalkDim),
      ),
    ],
  );
}
