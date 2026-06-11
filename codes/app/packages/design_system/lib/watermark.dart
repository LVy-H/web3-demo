import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'theme.dart';

/// Faint corner watermark glyphs that give each poll card its character —
/// ported from the inline SVG symbols in the web Home.tsx (#illo-vote /
/// #illo-schedule / #illo-trophy). Strokes are white in the source so a srcIn
/// color filter tints + dims them to the phase color.
enum PollPhase { active, upcoming, ended }

const _voteSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 140 140">
<g fill="none" stroke="#fff" stroke-width="3">
<rect x="22" y="60" width="96" height="58"/>
<line x1="38" y1="60" x2="102" y2="60"/>
<line x1="46" y1="60" x2="94" y2="60" stroke-width="6" opacity="0.5"/>
<rect x="46" y="18" width="48" height="40"/>
<polyline points="56,38 67,49 86,28" stroke-width="4" stroke-linecap="square"/>
<line x1="38" y1="80" x2="58" y2="80" stroke-width="2" opacity="0.65"/>
<line x1="38" y1="92" x2="74" y2="92" stroke-width="2" opacity="0.45"/>
<line x1="38" y1="104" x2="50" y2="104" stroke-width="2" opacity="0.3"/>
</g></svg>''';

const _scheduleSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 140 140">
<g fill="none" stroke="#fff" stroke-width="3">
<circle cx="70" cy="62" r="38"/>
<line x1="70" y1="28" x2="70" y2="34"/><line x1="70" y1="90" x2="70" y2="96"/>
<line x1="36" y1="62" x2="42" y2="62"/><line x1="98" y1="62" x2="104" y2="62"/>
<line x1="70" y1="62" x2="90" y2="46" stroke-width="4" stroke-linecap="square"/>
<line x1="70" y1="62" x2="70" y2="40" stroke-linecap="square"/>
<rect x="56" y="112" width="28" height="18"/>
<path d="M62 112 v-6 a8 8 0 0 1 16 0 v6"/>
</g><circle cx="70" cy="62" r="3" fill="#fff"/></svg>''';

const _trophySvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 140 140">
<g fill="none" stroke="#fff" stroke-width="3">
<path d="M44 24 C 30 44, 30 96, 44 116" stroke-linecap="square"/>
<path d="M96 24 C 110 44, 110 96, 96 116" stroke-linecap="square"/>
<rect x="54" y="50" width="32" height="36"/>
<polyline points="60,68 68,76 80,60" stroke-width="3.5" stroke-linecap="square"/>
<line x1="40" y1="120" x2="100" y2="120"/>
</g></svg>''';

class Watermark extends StatelessWidget {
  final PollPhase phase;
  final double size;
  const Watermark({super.key, required this.phase, this.size = 140});

  @override
  Widget build(BuildContext context) {
    final (svg, color) = switch (phase) {
      PollPhase.active => (_voteSvg, Db.segnale.withValues(alpha: 0.20)),
      PollPhase.upcoming => (_scheduleSvg, Db.oltremare.withValues(alpha: 0.25)),
      PollPhase.ended => (_trophySvg, Db.success.withValues(alpha: 0.18)),
    };
    return IgnorePointer(
      child: SvgPicture.string(
        svg,
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      ),
    );
  }
}
