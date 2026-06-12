/// The JOIN surface (spec §4.1): the Kahoot-pattern universal entry.
///
/// Big three-way entry — SCAN (camera, capability-gated), PASTE (any
/// tessera:// or https invite link), TYPE CODE (`TES-XXXXXX`). All three
/// feed [parseJoinInput]; a recognized [JoinTarget] goes out through
/// [JoinSurface.onTarget] (the app maps it to a route with its single
/// `locationForJoinTarget` mapping), and an [UnknownTarget] becomes a
/// friendly INLINE error — never a navigation, never a crash.
library;

import 'package:design_system/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../join_grammar.dart';
import '../join_target.dart';
import 'qr_scan_sheet.dart';

/// Reads a scanned raw value (or `null` when the user bailed / no camera).
/// Injectable so widget tests never touch the camera plugin.
typedef ScanLauncher = Future<String?> Function(BuildContext context);

/// Reads the clipboard text (or `null`). Injectable for tests.
typedef ClipboardReader = Future<String?> Function();

Future<String?> _systemClipboardText() async =>
    (await Clipboard.getData(Clipboard.kTextPlain))?.text;

/// The friendly inline rejection for anything [parseJoinInput] cannot read.
const String kJoinUnrecognizedCopy =
    "That doesn't look like a Tessera invite. "
    'Check the link or code and try again.';

/// Shown when PASTE finds an empty clipboard.
const String kJoinEmptyClipboardCopy =
    'Nothing to paste — copy the invite link first, then try again.';

class JoinSurface extends StatefulWidget {
  /// Whether the SCAN entry is offered at all (from `Capabilities.canScanQr`
  /// — spec §4.3: no camera means JOIN leads with paste/code, not a dead
  /// camera tile).
  final bool canScanQr;

  /// Receives every successfully parsed target. [UnknownTarget] never
  /// arrives here — it is rendered inline.
  final ValueChanged<JoinTarget> onTarget;

  /// Test seam; defaults to the camera QR sheet.
  final ScanLauncher? scanQr;

  /// Test seam; defaults to the system clipboard.
  final ClipboardReader? readClipboard;

  const JoinSurface({
    super.key,
    required this.canScanQr,
    required this.onTarget,
    this.scanQr,
    this.readClipboard,
  });

  @override
  State<JoinSurface> createState() => _JoinSurfaceState();
}

class _JoinSurfaceState extends State<JoinSurface> {
  final TextEditingController _code = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  /// One funnel for all three entries: parse, route or complain inline.
  void _handleRaw(String raw) {
    final target = parseJoinInput(raw);
    if (target is UnknownTarget) {
      setState(() => _error = kJoinUnrecognizedCopy);
      return;
    }
    setState(() => _error = null);
    widget.onTarget(target);
  }

  Future<void> _scan() async {
    final scan = widget.scanQr ?? showJoinScanSheet;
    final raw = await scan(context);
    if (!mounted || raw == null || raw.trim().isEmpty) return;
    _handleRaw(raw);
  }

  Future<void> _paste() async {
    final read = widget.readClipboard ?? _systemClipboardText;
    final text = await read();
    if (!mounted) return;
    if (text == null || text.trim().isEmpty) {
      setState(() => _error = kJoinEmptyClipboardCopy);
      return;
    }
    _handleRaw(text);
  }

  CodeTarget? get _codeTarget => tryParseJoinCode('TES-${_code.text}');

  void _submitCode() {
    final target = _codeTarget;
    if (target == null) return; // button is disabled until the code is whole
    setState(() => _error = null);
    widget.onTarget(target);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[
          _InlineError(key: const Key('join-inline-error'), message: _error!),
          const SizedBox(height: 16),
        ],
        if (widget.canScanQr) ...[
          _EntryTile(
            key: const Key('join-scan-tile'),
            icon: Icons.qr_code_scanner,
            title: 'SCAN',
            subtitle: 'Point your camera at the invite QR',
            onTap: _scan,
          ),
          const SizedBox(height: 12),
        ],
        _EntryTile(
          key: const Key('join-paste-tile'),
          icon: Icons.content_paste,
          title: 'PASTE',
          subtitle: 'Use an invite link you copied',
          onTap: _paste,
        ),
        const SizedBox(height: 28),
        Text('OR TYPE A CODE', style: dbLabel()),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextField(
                key: const Key('join-code-field'),
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                enableSuggestions: false,
                style: dbMono(20, Db.chalk, wght: 600, letterSpacing: 4),
                inputFormatters: [JoinCodeInputFormatter()],
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submitCode(),
                decoration: InputDecoration(
                  prefixText: 'TES-',
                  prefixStyle: dbMono(20, Db.mute, wght: 600, letterSpacing: 4),
                  hintText: 'XXXXXX',
                  hintStyle: dbMono(20, Db.muteDim, letterSpacing: 4),
                  filled: true,
                  fillColor: Db.slate3,
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
            ),
            const SizedBox(width: 10),
            FilledButton(
              key: const Key('join-code-submit'),
              onPressed: _codeTarget == null ? null : _submitCode,
              style: FilledButton.styleFrom(
                backgroundColor: Db.segnale,
                disabledBackgroundColor: Db.slate4,
                foregroundColor: Db.void_,
                disabledForegroundColor: Db.mute,
                shape: const RoundedRectangleBorder(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 20,
                ),
              ),
              child: Text('JOIN', style: dbMono(13, Db.void_, wght: 700)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'The 6-character code under the QR on the organizer’s screen.',
          style: dbMono(11, Db.muteDim, height: 1.5),
        ),
      ],
    );
  }
}

/// Keeps the code field honest while staying forgiving:
/// - uppercases as you type;
/// - accepts only Crockford symbols plus the spoken-alias letters O/I/L
///   (the grammar folds them to 0/1 on parse), hard-capped at 6;
/// - a PASTE of a full canonical code (`TES-XXXXXX`, hyphen or not) drops
///   the prefix instead of jamming `TES` into the body. Single keystrokes
///   are never prefix-stripped — a body can legitimately start with `TES`.
class JoinCodeInputFormatter extends TextInputFormatter {
  static const String _allowed = '0123456789ABCDEFGHJKMNPQRSTVWXYZOIL';

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var text = newValue.text.toUpperCase();
    final pasted = text.length - oldValue.text.length > 1;
    if (pasted) {
      final compact = text.replaceAll(RegExp(r'[\s-]'), '');
      text = (compact.startsWith('TES') && compact.length > 6)
          ? compact.substring(3)
          : compact;
    }
    final buf = StringBuffer();
    for (final ch in text.split('')) {
      if (buf.length >= 6) break;
      if (_allowed.contains(ch)) buf.write(ch);
    }
    final out = buf.toString();
    return TextEditingValue(
      text: out,
      selection: TextSelection.collapsed(offset: out.length),
    );
  }
}

class _EntryTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _EntryTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Db.slate,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(border: Border.all(color: Db.rule)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Row(
            children: [
              Icon(icon, color: Db.segnale, size: 28),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: dbSans(17, 800, Db.chalk)),
                    const SizedBox(height: 3),
                    Text(subtitle, style: dbMono(11, Db.chalkDim)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Db.mute),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  final String message;

  const _InlineError({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Db.slate3,
        border: Border.all(color: Db.segnale),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        // Top-aligned: the copy wraps to two lines at phone widths, and the
        // icon should sit level with the first line, not float mid-block.
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Db.segnale, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: dbMono(12, Db.chalk, height: 1.45)),
          ),
        ],
      ),
    );
  }
}
