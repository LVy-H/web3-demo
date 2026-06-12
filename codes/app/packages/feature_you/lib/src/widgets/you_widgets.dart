/// Small Dark Bauhaus building blocks shared by the YOU surfaces. Kept
/// package-internal (not exported) — design_system stays the cross-feature
/// source of truth; these are just feature_you's local compositions of it.
library;

import 'package:design_system/theme.dart';
import 'package:flutter/material.dart';

/// Wide-tracked section label ("VOTING PASS", "RECEIPTS", "SETTINGS").
class YouSectionLabel extends StatelessWidget {
  final String text;
  const YouSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) =>
      Text(text, style: dbLabel(size: 10, tracking: 0.16));
}

/// Slate panel with a colored left accent (the Bauhaus status panel).
class YouAccentPanel extends StatelessWidget {
  final Color accent;
  final Widget child;
  const YouAccentPanel({super.key, required this.accent, required this.child});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Db.slate,
      border: Border(left: BorderSide(color: accent, width: 3)),
    ),
    child: child,
  );
}

/// Bordered slate3 panel (seed/code reveal panels).
class YouFramedPanel extends StatelessWidget {
  final Widget child;
  const YouFramedPanel({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: const BoxDecoration(
      color: Db.slate3,
      border: Border.fromBorderSide(BorderSide(color: Db.rule)),
    ),
    child: child,
  );
}

/// Full-width signal-red primary action.
class YouPrimaryButton extends StatelessWidget {
  final String label;
  final bool busy;
  final VoidCallback? onTap;
  const YouPrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: FilledButton(
      onPressed: busy ? null : onTap,
      style: FilledButton.styleFrom(
        backgroundColor: Db.segnale,
        disabledBackgroundColor: Db.slate,
        foregroundColor: Db.chalk,
        shape: const RoundedRectangleBorder(),
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
      child: Text(label, style: dbSans(13, 800, Db.chalk, letterSpacing: 1.4)),
    ),
  );
}

/// Full-width hairline-outlined secondary action.
class YouOutlineButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback? onTap;
  const YouOutlineButton({
    super.key,
    required this.label,
    required this.onTap,
    this.color = Db.chalk,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: const BorderSide(color: Db.rule),
        shape: const RoundedRectangleBorder(),
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      child: Text(
        label,
        style: dbLabel(size: 11, color: color, tracking: 0.16),
      ),
    ),
  );
}

/// Compact icon+label chip button (REVEAL / COPY / HIDE).
class YouMiniButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const YouMiniButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Db.void_,
        border: Border.fromBorderSide(BorderSide(color: Db.rule)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Db.chalkDim),
          const SizedBox(width: 7),
          Text(label, style: dbLabel(size: 10, color: Db.chalkDim)),
        ],
      ),
    ),
  );
}

/// Label-over-input text field in the Bauhaus mono style.
class YouTextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  const YouTextField({
    super.key,
    required this.label,
    required this.controller,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      YouSectionLabel(label),
      const SizedBox(height: 8),
      TextField(
        controller: controller,
        style: dbMono(13, Db.chalk),
        cursorColor: Db.segnale,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: Db.void_,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          hintText: hint,
          hintStyle: dbMono(12, Db.mute),
          enabledBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: Db.rule),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: Db.segnale),
          ),
        ),
      ),
    ],
  );
}

/// Static label/value row inside a settings panel.
class YouInfoRow extends StatelessWidget {
  final String label;
  final String value;
  const YouInfoRow({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    // Both sides Flexible + ellipsis so an enlarged font scale can't push
    // the row past the edge (lifted from the legacy settings screen).
    child: Row(
      children: [
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: dbSans(13, 600, Db.chalkDim),
          ),
        ),
        const SizedBox(width: 12),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: dbMono(12, Db.chalk),
          ),
        ),
      ],
    ),
  );
}

/// Tappable row with a trailing arrow (settings navigation).
class YouLinkRow extends StatelessWidget {
  final String label;
  final String? detail;
  final VoidCallback onTap;
  const YouLinkRow({
    super.key,
    required this.label,
    required this.onTap,
    this.detail,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: dbSans(13, 600, Db.chalk),
            ),
          ),
          if (detail != null) ...[
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                detail!,
                overflow: TextOverflow.ellipsis,
                style: dbMono(11, Db.mute),
              ),
            ),
          ],
          const SizedBox(width: 12),
          const Icon(Icons.arrow_forward, size: 14, color: Db.segnale),
        ],
      ),
    ),
  );
}

/// Bordered container for a column of settings rows.
class YouRowsPanel extends StatelessWidget {
  final List<Widget> rows;
  const YouRowsPanel({super.key, required this.rows});

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: Db.slate,
      border: Border.fromBorderSide(BorderSide(color: Db.rule)),
    ),
    child: Column(children: rows),
  );
}

/// Hairline expander header (IMPORT / ADVANCED toggles).
class YouExpanderHeader extends StatelessWidget {
  final String label;
  final bool open;
  final VoidCallback onTap;
  const YouExpanderHeader({
    super.key,
    required this.label,
    required this.open,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(
            open ? Icons.expand_less : Icons.expand_more,
            size: 16,
            color: Db.mute,
          ),
          const SizedBox(width: 8),
          Text(label, style: dbLabel(size: 10, tracking: 0.16)),
        ],
      ),
    ),
  );
}

void showYouSnack(BuildContext context, String message) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: dbMono(12, Db.chalk)),
        backgroundColor: Db.slate,
      ),
    );
