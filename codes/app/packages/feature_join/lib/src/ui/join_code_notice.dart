/// Honest copy for a typed short code while the server-side resolver
/// (spec §8 open question 2 — relayer-hosted code→address table) has not
/// shipped: the code is real, the lookup is not live yet. No fake spinner,
/// no dead end — the user is told exactly what works instead.
library;

import 'package:design_system/theme.dart';
import 'package:flutter/material.dart';

class JoinCodeNotice extends StatelessWidget {
  /// The canonical code (`TES-XXXXXX`) the user typed, if any.
  final String? code;

  const JoinCodeNotice({super.key, this.code});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (code != null) ...[
          Text('YOUR CODE', style: dbLabel()),
          const SizedBox(height: 6),
          Text(
            code!,
            key: const Key('join-code-notice-code'),
            style: dbMono(28, Db.chalk, wght: 700, letterSpacing: 6),
          ),
          const SizedBox(height: 20),
        ],
        Container(
          decoration: BoxDecoration(
            color: Db.slate3,
            border: Border.all(color: Db.amber),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('CODES AREN’T LIVE YET', style: dbLabel(color: Db.amber)),
              const SizedBox(height: 10),
              Text(
                'Joining by short code is coming, but it doesn’t work yet. '
                'Ask the organizer for the QR or the invite link instead — '
                'both work today.',
                style: dbMono(12, Db.chalk, height: 1.55),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
