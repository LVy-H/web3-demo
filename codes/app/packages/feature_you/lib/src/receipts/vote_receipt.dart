import 'dart:convert';

/// A saved vote receipt — the proof-of-participation a voter keeps after
/// casting. Jargon note: [receiptCode] is the on-chain nullifier (a decimal
/// string), but the UI only ever calls it "receipt code" (spec §3 principle 5).
class VoteReceipt {
  final String pollAddress;
  final String pollTitle;
  final String receiptCode;
  final DateTime savedAt;

  const VoteReceipt({
    required this.pollAddress,
    required this.pollTitle,
    required this.receiptCode,
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
    'poll': pollAddress,
    'title': pollTitle,
    'code': receiptCode,
    'savedAt': savedAt.millisecondsSinceEpoch,
  };

  /// Tolerant decode: returns `null` for anything malformed instead of
  /// throwing, so one bad entry never takes the whole archive down.
  static VoteReceipt? tryFromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final poll = raw['poll'];
    final code = raw['code'];
    if (poll is! String || poll.isEmpty || code is! String || code.isEmpty) {
      return null;
    }
    final title = raw['title'];
    final savedAt = raw['savedAt'];
    return VoteReceipt(
      pollAddress: poll,
      pollTitle: title is String ? title : '',
      receiptCode: code,
      savedAt: savedAt is int
          ? DateTime.fromMillisecondsSinceEpoch(savedAt)
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  /// Encode a list for storage as a single JSON blob.
  static String encodeList(List<VoteReceipt> receipts) =>
      jsonEncode(receipts.map((r) => r.toJson()).toList());

  /// Decode a stored blob. A null/corrupt blob decodes to an empty list —
  /// the archive degrades to "no receipts", it never bricks the screen.
  static List<VoteReceipt> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .map(VoteReceipt.tryFromJson)
          .whereType<VoteReceipt>()
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
