import 'package:flutter/material.dart';

import '../core/theme.dart';

/// A single tally row: an option [label] and its [count]. Pure data — no colors,
/// no widgets — so callers feed it straight from their on-chain reads
/// (`PollSnapshot.results`, `BlindSnapshot.results`, …).
typedef ResultOption = ({String label, BigInt count});

/// Reusable, presentational tally chart — one themed horizontal bar per option,
/// fill ∝ count/total, with the label, count, and `%`. Highlights the single
/// leader; a tie shows no winner. Zero total renders a clean empty state instead
/// of dividing by zero. No data fetching, no chart package — Dark Bauhaus tokens
/// (`Db.*` / `db*`) and Flutter layout only.
///
/// Used by both the M1 anon poll detail ("LIVE RESULTS") and the M2 blind poll
/// reveal/tally ("REVEALED TALLY"); each screen owns its own card chrome and
/// passes the per-option counts here.
class ResultsBars extends StatelessWidget {
  /// Per-option `(label, count)` rows, in display order.
  final List<ResultOption> options;

  /// Total to divide by for each fraction. When null it's the sum of the
  /// option counts; pass an explicit total only if it can exceed that sum.
  final BigInt? total;

  /// Copy for the zero-total empty state. Defaults to "No votes yet"; the blind
  /// screen overrides it with its reveal-specific guidance.
  final String emptyLabel;

  /// Key attached to the leading bar's winner marker — present iff there is a
  /// single, strict leader (so tests can assert a winner exists / a tie or zero
  /// total shows none).
  static const winnerKey = Key('results-bars-winner');

  const ResultsBars({
    super.key,
    required this.options,
    this.total,
    this.emptyLabel = 'No votes yet',
  });

  @override
  Widget build(BuildContext context) {
    final sum = options.fold(BigInt.zero, (a, o) => a + o.count);
    final denom = total ?? sum;

    if (denom <= BigInt.zero) {
      return Row(children: [
        const Icon(Icons.inbox_outlined, size: 16, color: Db.mute),
        const SizedBox(width: 10),
        Expanded(
          child: Text(emptyLabel, style: dbMono(12, Db.mute, height: 1.5)),
        ),
      ]);
    }

    // Strict single leader by exact BigInt comparison (never via the float %),
    // so a true tie highlights nobody.
    final leaderIndex = _strictLeaderIndex(options);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          _Bar(
            label: options[i].label,
            count: options[i].count,
            total: denom,
            color: Db.optionColor(i),
            isLeader: i == leaderIndex,
          ),
        ],
      ],
    );
  }

  /// Index of the unique maximum count, or null if no votes or a tie at the top.
  static int? _strictLeaderIndex(List<ResultOption> options) {
    if (options.isEmpty) return null;
    var maxCount = BigInt.zero;
    int? leader;
    var tied = false;
    for (var i = 0; i < options.length; i++) {
      final c = options[i].count;
      if (c > maxCount) {
        maxCount = c;
        leader = i;
        tied = false;
      } else if (c == maxCount) {
        tied = true;
      }
    }
    if (leader == null || maxCount <= BigInt.zero || tied) return null;
    return leader;
  }
}

class _Bar extends StatelessWidget {
  final String label;
  final BigInt count;
  final BigInt total;
  final Color color;
  final bool isLeader;
  const _Bar({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
    required this.isLeader,
  });

  @override
  Widget build(BuildContext context) {
    // BigInt / BigInt -> double; uint256 counts stay well within double range,
    // so the fraction (and its %) are exact enough for display.
    final frac = (count / total).clamp(0.0, 1.0);
    final pct = frac * 100;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            if (isLeader) ...[
              Icon(Icons.emoji_events, key: ResultsBars.winnerKey,
                  size: 13, color: color),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: dbSans(14, isLeader ? 800 : 700, Db.chalk,
                      letterSpacing: 0.3)),
            ),
            // Flexible + ellipsis so a huge BigInt count string shrinks instead
            // of overflowing the row (78-digit values have no wrap points).
            Flexible(
              child: Text('$count',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: dbMono(20, Db.chalk, wght: 700, letterSpacing: -0.4)),
            ),
            const SizedBox(width: 8),
            Text('${pct.toStringAsFixed(1)}%', style: dbMono(11, Db.mute)),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 8,
          child: Stack(children: [
            const Positioned.fill(child: ColoredBox(color: Db.rule)),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: frac,
              child: ColoredBox(color: color),
            ),
          ]),
        ),
      ],
    );
  }
}
