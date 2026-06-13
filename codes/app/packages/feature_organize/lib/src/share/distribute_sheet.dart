/// The DISTRIBUTE share sheet (spec §4.2: created → distribute via
/// QR / link / NFC). QR and copy-link are always available — displaying a
/// QR needs no hardware; the NFC tile appears only when the organizer
/// device actually has the radio (spec §4.3: "no NFC → share sheet drops
/// NFC tile").
library;

import 'package:design_system/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../qr/qr_view.dart';
import 'share_link.dart';

export 'share_link.dart' show ShareLinkFn;

class DistributeSheet extends StatelessWidget {
  static const Key qrKey = Key('distribute-qr');
  static const Key copyLinkKey = Key('distribute-copy-link');
  static const Key shareKey = Key('distribute-share');
  static const Key nfcTileKey = Key('distribute-nfc');

  /// The canonical poll deep link (feature_join's `shareLinkForPoll` — the
  /// JOIN grammar reads it back to the same poll).
  final String shareLink;

  final bool nfcAvailable;

  /// The OS share-sheet action, injected for tests. Defaults to the real
  /// share_plus call ([shareTextViaOs]).
  final ShareLinkFn onShare;

  const DistributeSheet({
    super.key,
    required this.shareLink,
    required this.nfcAvailable,
    ShareLinkFn? onShare,
  }) : onShare = onShare ?? shareTextViaOs;

  /// Standard entry point: present as a modal bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required String shareLink,
    required bool nfcAvailable,
    ShareLinkFn? onShare,
  }) => showModalBottomSheet<void>(
    context: context,
    backgroundColor: Db.slate,
    shape: const RoundedRectangleBorder(),
    isScrollControlled: true,
    builder: (context) => DistributeSheet(
      shareLink: shareLink,
      nfcAvailable: nfcAvailable,
      onShare: onShare,
    ),
  );

  /// Honest share text: a short human line + the same deep link COPY
  /// produces. The link opens Tessera for recipients who have the app — no
  /// claim it works for people without it.
  String get _shareText => 'Join my poll on Tessera:\n$shareLink';

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SHARE THIS POLL', style: dbSectionTitle),
          const SizedBox(height: 6),
          Text(
            'Anyone with this QR or link can open the poll. It stays out '
            'of the public directory unless you listed it.',
            style: dbSans(12, 400, Db.chalkDim, height: 1.5),
          ),
          const SizedBox(height: 20),
          Center(
            child: QrView(key: qrKey, data: shareLink, dimension: 220),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Db.slate3,
              border: Border.all(color: Db.rule),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    shareLink,
                    style: dbMono(11, Db.chalkDim),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  key: copyLinkKey,
                  onPressed: () => _copy(context),
                  child: Text('COPY LINK', style: dbMono(11, Db.chalk)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Native OS share of the same deep link COPY produces — a
          // convenience over copy, not a new capability.
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: shareKey,
              onPressed: () => onShare(_shareText),
              icon: const Icon(Icons.ios_share, size: 16, color: Db.chalk),
              label: Text('SHARE', style: dbMono(11, Db.chalk)),
            ),
          ),
          if (nfcAvailable) ...[
            const SizedBox(height: 12),
            Container(
              key: nfcTileKey,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Db.slate3,
                border: Border.all(color: Db.rule),
              ),
              child: Row(
                children: [
                  const Icon(Icons.nfc, size: 18, color: Db.chalkDim),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'NFC — hold the voter’s phone to the back of this '
                      'one while this sheet is open.',
                      style: dbSans(12, 400, Db.chalkDim),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    ),
  );

  Future<void> _copy(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    await Clipboard.setData(ClipboardData(text: shareLink));
    messenger?.showSnackBar(
      SnackBar(
        backgroundColor: Db.slate2,
        content: Text('Link copied', style: dbSans(13, 500, Db.chalk)),
      ),
    );
  }
}
