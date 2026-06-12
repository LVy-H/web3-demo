/// Shared Dark Bauhaus chrome for the VOTE space: sharp-bordered panels,
/// the phase strip, the one primary [NextAction] button (honest disabled
/// reasons), progress, receipt and sealed-results panels.
library;

import 'package:core_domain/journeys/journey.dart';
import 'package:design_system/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../copy.dart';

/// A sharp-edged Dark Bauhaus card.
class VotePanel extends StatelessWidget {
  final Widget child;
  final Color color;
  final EdgeInsetsGeometry padding;

  const VotePanel({
    super.key,
    required this.child,
    this.color = Db.slate,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: color,
      border: const Border.fromBorderSide(BorderSide(color: Db.rule)),
    ),
    child: child,
  );
}

/// REGISTRATION → VOTING → ENDED strip (legacy poll-detail style).
class PhaseStrip extends StatelessWidget {
  final int phase; // 0 reg, 1 voting, 2 ended
  const PhaseStrip({super.key, required this.phase});

  static const _labels = ['JOINING', 'VOTING', 'ENDED'];

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      border: Border.fromBorderSide(BorderSide(color: Db.rule)),
    ),
    child: Row(
      children: [
        for (var i = 0; i < 3; i++)
          Expanded(
            child: Container(
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: i == phase
                    ? Db.segnale
                    : (i < phase ? Db.slate : Db.void_),
                border: i < 2
                    ? const Border(right: BorderSide(color: Db.rule))
                    : null,
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (i < phase) ...[
                      const Icon(Icons.check, size: 12, color: Db.mute),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      _labels[i],
                      style: dbSans(
                        11,
                        800,
                        i == phase ? Db.void_ : Db.mute,
                        letterSpacing: 11 * 0.14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// The ONE primary action for the current journey state. Disabled states
/// always show why ([NextAction.disabledReasonKey] → jargon-free copy).
class PrimaryActionButton extends StatelessWidget {
  final NextAction action;
  final VoidCallback? onPressed;

  const PrimaryActionButton({
    super.key,
    required this.action,
    required this.onPressed,
  });

  static const disabledReasonKey = Key('primary-action-disabled-reason');

  @override
  Widget build(BuildContext context) {
    final enabled = action.enabled && onPressed != null;
    final waiting = action.type == NextActionType.wait;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (waiting)
          Container(
            height: 52,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Db.slate3,
              border: Border.fromBorderSide(BorderSide(color: Db.rule)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Static glyph, not a spinner: wait states are idle on an
                // EXTERNAL event (phase change), nothing is in flight here.
                const Icon(Icons.hourglass_empty, size: 14, color: Db.mute),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    voteCopy(action.labelKey),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: dbSans(12, 800, Db.chalkDim, letterSpacing: 1),
                  ),
                ),
              ],
            ),
          )
        else
          InkWell(
            onTap: enabled ? onPressed : null,
            child: Container(
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: enabled ? Db.segnale : Db.slate4,
                border: Border.fromBorderSide(
                  BorderSide(color: enabled ? Db.segnale : Db.rule),
                ),
              ),
              child: Text(
                voteCopy(action.labelKey),
                style: dbSans(
                  13,
                  800,
                  enabled ? Db.void_ : Db.mute,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
        if (action.disabledReasonKey != null) ...[
          const SizedBox(height: 8),
          Text(
            voteCopy(action.disabledReasonKey!),
            key: disabledReasonKey,
            style: dbMono(11, Db.mute, height: 1.5),
          ),
        ],
      ],
    );
  }
}

/// In-flight effect panel (proving, casting, loading) with honest copy.
class ProgressPanel extends StatelessWidget {
  final String title;
  final String? detail;

  const ProgressPanel({super.key, required this.title, this.detail});

  @override
  Widget build(BuildContext context) => VotePanel(
    child: Row(
      children: [
        const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: Db.segnale),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: dbSans(13, 800, Db.chalk, letterSpacing: 0.6)),
              if (detail != null) ...[
                const SizedBox(height: 4),
                Text(detail!, style: dbMono(11, Db.mute, height: 1.5)),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

/// Typed-error panel: jargon-free message + the state's recovery action.
class ErrorPanel extends StatelessWidget {
  final String messageKey;
  final VoidCallback onRetry;
  final String retryLabel;

  const ErrorPanel({
    super.key,
    required this.messageKey,
    required this.onRetry,
    this.retryLabel = 'TRY AGAIN',
  });

  @override
  Widget build(BuildContext context) => VotePanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.error_outline, size: 16, color: Db.segnale),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                voteCopy(messageKey),
                style: dbSans(13, 700, Db.chalk, height: 1.4),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: onRetry,
            style: OutlinedButton.styleFrom(
              foregroundColor: Db.segnale,
              side: const BorderSide(color: Db.segnale),
              shape: const RoundedRectangleBorder(),
            ),
            child: Text(retryLabel, style: dbMono(12, Db.segnale, wght: 700)),
          ),
        ),
      ],
    ),
  );
}

/// "Your private vote receipt" — code + verify action. No protocol words.
class ReceiptPanel extends StatelessWidget {
  final String code;
  final VoidCallback? onVerify;

  const ReceiptPanel({super.key, required this.code, this.onVerify});

  static const verifyKey = Key('receipt-verify-action');

  String get _shortCode =>
      code.length <= 18 ? code : '${code.substring(0, 14)}…';

  @override
  Widget build(BuildContext context) => VotePanel(
    color: Db.slate3,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('YOUR PRIVATE VOTE RECEIPT', style: dbLabel(size: 10)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                _shortCode,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: dbMono(14, Db.chalk, wght: 700, letterSpacing: 0.5),
              ),
            ),
            IconButton(
              tooltip: 'Copy receipt',
              icon: const Icon(Icons.copy, size: 16, color: Db.mute),
              onPressed: () => Clipboard.setData(ClipboardData(text: code)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Keep this code — anyone can use it to check your vote was '
          'counted, without seeing what you chose.',
          style: dbMono(11, Db.mute, height: 1.5),
        ),
        if (onVerify != null) ...[
          const SizedBox(height: 14),
          InkWell(
            key: verifyKey,
            onTap: onVerify,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Db.void_,
                border: Border.all(color: Db.segnale),
              ),
              child: Text(
                'VERIFY THIS VOTE  →',
                style: dbSans(11, 800, Db.segnale, letterSpacing: 1),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

/// Sealed-results panel: rendered INSTEAD of any tally while voting is open
/// under the sealed-until-close policy — even though chain data is readable.
class SealedResultsPanel extends StatelessWidget {
  const SealedResultsPanel({super.key});

  static const panelKey = Key('sealed-results-panel');

  @override
  Widget build(BuildContext context) => VotePanel(
    key: panelKey,
    child: Row(
      children: [
        const Icon(Icons.lock_outline, size: 18, color: Db.mute),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'RESULTS ARE SEALED',
                style: dbSans(13, 800, Db.chalk, letterSpacing: 1),
              ),
              const SizedBox(height: 4),
              Text(
                'Results open when voting closes.',
                style: dbMono(11, Db.mute, height: 1.5),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Section heading in the stamped-label style.
class VoteSectionLabel extends StatelessWidget {
  final String text;
  const VoteSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(text, style: dbLabel(size: 10, color: Db.mute)),
  );
}
