// Short-code landing (R3). The server-side code → poll-address resolver
// (spec §8 open question 2) has NOT shipped, so this screen is honest about
// it (feature_join's JoinCodeNotice) instead of faking a lookup. When the
// resolver lands, only this file changes — the route and the CodeTarget →
// /join/resolve mapping already carry the canonical code.
import 'package:design_system/dot_grid_background.dart';
import 'package:design_system/theme.dart';
import 'package:feature_join/ui.dart';
import 'package:flutter/material.dart';

class JoinResolveScreen extends StatelessWidget {
  final String? code;

  const JoinResolveScreen({super.key, this.code});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent),
      body: DotGridBackground(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                Text('JOIN CODE', style: dbSans(34, 800, Db.chalk)),
                const SizedBox(height: 24),
                JoinCodeNotice(code: code),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
