/// A voter waiting in the organizer's confirmation queue.
///
/// Mirrors the `PendingVoter` shape returned by the relayer's
/// `GET /api/relay/tickets/queue` (see codes/relayer/src/tickets.ts and
/// codes/frontend/src/lib/liveRelay.ts).
class PendingVoter {
  final String ticketNonce;
  final String ticket;
  final String ephemeralIdentityCommitment;
  final String confirmationCode;

  /// 'pending' | 'confirmed' | 'rejected'
  final String status;
  final int createdAt;

  const PendingVoter({
    required this.ticketNonce,
    required this.ticket,
    required this.ephemeralIdentityCommitment,
    required this.confirmationCode,
    required this.status,
    required this.createdAt,
  });

  factory PendingVoter.fromJson(Map<String, dynamic> json) => PendingVoter(
        ticketNonce: json['ticketNonce'] as String,
        ticket: json['ticket'] as String,
        ephemeralIdentityCommitment:
            json['ephemeralIdentityCommitment'] as String,
        confirmationCode: json['confirmationCode'] as String,
        status: json['status'] as String,
        createdAt: (json['createdAt'] as num).toInt(),
      );

  Map<String, dynamic> toJson() => {
        'ticketNonce': ticketNonce,
        'ticket': ticket,
        'ephemeralIdentityCommitment': ephemeralIdentityCommitment,
        'confirmationCode': confirmationCode,
        'status': status,
        'createdAt': createdAt,
      };
}
