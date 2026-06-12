import 'package:flutter/foundation.dart';

/// On-chain receipt check: is this receipt code recorded as used in the
/// poll? Production injects `ChainReader.isNullifierUsed` (the same public
/// participation check the legacy verify flow and the web Verify page use).
typedef ReceiptCheck =
    Future<bool> Function(String pollAddress, String receiptCode);

/// Resolve a poll address to its title for the result copy ("This receipt
/// is counted in `<poll title>`"). May return `null` (unknown poll) and may
/// throw — failures only cost the title, never the verdict.
typedef PollTitleLookup = Future<String?> Function(String pollAddress);

enum VerifyVerdict { idle, checking, counted, notFound, error }

/// State for the Verify surface. Read-only by design — it works WITHOUT a
/// voting pass (anyone holding a receipt can check it). Inputs are validated
/// locally before any chain call, with jargon-free messages.
class VerifyController extends ChangeNotifier {
  final ReceiptCheck _checkReceipt;
  final PollTitleLookup? _lookupPollTitle;

  VerifyController({
    required ReceiptCheck checkReceipt,
    PollTitleLookup? lookupPollTitle,
  }) : _checkReceipt = checkReceipt,
       _lookupPollTitle = lookupPollTitle;

  static final _addressPattern = RegExp(r'^0x[0-9a-fA-F]{40}$');
  static final _codePattern = RegExp(r'^[0-9]+$');

  VerifyVerdict verdict = VerifyVerdict.idle;
  String? error;

  /// The verified poll's title, when the lookup knew it.
  String? pollTitle;

  bool _disposed = false;
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> verify(String pollAddress, String receiptCode) async {
    final poll = pollAddress.trim();
    final code = receiptCode.trim();
    pollTitle = null;
    if (!_addressPattern.hasMatch(poll)) {
      error =
          'That doesn’t look like a poll address — expected 0x followed by '
          '40 characters.';
      verdict = VerifyVerdict.error;
      _notify();
      return;
    }
    if (!_codePattern.hasMatch(code)) {
      error =
          'That doesn’t look like a receipt code — it’s the long number on '
          'your receipt.';
      verdict = VerifyVerdict.error;
      _notify();
      return;
    }
    verdict = VerifyVerdict.checking;
    error = null;
    _notify();
    try {
      final counted = await _checkReceipt(poll, code);
      if (counted) {
        // Best-effort title for friendlier copy; never fails the verdict.
        try {
          pollTitle = await _lookupPollTitle?.call(poll);
        } catch (_) {
          pollTitle = null;
        }
      }
      verdict = counted ? VerifyVerdict.counted : VerifyVerdict.notFound;
    } catch (e) {
      error = 'Couldn’t reach the network to check: $e';
      verdict = VerifyVerdict.error;
    }
    _notify();
  }
}
