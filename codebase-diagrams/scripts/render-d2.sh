#!/usr/bin/env bash
# Format, validate and render every .d2 file in <dir>/d2/ (or a single file).
# Usage: bash render-d2.sh <target-dir | file.d2> [--format svg|png|both]   (default: svg)
# The chosen format is written next to each source; PNG previews always go to a scratch
# directory outside the repo (printed at the end) so every diagram can be looked at.
# Per-file layout/theme belong in the file itself via:
#   vars: { d2-config: { layout-engine: elk; theme-id: 0; pad: 40 } }
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib.sh"

TARGET="${1:?usage: render-d2.sh <target-dir|file.d2> [--format svg|png|both]}"; shift
FORMAT="svg"
while [ $# -gt 0 ]; do
  case "$1" in
    --format) FORMAT="${2:?--format needs svg, png or both}"; shift ;;
    --svg-only) FORMAT="svg" ;;
    *) red "unknown option $1"; exit 2 ;;
  esac
  shift
done
case "$FORMAT" in svg|png|both) ;; *) red "--format must be svg, png or both"; exit 2 ;; esac

have d2 || { red "d2 not found - run scripts/preflight.sh"; exit 1; }

files=()
if [ -f "$TARGET" ]; then
  files=("$TARGET"); SRC_DIR="$(cd "$(dirname "$TARGET")" && pwd)"
else
  d="$TARGET/d2"; [ -d "$d" ] || d="$TARGET"
  SRC_DIR="$(cd "$d" && pwd)"
  while IFS= read -r f; do files+=("$f"); done < <(find "$d" -maxdepth 1 -name '*.d2' | sort)
fi
[ ${#files[@]} -gt 0 ] || { yellow "no .d2 files found under $TARGET"; exit 0; }
ROOT="$SRC_DIR"; [ "$(basename "$ROOT")" = "d2" ] && ROOT="$(dirname "$ROOT")"
PREVIEW="$(preview_dir "$ROOT")/d2"; mkdir -p "$PREVIEW"

status=0
for f in "${files[@]}"; do
  base="${f%.d2}"; name="$(basename "$base")"
  bold "$f"
  d2 fmt "$f" 2>/dev/null || true
  if ! d2 validate "$f"; then red "  invalid D2 - fix and re-run"; status=1; continue; fi
  # --pad 40 keeps PNGs compact; scale 2 gives crisp text when embedded in docs.
  if ! d2 --pad 40 --scale 2 "$f" "$PREVIEW/$name.png"; then red "  render failed"; status=1; continue; fi
  if [ "$FORMAT" != "png" ]; then
    d2 "$f" "$base.svg" || { red "  svg render failed"; status=1; continue; }
    green "  -> $base.svg"
  else
    rm -f "$base.svg"
  fi
  if [ "$FORMAT" != "svg" ]; then
    cp "$PREVIEW/$name.png" "$base.png"; green "  -> $base.png"
  else
    rm -f "$base.png"
  fi
done

# Images whose source is gone are leftovers from an earlier run - flag them rather than delete.
for img in "$SRC_DIR"/*.svg "$SRC_DIR"/*.png; do
  [ -e "$img" ] || continue
  [ -f "${img%.*}.d2" ] || yellow "orphan image with no .d2 source (delete it if unintended): $img"
done

bold "PNG previews (look at these): $PREVIEW"
[ $status -eq 0 ] && green "D2 render OK" || red "D2 render had errors"
exit $status
