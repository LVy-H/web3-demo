// R3 replaces this file with the real ORGANIZE space (dashboard of the polls
// you run: phase, turnout, next action; CREATE lives here). The router does
// not change when it does — only this file.
import 'package:design_system/theme.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'space_placeholder.dart';

class OrganizeSpaceScreen extends StatelessWidget {
  const OrganizeSpaceScreen({super.key});

  @override
  Widget build(BuildContext context) => SpacePlaceholder(
    title: 'ORGANIZE',
    caption: 'Organizer home — R3 placeholder',
    children: [
      Text(
        'Your polls and events, each with a dashboard card, land here in R3.',
        style: dbSans(13, 400, Db.chalkDim),
      ),
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton(
          onPressed: () => context.go('/organize/create'),
          child: const Text('CREATE'),
        ),
      ),
    ],
  );
}
