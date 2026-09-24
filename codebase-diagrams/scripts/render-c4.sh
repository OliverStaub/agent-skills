#!/usr/bin/env bash
# Validate <dir>/workspace.dsl and export every view into <dir>/c4/.
# Usage: bash render-c4.sh <target-dir> [--format svg|png|both]   (default: svg)
#
# <dir>/c4/ is treated as generated output: it is replaced on every successful export, so views
# that were removed from the DSL do not leave stale images behind. Structurizr's automatic legend
# images (<view>-key.*) and the JSON export are not kept - they look like half-finished diagrams.
# PNG previews of every view are always written to a scratch directory outside the repo (printed
# at the end) so the result can be looked at even when the repo only keeps SVG.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib.sh"

DIR="${1:?usage: render-c4.sh <target-dir> [--format svg|png|both]}"; shift
FORMAT="svg"
while [ $# -gt 0 ]; do
  case "$1" in
    --format) FORMAT="${2:?--format needs svg, png or both}"; shift ;;
    --svg-only) FORMAT="svg" ;;
    --png-only) FORMAT="png" ;;
    *) red "unknown option $1"; exit 2 ;;
  esac
  shift
done
case "$FORMAT" in svg|png|both) ;; *) red "--format must be svg, png or both"; exit 2 ;; esac
[ -f "$DIR/workspace.dsl" ] || { red "No workspace.dsl in $DIR"; exit 2; }
DIR="$(cd "$DIR" && pwd)"
PREVIEW="$(preview_dir "$DIR")/c4"

resolve_structurizr || { red "Structurizr not found - run scripts/preflight.sh"; exit 1; }

bold "validate"
if ! structurizr_in "$DIR" validate -workspace workspace.dsl; then
  red "workspace.dsl is invalid - fix the error above (the parser reports the line) and re-run."
  exit 1
fi

# Export into a staging dir inside the target (Docker can only see the mounted directory), then
# swap it into place only if everything succeeded, so a failed run leaves the old images intact.
STAGE=".c4-export"
rm -rf "$DIR/$STAGE"; mkdir -p "$DIR/$STAGE"
trap 'rm -rf "$DIR/$STAGE"' EXIT

exports="png"; [ "$FORMAT" != "png" ] && exports="png svg"
for f in $exports; do
  bold "export -format $f"
  if ! structurizr_in "$DIR" export -workspace workspace.dsl -format "$f" -output "$STAGE"; then
    red "export to $f failed - existing $DIR/c4 left untouched"; exit 1
  fi
done
rm -f "$DIR/$STAGE"/*-key.png "$DIR/$STAGE"/*-key.svg

n=$(ls -1 "$DIR/$STAGE"/*.png 2>/dev/null | wc -l | tr -d ' ')
[ "$n" -gt 0 ] || { red "no views were exported"; exit 1; }

rm -rf "$PREVIEW"; mkdir -p "$PREVIEW"
cp "$DIR/$STAGE"/*.png "$PREVIEW/"
[ "$FORMAT" = "svg" ] && rm -f "$DIR/$STAGE"/*.png
[ "$FORMAT" = "png" ] && rm -f "$DIR/$STAGE"/*.svg

rm -rf "$DIR/c4"; mv "$DIR/$STAGE" "$DIR/c4"
rm -f "$DIR/workspace.json"   # written by older versions of this script

echo
bold "views in $DIR/c4:"
ls -1 "$DIR/c4" | sed 's/^/  /'
bold "PNG previews (look at these): $PREVIEW"
green "C4 render OK"
