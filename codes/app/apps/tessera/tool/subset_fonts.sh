#!/usr/bin/env bash
# Regenerate the subsetted UI fonts in assets/fonts/ from full upstream files.
#
# The app ships SUBSET copies of Inter and JetBrains Mono (perf/web-load-time):
# both are in FontManifest.json, so Flutter web fetches them BEFORE first
# paint — the full families cost 1,063KB; the subsets ~474KB.
#
# What the subset keeps (verify before shrinking further):
#   - Variable-font axes (fvar/gvar): design_system/theme.dart drives weight
#     via FontVariation('wght', ...) — instancing to static weights would
#     silently flatten every weight to regular.
#   - Kerning (GPOS) and the tnum/zero/case features.
#   - Scripts: Latin, Latin Extended A/B + Additional (full Vietnamese),
#     combining diacritics, general punctuation, currency (₫), ™, arrows,
#     minus/division, fi/fl ligatures.
#   - Glyphs OUTSIDE the subset are not lost at runtime: Flutter web falls
#     back to downloading a matching Noto font on demand.
#
# Usage: drop the full Inter.ttf / JetBrainsMono.ttf into assets/fonts/, then
#   ./tool/subset_fonts.sh
# (Uses fonttools; on NixOS: nix run nixpkgs#python3Packages.fonttools)
set -euo pipefail
cd "$(dirname "$0")/../assets/fonts"

RANGES="U+0000-00FF,U+0100-017F,U+0180-024F,U+0300-036F,U+1E00-1EFF,U+2000-206F,U+20A0-20CF,U+2122,U+2190-2199,U+2212,U+2215,U+FB00-FB04"

subset() {
  local f="$1"
  if command -v pyftsubset >/dev/null 2>&1; then
    SUBSET=(pyftsubset)
  else
    SUBSET=(nix run nixpkgs#python3Packages.fonttools -- subset)
  fi
  "${SUBSET[@]}" "$f.ttf" \
    --output-file="$f.subset.ttf" \
    --unicodes="$RANGES" \
    --layout-features+=tnum,zero,case \
    --no-hinting \
    --notdef-outline
  mv "$f.subset.ttf" "$f.ttf"
  ls -la "$f.ttf"
}

subset Inter
subset JetBrainsMono
