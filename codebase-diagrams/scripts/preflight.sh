#!/usr/bin/env bash
# Preflight for the codebase-diagrams skill.
# Verifies the whole toolchain with real trial exports. Exit 0 = ready, 1 = something missing.
# Usage: bash preflight.sh [--skip-trial]
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"

SKIP_TRIAL=0
[ "${1:-}" = "--skip-trial" ] && SKIP_TRIAL=1

FAIL=0
STRUCTURIZR_HELP=0
problem() { red "✗ $*"; FAIL=1; }
ok()      { green "✓ $*"; }

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t cbd)"
trap 'rm -rf "$TMP"' EXIT

bold "== codebase-diagrams preflight =="

# ---------------------------------------------------------------- Structurizr
if resolve_structurizr; then
  ok "Structurizr: $STRUCTURIZR_HOW"
  if [ "$STRUCTURIZR_MODE" = "war" ]; then
    JM="$(java_major || true)"
    if [ -z "$JM" ]; then
      problem "Java not found (needed to run the Structurizr war)"; STRUCTURIZR_HELP=1
    elif [ "$JM" -lt 21 ]; then
      problem "Java $JM found, but Structurizr needs Java 21+"; STRUCTURIZR_HELP=1
    else
      ok "Java $JM"
    fi
  fi
else
  problem "Structurizr not found (no \$STRUCTURIZR_CMD, \$STRUCTURIZR_WAR, ~/.structurizr/structurizr.war, 'structurizr' on PATH, or working Docker)"; STRUCTURIZR_HELP=1
fi

# ---------------------------------------------------------------- D2
if have d2; then
  ok "d2 $(d2 --version 2>/dev/null | head -1)"
else
  problem "d2 not found on PATH"
fi

# ---------------------------------------------------------------- Trial exports
if [ "$FAIL" -eq 0 ] && [ "$SKIP_TRIAL" -eq 0 ]; then
  bold "-- trial exports (first run pulls the Docker image or downloads Chromium; give it a few minutes) --"

  mkdir -p "$TMP/c4"
  cat > "$TMP/c4/workspace.dsl" <<'EOF'
workspace "Preflight" "Toolchain check" {
    model {
        u = person "User"
        s = softwareSystem "System" {
            c = container "Service" "" "Any"
        }
        u -> c "Uses" "HTTPS"
    }
    views {
        systemContext s "Ctx" {
            include *
            autoLayout lr
        }
        container s "Containers" {
            include *
            autoLayout lr
        }
    }
}
EOF
  if structurizr_in "$TMP/c4" validate -workspace workspace.dsl >"$TMP/validate.log" 2>&1; then
    ok "structurizr validate"
  else
    problem "structurizr validate failed:"; STRUCTURIZR_HELP=1; sed 's/^/    /' "$TMP/validate.log" | tail -20
  fi

  if [ "$FAIL" -eq 0 ]; then
    if structurizr_in "$TMP/c4" export -workspace workspace.dsl -format png -output out >"$TMP/export.log" 2>&1 \
       && ls "$TMP/c4/out"/*.png >/dev/null 2>&1; then
      ok "structurizr export -format png ($(ls "$TMP/c4/out"/*.png | wc -l | tr -d ' ') files)"
    else
      STRUCTURIZR_HELP=1; problem "structurizr PNG export failed. This usually means the build is not the Playwright-enabled one, or Chromium's system libraries are missing (Linux)."
      sed 's/^/    /' "$TMP/export.log" | tail -25
    fi
  fi

  if have d2; then
    printf 'a -> b: ok\n' > "$TMP/t.d2"
    if d2 "$TMP/t.d2" "$TMP/t.svg" >"$TMP/d2svg.log" 2>&1; then ok "d2 -> svg"; else problem "d2 SVG render failed:"; sed 's/^/    /' "$TMP/d2svg.log" | tail -10; fi
    if d2 "$TMP/t.d2" "$TMP/t.png" >"$TMP/d2png.log" 2>&1; then ok "d2 -> png"; else problem "d2 PNG render failed (headless browser problem?):"; sed 's/^/    /' "$TMP/d2png.log" | tail -10; fi
    if d2 layout 2>/dev/null | grep -qi elk; then ok "d2 layout engine 'elk' available"; else yellow "! d2 'elk' layout not listed; large infra/dependency diagrams will use dagre"; fi
  fi
fi

echo
if [ "$FAIL" -eq 0 ]; then
  green "PREFLIGHT PASSED"
  echo "Structurizr command prefix: $STRUCTURIZR_RUN"
  exit 0
fi

red "PREFLIGHT FAILED - install the missing tools, then re-run this script."
[ "$STRUCTURIZR_HELP" -eq 1 ] && install_help_structurizr
have d2 || install_help_d2
exit 1
