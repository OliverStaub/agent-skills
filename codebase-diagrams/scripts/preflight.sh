#!/usr/bin/env bash
# Preflight for the codebase-diagrams skill.
# Verifies the whole toolchain with real trial exports. Exit 0 = ready, 1 = something missing.
# Run it from the root of the project to be diagrammed: the trial workspace is created inside
# that project, so the Docker file-sharing check covers the path the real renders will use.
# Checks run cheapest first and stop at the first Structurizr problem.
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

# Trial workspace location. Not the system temp dir: Docker VMs (Colima by default) often do not
# share /var/folders, so the container would see an empty directory. Instead:
#   - the skill's own folder, when the skill is installed inside the project (<project>/.claude/skills/...)
#   - otherwise <project>/.claude/tmp, created if needed
PROJECT="$(pwd -P)"
SKILL_DIR="$(cd "$HERE/.." && pwd -P)"
case "$SKILL_DIR/" in
  "$PROJECT"/*) BASE="$SKILL_DIR/.tmp" ;;
  *)            BASE="$PROJECT/.claude/tmp" ;;
esac
CREATED=""   # directories this script created, removed again on exit if empty
d="$BASE"
while [ ! -d "$d" ]; do CREATED="$d $CREATED"; d="$(dirname "$d")"; done
if mkdir -p "$BASE" 2>/dev/null && TMP="$(mktemp -d "$BASE/preflight.XXXXXX" 2>/dev/null)"; then :; else
  yellow "! cannot write to $BASE; falling back to the system temp dir (Docker may not see it)"
  CREATED=""; TMP="$(mktemp -d 2>/dev/null || mktemp -d -t cbd)"
fi
cleanup() {
  rm -rf "$TMP"
  local c; for c in $(printf '%s\n' $CREATED | awk '{ print length, $0 }' | sort -rn | cut -d' ' -f2-); do
    rmdir "$c" 2>/dev/null
  done
}
trap cleanup EXIT

# Print the verdict and exit. Called at the end, or early from the first Structurizr trial failure.
finish() {
  echo
  if [ "$FAIL" -eq 0 ]; then
    green "PREFLIGHT PASSED"
    echo "Structurizr command prefix: $STRUCTURIZR_RUN"
    exit 0
  fi
  if [ "${MOUNT_PROBLEM:-0}" -eq 1 ]; then
    red "PREFLIGHT FAILED - Docker file sharing, not a missing tool: apply one of the fixes above, then re-run."
    exit 1
  fi
  red "PREFLIGHT FAILED - install the missing tools, then re-run this script."
  [ "$STRUCTURIZR_HELP" -eq 1 ] && install_help_structurizr
  have d2 || install_help_d2
  exit 1
}

bold "== codebase-diagrams preflight =="

# ---------------------------------------------------------------- Tools present (fast)
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

if have d2; then
  ok "d2 $(d2 --version 2>/dev/null | head -1)"
else
  problem "d2 not found on PATH"
fi

[ "$FAIL" -eq 0 ] && [ "$SKIP_TRIAL" -eq 0 ] || finish

# ---------------------------------------------------------------- Trial workspace
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

# ---------------------------------------------------------------- Docker: image + file sharing (~1s)
if [ "$STRUCTURIZR_MODE" = "docker" ]; then
  IMG="${STRUCTURIZR_DOCKER_IMAGE:-$STRUCTURIZR_DOCKER_IMAGE_DEFAULT}"
  if ! docker image inspect "$IMG" >/dev/null 2>&1; then
    bold "-- pulling $IMG (one-time, a few hundred MB) --"
    docker pull "$IMG" || { problem "docker pull $IMG failed"; STRUCTURIZR_HELP=1; finish; }
  fi
  # An unshared host path is mounted as an empty directory; Structurizr would then only say
  # "workspace.dsl does not exist". Check directly so the real cause is reported.
  if docker run --rm -v "$TMP/c4:/usr/local/structurizr" --entrypoint sh "$IMG" \
       -c 'test -f /usr/local/structurizr/workspace.dsl' >/dev/null 2>&1; then
    ok "Docker can see the project ($PROJECT)"
  else
    MOUNT_PROBLEM=1
    problem "Docker cannot see $PROJECT (the container gets an empty directory)."
    cat <<EOF
    Nothing is missing - this is Docker file sharing (active context: $(docker context show 2>/dev/null || echo '?')).
    Colima shares only \$HOME unless 'mounts:' is set; Docker Desktop shares /Users, /Volumes,
    /private, /tmp and /var/folders by default. Fix one of:
      - work on a checkout under \$HOME
      - Colima:  colima stop && colima start --mount \$HOME:w --mount $PROJECT:w
                 (or add both under 'mounts:' in ~/.colima/<profile>/colima.yaml)
      - Docker Desktop: Settings > Resources > File sharing, add the path
      - skip Docker: Java 21 + STRUCTURIZR_WAR=/path/to/structurizr-<ver>-playwright.war
EOF
    finish
  fi
fi

# ---------------------------------------------------------------- Trial exports
bold "-- trial exports (first run may download Chromium; give it a few minutes) --"

if structurizr_in "$TMP/c4" validate -workspace workspace.dsl >"$TMP/validate.log" 2>&1; then
  ok "structurizr validate"
else
  problem "structurizr validate failed:"; STRUCTURIZR_HELP=1; sed 's/^/    /' "$TMP/validate.log" | tail -20
  finish
fi

if structurizr_in "$TMP/c4" export -workspace workspace.dsl -format png -output out >"$TMP/export.log" 2>&1 \
   && ls "$TMP/c4/out"/*.png >/dev/null 2>&1; then
  ok "structurizr export -format png ($(ls "$TMP/c4/out"/*.png | wc -l | tr -d ' ') files)"
else
  STRUCTURIZR_HELP=1; problem "structurizr PNG export failed. This usually means the build is not the Playwright-enabled one, or Chromium's system libraries are missing (Linux)."
  sed 's/^/    /' "$TMP/export.log" | tail -25
  finish
fi

printf 'a -> b: ok\n' > "$TMP/t.d2"
if d2 "$TMP/t.d2" "$TMP/t.svg" >"$TMP/d2svg.log" 2>&1; then ok "d2 -> svg"; else problem "d2 SVG render failed:"; sed 's/^/    /' "$TMP/d2svg.log" | tail -10; fi
if d2 "$TMP/t.d2" "$TMP/t.png" >"$TMP/d2png.log" 2>&1; then ok "d2 -> png"; else problem "d2 PNG render failed (headless browser problem?):"; sed 's/^/    /' "$TMP/d2png.log" | tail -10; fi
if d2 layout 2>/dev/null | grep -qi elk; then ok "d2 layout engine 'elk' available"; else yellow "! d2 'elk' layout not listed; large infra/dependency diagrams will use dagre"; fi

finish
