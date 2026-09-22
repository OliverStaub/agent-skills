#!/usr/bin/env bash
# Format, validate and render every .d2 file in <dir>/d2/ (or a single file) to SVG + PNG.
# Usage: bash render-d2.sh <target-dir | file.d2> [--svg-only]
# Per-file layout/theme belong in the file itself via:
#   vars: { d2-config: { layout-engine: elk; theme-id: 0; pad: 40 } }
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib.sh"

TARGET="${1:?usage: render-d2.sh <target-dir|file.d2> [--svg-only]}"
SVG_ONLY=0; [ "${2:-}" = "--svg-only" ] && SVG_ONLY=1

have d2 || { red "d2 not found - run scripts/preflight.sh"; exit 1; }

files=()
if [ -f "$TARGET" ]; then
  files=("$TARGET")
else
  d="$TARGET/d2"; [ -d "$d" ] || d="$TARGET"
  while IFS= read -r f; do files+=("$f"); done < <(find "$d" -maxdepth 1 -name '*.d2' | sort)
fi
[ ${#files[@]} -gt 0 ] || { yellow "no .d2 files found under $TARGET"; exit 0; }

status=0
for f in "${files[@]}"; do
  base="${f%.d2}"
  bold "$f"
  d2 fmt "$f" 2>/dev/null || true
  if ! d2 validate "$f"; then red "  invalid D2 - fix and re-run"; status=1; continue; fi
  if d2 "$f" "$base.svg"; then green "  -> $base.svg"; else red "  svg render failed"; status=1; continue; fi
  if [ $SVG_ONLY -eq 0 ]; then
    # --pad 40 keeps PNGs compact; scale 2 gives crisp text when embedded in docs.
    if d2 --pad 40 --scale 2 "$f" "$base.png"; then green "  -> $base.png"; else red "  png render failed"; status=1; fi
  fi
done

[ $status -eq 0 ] && green "D2 render OK" || red "D2 render had errors"
exit $status
