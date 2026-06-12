// R3 refines the copy here; the screen itself — the typed catch-all error
// route the legacy router never had — is structural and stays.
import 'package:design_system/theme.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'space_placeholder.dart';

/// Message key for locations no route matches (go_router errorBuilder).
const String kRouteNotFoundKey = 'error.route.notFound';

class RouteErrorScreen extends StatelessWidget {
  final String messageKey;
  final String? detail;

  const RouteErrorScreen({super.key, required this.messageKey, this.detail});

  @override
  Widget build(BuildContext context) => SpacePlaceholder(
    title: 'NOTHING HERE',
    caption: messageKey,
    showBack: true,
    children: [
      Text(switch (messageKey) {
        kRouteNotFoundKey =>
          'That link does not lead anywhere in Tessera. It may be old, '
              'mistyped, or from a newer version.',
        'error.join.unrecognized' =>
          'That QR code, link, or code is not something Tessera '
              'recognizes.',
        _ => 'Something went wrong with that link.',
      }, style: dbSans(15, 500, Db.chalk)),
      const SizedBox(height: 16),
      if (detail != null) PlaceholderRow(label: 'detail', value: detail!),
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton(
          onPressed: () => context.go('/vote'),
          child: const Text('BACK TO VOTE'),
        ),
      ),
    ],
  );
}
