// R3 replaces this file with the real JOIN surface (camera QR / paste link /
// type code — the Kahoot-pattern universal entry). The router does not
// change when it does — only this file. The typed grammar (feature_join) and
// the JoinTarget → location mapping (routing/join_routing.dart) are already
// final.
import 'package:design_system/theme.dart';
import 'package:flutter/material.dart';

import 'space_placeholder.dart';

class JoinScreen extends StatelessWidget {
  const JoinScreen({super.key});

  @override
  Widget build(BuildContext context) => SpacePlaceholder(
    title: 'JOIN',
    caption: 'Universal entry — R3 placeholder',
    showBack: true,
    children: [
      Text(
        'Scan a QR, paste a link, or type a TES- code. The real surface '
        'lands in R3; parsed targets already route through '
        'locationForJoinTarget().',
        style: dbSans(13, 400, Db.chalkDim),
      ),
    ],
  );
}
