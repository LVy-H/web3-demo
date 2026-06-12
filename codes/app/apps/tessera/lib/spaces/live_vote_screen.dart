// R3 replaces this file with the real live-voter flow (scanned → pending →
// admitted → ballot → done, driven by the liveVoter journey machine). The
// router — including the canProve guard in routing/guards.dart that protects
// this route — does not change when it does; only this file.
import 'package:design_system/theme.dart';
import 'package:flutter/material.dart';

import 'space_placeholder.dart';

class LiveVoteScreen extends StatelessWidget {
  final String address;
  final String? ticket;

  const LiveVoteScreen({super.key, required this.address, this.ticket});

  @override
  Widget build(BuildContext context) => SpacePlaceholder(
    title: 'LIVE VOTE',
    caption: 'Live voter — R3 placeholder',
    showBack: true,
    children: [
      PlaceholderRow(label: 'session', value: address),
      PlaceholderRow(
        label: 'ticket',
        value: ticket ?? '(none — join in-session)',
      ),
      const SizedBox(height: 12),
      Text(
        'The live ballot lands here in R3. This route is only reachable on '
        'devices that can prove — the router guard already enforces that.',
        style: dbSans(13, 400, Db.chalkDim),
      ),
    ],
  );
}
