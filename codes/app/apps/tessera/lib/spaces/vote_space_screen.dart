// R3 replaces this file with the real VOTE space (voter home: needs-action /
// waiting / done, public directory as a secondary tab). The router does not
// change when it does — only this file.
import 'package:design_system/theme.dart';
import 'package:flutter/material.dart';

import 'space_placeholder.dart';

class VoteSpaceScreen extends StatelessWidget {
  const VoteSpaceScreen({super.key});

  @override
  Widget build(BuildContext context) => SpacePlaceholder(
    title: 'VOTE',
    caption: 'Voter home — R3 placeholder',
    children: [
      Text(
        'Polls that need your action, what you are waiting on, and your '
        'receipts land here in R3.',
        style: dbSans(13, 400, Db.chalkDim),
      ),
    ],
  );
}
