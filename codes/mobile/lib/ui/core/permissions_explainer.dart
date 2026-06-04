import 'package:flutter/material.dart';

import 'poll_roles.dart';
import 'theme.dart';

/// A themed bottom sheet that explains a poll's roles + permissions in one place,
/// leading with the answer that matters most in a ZK app: **your vote is
/// private — nobody can see who voted for what.**
///
/// Static given its inputs (the poll's [ownerKind] + the user's [isRegistered]),
/// so it's widget-testable and can't fail at runtime.
Future<void> showPermissionsExplainerSheet(
  BuildContext context, {
  required PollOwnerKind ownerKind,
  bool? isRegistered,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Db.void_,
    builder: (_) =>
        _PermissionsSheet(ownerKind: ownerKind, isRegistered: isRegistered),
  );
}

class _PermissionsSheet extends StatelessWidget {
  final PollOwnerKind ownerKind;
  final bool? isRegistered;
  const _PermissionsSheet({required this.ownerKind, this.isRegistered});

  String get _ownerBody => switch (ownerKind) {
    PollOwnerKind.sponsored =>
      'This poll is sponsored — the Tessera relayer runs it (pays the gas, '
          'opens & closes voting), so no single person owns it.',
    PollOwnerKind.you =>
      "That's you — you invite voters and open or close voting.",
    PollOwnerKind.other =>
      'A specific creator controls the lifecycle: who is invited and when '
          'voting opens and closes.',
  };

  String get _youBody => switch (isRegistered) {
    true =>
      "You're registered for this poll — you can cast one anonymous "
          'vote while voting is open.',
    false =>
      "You're not registered yet — join the poll to become an eligible "
          'voter (wallet-free).',
    null => 'Enter your identity on this poll to check whether you can vote.',
  };

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'WHO CAN DO WHAT',
                    style: dbLabel(size: 12, tracking: 0.16),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Db.mute, size: 20),
                    splashRadius: 18,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Your vote is private.',
                style: dbSans(20, 800, Db.chalk, height: 1.2),
              ),
              const SizedBox(height: 8),
              Text(
                'Tessera votes are zero-knowledge proofs — these roles decide who '
                'runs a poll and who may vote, but never who you voted for.',
                style: dbMono(12, Db.mute, height: 1.55),
              ),
              const SizedBox(height: 20),
              _role(
                accent: Db.success,
                icon: Icons.visibility_off_outlined,
                tag: 'PRIVATE',
                title: 'Nobody sees your vote',
                body:
                    'Each vote is a zero-knowledge proof. Nobody — not even the '
                    "poll's owner — can see who voted for what. Only the totals "
                    'are public.',
              ),
              const SizedBox(height: 12),
              _role(
                accent: Db.segnale,
                icon: Icons.admin_panel_settings_outlined,
                tag: 'OWNER',
                title: 'Who runs the poll',
                body: _ownerBody,
              ),
              const SizedBox(height: 12),
              _role(
                accent: Db.oltremare,
                icon: Icons.how_to_vote_outlined,
                tag: 'VOTERS',
                title: 'Who can vote',
                body:
                    'Invited members (registered identities) each cast exactly '
                    'one vote. A nullifier stops anyone from voting twice.',
              ),
              const SizedBox(height: 12),
              _role(
                accent: Db.amber,
                icon: Icons.person_outline,
                tag: 'YOU',
                title: 'Your access',
                body: _youBody,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _role({
    required Color accent,
    required IconData icon,
    required String tag,
    required String title,
    required String body,
  }) => Container(
    decoration: BoxDecoration(
      color: Db.slate,
      border: Border(left: BorderSide(color: accent, width: 3)),
    ),
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: dbSans(13, 700, Db.chalk),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(tag, style: dbLabel(size: 9, color: accent)),
          ],
        ),
        const SizedBox(height: 8),
        Text(body, style: dbMono(11, Db.mute, height: 1.5)),
      ],
    ),
  );
}
