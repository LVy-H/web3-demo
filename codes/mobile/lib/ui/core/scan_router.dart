import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/live_vote/qr_scan_sheet.dart';
import 'theme.dart';

/// Map a scanned / pasted Tessera deep-link to an in-app [GoRouter] location.
///
/// Pure and total: returns the route string for a recognized payload, or `null`
/// for anything it can't route (so the caller shows "unrecognized" feedback).
/// Recognizes the `tessera://` custom scheme the app's QR codes encode — the
/// live-meeting host ticket is `tessera://live/<addr>/vote?t=<wire>` (see
/// `live_host_view_model.dart`) — and also tolerates `http(s)` links that mirror
/// the same path structure (forward-compatible with future web shares).
///
/// This is the unit-tested half of the scanner; the camera decode itself is the
/// device-fenced half (see [cameraScanSupported]).
String? routeForScannedValue(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  final uri = Uri.tryParse(s);
  if (uri == null) return null;
  if (uri.scheme != 'tessera' &&
      uri.scheme != 'https' &&
      uri.scheme != 'http') {
    return null;
  }
  // For the custom `tessera://<seg0>/<seg1>/…` scheme, Dart parses <seg0> as the
  // authority/host; for http(s) the logical segments are just the path. Flatten
  // both into one ordered list of non-empty segments.
  final segs = <String>[
    if (uri.scheme == 'tessera' && uri.host.isNotEmpty) uri.host,
    ...uri.pathSegments,
  ].where((e) => e.isNotEmpty).toList();
  if (segs.isEmpty) return null;
  final query = uri.hasQuery ? '?${uri.query}' : '';

  if (segs.length >= 3 && segs[0] == 'live' && segs[2] == 'vote') {
    return '/live/${segs[1]}/vote$query';
  }
  if (segs.length >= 3 && segs[0] == 'live' && segs[2] == 'host') {
    return '/live/${segs[1]}/host';
  }
  if (segs[0] == 'verify') {
    return '/verify$query';
  }
  if (segs.length >= 2 && segs[0] == 'poll') {
    return '/poll/${segs[1]}$query';
  }
  return null;
}

/// Build the canonical Tessera deep-link for a poll — the inverse of
/// [routeForScannedValue]. The link encodes into a QR (see `share_poll_sheet`)
/// that the existing scanner reads back to the same poll-detail location:
/// `routeForScannedValue(shareLinkForPoll(a, module: m)) == '/poll/$a?module=$m'`.
/// Keeping the writer next to the reader makes that round-trip invariant local.
String shareLinkForPoll(String address, {String? module}) {
  final q = (module != null && module.isNotEmpty) ? '?module=$module' : '';
  return 'tessera://poll/$address$q';
}

/// Open the QR scanner (camera on mobile) or a paste dialog, then route the
/// result. Wired to the navbar SCAN action. Camera unsupported → straight to
/// paste; camera dismissed → cancel; "paste instead" inside the sheet → paste.
///
/// The `GoRouter` and `ScaffoldMessenger` are looked up *before* any `await`:
/// after a sheet/dialog closes, the passed `context` may be mid-teardown and an
/// inherited lookup on it can trip a framework assertion.
Future<void> scanAndRoute(BuildContext context) async {
  final router = GoRouter.of(context);
  final messenger = ScaffoldMessenger.of(context);

  String? raw;
  if (cameraScanSupported) {
    raw = await showQrScanSheet(
      context,
      title: 'SCAN QR',
      hint:
          "Point the camera at a Tessera QR — a live-meeting ticket, a poll, "
          "or a verification link. Can't scan? Paste a link instead.",
      showPasteAction: true,
    );
    if (raw == null) return; // dismissed
    if (raw == kQrScanPaste) {
      if (!context.mounted) return;
      raw = await showPasteLinkDialog(context);
    }
  } else {
    raw = await showPasteLinkDialog(context);
  }
  if (raw == null || raw == kQrScanPaste) return; // cancelled

  final route = routeForScannedValue(raw);
  if (route != null) {
    router.go(route);
  } else {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: Db.slate,
          behavior: SnackBarBehavior.floating,
          content: Text(
            "Couldn't read that as a Tessera link.",
            style: dbMono(12, Db.chalk),
          ),
        ),
      );
  }
}

/// A themed paste-a-link dialog — the always-reachable fallback for when the
/// camera is unavailable / denied, or the user prefers typing. Returns the
/// trimmed input, or `null` if cancelled.
Future<String?> showPasteLinkDialog(BuildContext context) => showDialog<String>(
  context: context,
  builder: (_) => const _PasteLinkDialog(),
);

class _PasteLinkDialog extends StatefulWidget {
  const _PasteLinkDialog();
  @override
  State<_PasteLinkDialog> createState() => _PasteLinkDialogState();
}

class _PasteLinkDialogState extends State<_PasteLinkDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose(); // safe: runs after this State unmounts
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: Db.slate,
    shape: const RoundedRectangleBorder(side: BorderSide(color: Db.rule)),
    title: Text('PASTE A LINK', style: dbLabel(size: 12, tracking: 0.16)),
    content: TextField(
      controller: _controller,
      autofocus: true,
      style: dbMono(13, Db.chalk),
      cursorColor: Db.segnale,
      decoration: InputDecoration(
        hintText: 'tessera://…',
        hintStyle: dbMono(13, Db.muteDim),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Db.rule),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Db.segnale),
        ),
      ),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text('CANCEL', style: dbLabel(size: 11, color: Db.mute)),
      ),
      TextButton(
        onPressed: _submit,
        child: Text('GO', style: dbLabel(size: 11, color: Db.segnale)),
      ),
    ],
  );
}
