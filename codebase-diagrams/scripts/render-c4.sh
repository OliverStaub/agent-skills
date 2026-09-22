#!/usr/bin/env bash
# Validate <dir>/workspace.dsl and export every view to <dir>/c4/ as PNG and SVG.
# Usage: bash render-c4.sh <target-dir> [--svg-only|--png-only]
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib.sh"

DIR="${1:?usage: render-c4.sh <target-dir> [--svg-only|--png-only]}"
MODE="${2:-}"
[ -f "$DIR/workspace.dsl" ] || { red "No workspace.dsl in $DIR"; exit 2; }

resolve_structurizr || { red "Structurizr not found - run scripts/preflight.sh"; exit 1; }

bold "validate"
if ! structurizr_in "$DIR" validate -workspace workspace.dsl; then
  red "workspace.dsl is invalid - fix the error above (the parser reports the line) and re-run."
  exit 1
fi

mkdir -p "$DIR/c4"
formats="png svg"
[ "$MODE" = "--svg-only" ] && formats="svg"
[ "$MODE" = "--png-only" ] && formats="png"

status=0
for f in $formats; do
  bold "export -format $f"
  if ! structurizr_in "$DIR" export -workspace workspace.dsl -format "$f" -output c4; then
    red "export to $f failed"; status=1
  fi
done

# Also keep a JSON export next to the DSL: handy for tooling and for preserving manual layout later.
structurizr_in "$DIR" export -workspace workspace.dsl -format json -output . >/dev/null 2>&1 || true

echo
bold "exported views:"
ls -1 "$DIR/c4" 2>/dev/null | sed 's/^/  /'
n=$(ls -1 "$DIR/c4"/*.png 2>/dev/null | wc -l | tr -d ' ')
[ "$n" -eq 0 ] && [ "$MODE" != "--svg-only" ] && { red "no PNG files were produced"; status=1; }
[ $status -eq 0 ] && green "C4 render OK" || red "C4 render had errors"
exit $status
