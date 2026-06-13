import 'package:design_system/format.dart';
import 'package:design_system/theme.dart';
import 'package:flutter/material.dart';

import '../widgets/you_widgets.dart';
import 'receipts_store.dart';
import 'vote_receipt.dart';

/// The receipts archive (spec §4.1 "You"): every receipt the voter saved,
/// each opening Verify pre-filled. Verification is also reachable here for
/// people who were handed someone else's receipt — no pass required.
class ReceiptsSection extends StatefulWidget {
  final ReceiptsStore store;

  /// Open the Verify surface. Both arguments `null` for a blank check;
  /// otherwise pre-filled from the tapped receipt.
  final void Function(String? pollAddress, String? receiptCode) onOpenVerify;

  const ReceiptsSection({
    super.key,
    required this.store,
    required this.onOpenVerify,
  });

  @override
  State<ReceiptsSection> createState() => _ReceiptsSectionState();
}

class _ReceiptsSectionState extends State<ReceiptsSection> {
  List<VoteReceipt>? _receipts; // null while loading
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loadFailed) setState(() => _loadFailed = false);
    try {
      final loaded = await widget.store.loadAll();
      if (mounted) setState(() => _receipts = loaded);
    } catch (_) {
      // The receipts archive is how a voter checks their vote was counted —
      // a failed load must read as an honest, retryable error, never a false
      // "no receipts yet" (which would tell them their proof vanished).
      if (mounted) {
        setState(() {
          _receipts = null;
          _loadFailed = true;
        });
      }
    }
  }

  static String _date(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

  static String _shortCode(String code) => code.length <= 10
      ? code
      : '${code.substring(0, 6)}…${code.substring(code.length - 4)}';

  @override
  Widget build(BuildContext context) {
    final receipts = _receipts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const YouSectionLabel('RECEIPTS'),
        const SizedBox(height: 8),
        if (_loadFailed)
          _errorPanel()
        else if (receipts == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Db.segnale,
                ),
              ),
            ),
          )
        else if (receipts.isEmpty)
          YouFramedPanel(
            child: Text(
              'No receipts yet. When you vote, your receipt is saved here so '
              'you can always check it was counted.',
              style: dbSans(13, 400, Db.chalkDim, height: 1.5),
            ),
          )
        else
          Container(
            decoration: const BoxDecoration(
              color: Db.slate,
              border: Border.fromBorderSide(BorderSide(color: Db.rule)),
            ),
            child: Column(
              children: [
                for (var i = 0; i < receipts.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, thickness: 1, color: Db.ruleSoft),
                  _receiptTile(receipts[i]),
                ],
              ],
            ),
          ),
        const SizedBox(height: 12),
        YouOutlineButton(
          label: 'CHECK A RECEIPT',
          onTap: () => widget.onOpenVerify(null, null),
        ),
      ],
    );
  }

  Widget _errorPanel() => YouAccentPanel(
    accent: Db.amber,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Couldn’t load your receipts on this device. Your saved receipts '
          'aren’t lost — this is just a problem reading them right now.',
          style: dbSans(13, 400, Db.chalkDim, height: 1.5),
        ),
        const SizedBox(height: 12),
        YouOutlineButton(label: 'TRY AGAIN', color: Db.amber, onTap: _load),
      ],
    ),
  );

  Widget _receiptTile(VoteReceipt r) => InkWell(
    onTap: () => widget.onOpenVerify(r.pollAddress, r.receiptCode),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          const Icon(Icons.receipt_long_outlined, size: 16, color: Db.mute),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.pollTitle.isNotEmpty
                      ? r.pollTitle
                      : shortAddr(r.pollAddress),
                  overflow: TextOverflow.ellipsis,
                  style: dbSans(13, 600, Db.chalk),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_date(r.savedAt)} · code ${_shortCode(r.receiptCode)}',
                  overflow: TextOverflow.ellipsis,
                  style: dbMono(11, Db.mute),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const Icon(Icons.arrow_forward, size: 14, color: Db.segnale),
        ],
      ),
    ),
  );
}
