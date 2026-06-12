/// Shared scaffold for the R2f placeholder screens. Lives in spaces/ with
/// them; R3 deletes it together with the last placeholder.
library;

import 'package:design_system/dot_grid_background.dart';
import 'package:design_system/theme.dart';
import 'package:flutter/material.dart';

class SpacePlaceholder extends StatelessWidget {
  final String title;
  final String caption;
  final List<Widget> children;
  final bool showBack;

  const SpacePlaceholder({
    super.key,
    required this.title,
    required this.caption,
    this.children = const [],
    this.showBack = false,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: showBack ? AppBar(backgroundColor: Colors.transparent) : null,
    body: DotGridBackground(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Text(title, style: dbSans(34, 800, Db.chalk)),
              const SizedBox(height: 4),
              Text(caption.toUpperCase(), style: dbMono(11, Db.segnale)),
              const SizedBox(height: 24),
              ...children,
            ],
          ),
        ),
      ),
    ),
  );
}

/// A keyed info row in the Dark Bauhaus mono style.
class PlaceholderRow extends StatelessWidget {
  final String label;
  final String value;

  const PlaceholderRow({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 130, child: Text(label, style: dbMono(12, Db.mute))),
        Expanded(child: Text(value, style: dbMono(12, Db.chalk))),
      ],
    ),
  );
}
