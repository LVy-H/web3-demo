import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../data/services/nfc_service.dart';
import 'scan_router.dart';
import 'theme.dart';

/// Show a themed bottom sheet with a scannable QR + copyable deep-link for a
/// poll. The QR encodes [shareLinkForPoll], which the navbar SCAN action reads
/// back to this same poll — closing the scan loop. Reusable from any screen.
Future<void> showSharePollSheet(
  BuildContext context, {
  required String address,
  String? module,
  String? title,
}) {
  final link = shareLinkForPoll(address, module: module);
  final nfc = context.read<NfcService>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Db.void_,
    builder: (_) => _SharePollSheet(link: link, title: title, nfc: nfc),
  );
}

class _SharePollSheet extends StatefulWidget {
  final String link;
  final String? title;
  final NfcService nfc;
  const _SharePollSheet({required this.link, this.title, required this.nfc});

  @override
  State<_SharePollSheet> createState() => _SharePollSheetState();
}

class _SharePollSheetState extends State<_SharePollSheet> {
  bool _copied = false;
  bool _nfcAvailable = false; // probed on open; gates the NFC affordance
  bool _nfcWriting = false;
  String? _nfcMsg;

  @override
  void initState() {
    super.initState();
    widget.nfc.isAvailable().then((ok) {
      if (mounted) setState(() => _nfcAvailable = ok);
    });
  }

  @override
  void dispose() {
    widget.nfc.cancel(); // close any in-flight tag session
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.link));
    if (!mounted) return; // guard the post-await setState
    setState(() => _copied = true);
  }

  Future<void> _writeNfc() async {
    setState(() {
      _nfcWriting = true;
      _nfcMsg = 'Hold a writable NFC tag to the back of the phone…';
    });
    final r = await widget.nfc.writeUrl(widget.link);
    if (!mounted) return;
    setState(() {
      _nfcWriting = false;
      _nfcMsg = r.ok
          ? 'Written to tag ✓ — anyone can tap it to open this poll.'
          : (r.error ?? 'Could not write the tag.');
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text('SHARE POLL', style: dbLabel(size: 12, tracking: 0.16)),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Db.mute, size: 20),
                    splashRadius: 18,
                  ),
                ],
              ),
              if (widget.title != null && widget.title!.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  widget.title!,
                  style: dbMono(12, Db.mute),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 16),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  color: Colors.white,
                  child: QrImageView(
                    data: widget.link,
                    version: QrVersions.auto,
                    size: 220,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('LINK', style: dbLabel(size: 9)),
              const SizedBox(height: 4),
              SelectableText(widget.link, style: dbMono(12, Db.chalk)),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _copy,
                icon: Icon(
                  _copied ? Icons.check : Icons.copy,
                  size: 16,
                  color: _copied ? Db.segnale : Db.chalk,
                ),
                label: Text(
                  _copied ? 'COPIED' : 'COPY LINK',
                  style: dbLabel(
                    size: 11,
                    color: _copied ? Db.segnale : Db.chalk,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Db.rule),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              // NFC: write the same poll link to a tag (Android, where the radio
              // is present). Hidden where there's no NFC — the QR is the baseline.
              if (_nfcAvailable) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _nfcWriting ? null : _writeNfc,
                  icon: const Icon(Icons.nfc, size: 16, color: Db.chalk),
                  label: Text(
                    _nfcWriting ? 'TAP A TAG…' : 'WRITE TO NFC TAG',
                    style: dbLabel(size: 11, color: Db.chalk),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Db.rule),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                if (_nfcMsg != null) ...[
                  const SizedBox(height: 6),
                  Text(_nfcMsg!, style: dbMono(11, Db.muteDim, height: 1.4)),
                ],
              ],
              const SizedBox(height: 8),
              Text(
                'Scan this with the Tessera app (SCAN tab) to open the poll.',
                style: dbMono(11, Db.muteDim, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
