import 'package:flutter/widgets.dart';

/// Centres [child] and caps it at a comfortable single-column measure on wide
/// windows (web/desktop), while staying full-bleed on phones.
///
/// The app is single-column by design. With no width constraint the body
/// stretches edge-to-edge on a wide window: line lengths grow far past the
/// readable range and controls fling to the far edges. [ContentWidth] solves
/// that without redesigning anything — it just constrains and centres.
///
/// ## Why 640dp
/// [maxContentWidth] is **640dp**. For Tessera's body type sizes this keeps
/// line length inside the classic ~45–75 character readable band, and is wide
/// enough for the card rows and CTAs to breathe without looking cramped. It
/// sits in the 560–720dp single-column window: tighter than 720 (which already
/// starts to read long) and looser than 560 (which crowds the wider cards).
///
/// Below the cap (phones, narrow windows) the child fills the full available
/// width — no horizontal inset is added — so existing phone layouts and their
/// `SafeArea`/scroll padding are untouched.
class ContentWidth extends StatelessWidget {
  /// Default single-column maximum content width, in logical pixels.
  static const double maxContentWidth = 640;

  /// The content to centre and cap.
  final Widget child;

  /// Override the cap. Defaults to [maxContentWidth].
  final double maxWidth;

  const ContentWidth({
    super.key,
    required this.child,
    this.maxWidth = maxContentWidth,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      // Take the full width up to the cap so narrow windows are full-bleed
      // (no inset) and wide windows are capped + centred by the [Center].
      child: SizedBox(width: double.infinity, child: child),
    ),
  );
}
