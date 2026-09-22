#!/usr/bin/env bash
# Shared helpers for preflight.sh, render-c4.sh and render-d2.sh.
# Sourced, not executed.

# Minimum Structurizr version whose Docker image / war ship the -playwright variant.
STRUCTURIZR_VERSION_DEFAULT="2026.09.19"
STRUCTURIZR_DOCKER_IMAGE_DEFAULT="structurizr/structurizr:${STRUCTURIZR_VERSION:-$STRUCTURIZR_VERSION_DEFAULT}-playwright"

red()    { printf '\033[31m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
bold()   { printf '\033[1m%s\033[0m\n' "$*"; }

have() { command -v "$1" >/dev/null 2>&1; }

# Prints the major version of the java on PATH (or $JAVA_HOME/bin/java), or nothing.
java_major() {
  local jbin="java"
  [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ] && jbin="$JAVA_HOME/bin/java"
  have "$jbin" || [ -x "$jbin" ] || return 1
  "$jbin" -version 2>&1 | grep -v JAVA_TOOL_OPTIONS | head -1 \
    | sed -E 's/.*version "([0-9]+)(\.[0-9]+)*.*/\1/'
}

# Resolve how to run Structurizr. Sets:
#   STRUCTURIZR_MODE   = cmd | war | docker | none
#   STRUCTURIZR_RUN    = the command prefix (array-ish string; use with eval)
#   STRUCTURIZR_HOW    = human-readable description
# Order of precedence (Docker is the recommended route; it is the only one that
# guarantees the Playwright-enabled build needed for PNG/SVG export):
#   1. $STRUCTURIZR_CMD   (full command prefix, e.g. "java -jar /opt/structurizr-2026.09.19-playwright.war")
#   2. $STRUCTURIZR_USE_DOCKER=1  -> Docker, even if a war exists
#   3. $STRUCTURIZR_WAR   (path to a -playwright war)
#   4. ~/.structurizr/structurizr.war or ./structurizr*.war
#   5. Docker image $STRUCTURIZR_DOCKER_IMAGE (default structurizr/structurizr:<ver>-playwright)
#   6. `structurizr` on PATH - last, because the Homebrew formula builds the
#      plain war without Playwright, so it validates but cannot export images.
docker_ok() { have docker && docker info >/dev/null 2>&1; }
use_docker() {
  local img="${STRUCTURIZR_DOCKER_IMAGE:-$STRUCTURIZR_DOCKER_IMAGE_DEFAULT}"
  STRUCTURIZR_MODE="docker"; STRUCTURIZR_RUN="docker run --rm -v \"__WORKDIR__:/usr/local/structurizr\" $img"
  STRUCTURIZR_HOW="docker image $img"
}
resolve_structurizr() {
  STRUCTURIZR_MODE="none"; STRUCTURIZR_RUN=""; STRUCTURIZR_HOW=""
  if [ -n "${STRUCTURIZR_CMD:-}" ]; then
    STRUCTURIZR_MODE="cmd"; STRUCTURIZR_RUN="$STRUCTURIZR_CMD"; STRUCTURIZR_HOW="\$STRUCTURIZR_CMD = $STRUCTURIZR_CMD"; return 0
  fi
  if [ "${STRUCTURIZR_USE_DOCKER:-0}" = "1" ]; then
    if docker_ok; then use_docker; return 0; fi
    STRUCTURIZR_HOW="STRUCTURIZR_USE_DOCKER=1 is set but Docker is not running"; return 1
  fi
  local war=""
  if [ -n "${STRUCTURIZR_WAR:-}" ] && [ -f "$STRUCTURIZR_WAR" ]; then
    war="$STRUCTURIZR_WAR"
  elif [ -f "$HOME/.structurizr/structurizr.war" ]; then
    war="$HOME/.structurizr/structurizr.war"
  else
    local f
    for f in ./structurizr*.war; do [ -f "$f" ] && { war="$f"; break; }; done
  fi
  if [ -n "$war" ]; then
    local jbin="java"
    [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ] && jbin="$JAVA_HOME/bin/java"
    STRUCTURIZR_MODE="war"; STRUCTURIZR_RUN="$jbin -jar $war"; STRUCTURIZR_HOW="java -jar $war"; return 0
  fi
  if docker_ok; then use_docker; return 0; fi
  if have structurizr; then
    STRUCTURIZR_MODE="cmd"; STRUCTURIZR_RUN="structurizr"
    STRUCTURIZR_HOW="structurizr on PATH ($(command -v structurizr)) - note: the Homebrew build has no Playwright, PNG/SVG export will likely fail"
    return 0
  fi
  return 1
}

# Run a structurizr command inside a working directory. All file arguments must be
# relative to that directory (Docker mounts it at /usr/local/structurizr).
#   structurizr_in <workdir> <args...>
structurizr_in() {
  local workdir="$1"; shift
  workdir="$(cd "$workdir" && pwd)"
  case "$STRUCTURIZR_MODE" in
    docker)
      local run="${STRUCTURIZR_RUN/__WORKDIR__/$workdir}"
      # Rewrite relative paths after -workspace/-output to the container mount.
      local args=() prev=""
      for a in "$@"; do
        if [ "$prev" = "-workspace" ] || [ "$prev" = "-output" ]; then
          case "$a" in /*) args+=("$a");; *) args+=("/usr/local/structurizr/$a");; esac
        else
          args+=("$a")
        fi
        prev="$a"
      done
      (cd "$workdir" && eval "$run" '"${args[@]}"')
      ;;
    *)
      (cd "$workdir" && eval "$STRUCTURIZR_RUN" '"$@"')
      ;;
  esac
}

install_help_structurizr() {
  cat <<EOF

$(bold "How to install Structurizr (PNG/SVG export needs the Playwright-enabled build):")

  Option A - Docker (recommended: no Java or Chromium setup, image already contains Playwright)
       docker pull ${STRUCTURIZR_DOCKER_IMAGE_DEFAULT}
     Docker Desktop / the daemon must be running. Newer version? Set STRUCTURIZR_VERSION=<ver> or
     STRUCTURIZR_DOCKER_IMAGE=structurizr/structurizr:<ver>-playwright (see https://docs.structurizr.com/binaries).
     The plain 'latest' tag and 'brew install structurizr' have no Playwright and cannot export PNG/SVG.
     To force Docker even when a war or PATH binary exists: export STRUCTURIZR_USE_DOCKER=1

  Option B - Java 21 + war
    1. Install Java 21 if missing:  macOS: brew install openjdk@21   |  sdkman: sdk install java 21-tem
       Linux: apt install openjdk-21-jre  /  dnf install java-21-openjdk   |  Windows: winget install EclipseAdoptium.Temurin.21.JRE
    2. Download the Playwright build (latest known: ${STRUCTURIZR_VERSION_DEFAULT}):
         mkdir -p ~/.structurizr
         curl -L -o ~/.structurizr/structurizr.war https://download.structurizr.com/structurizr-${STRUCTURIZR_VERSION_DEFAULT}-playwright.war
       (any path works if you export STRUCTURIZR_WAR=/path/to/structurizr-<ver>-playwright.war)
    3. Linux only: Playwright needs Chromium's shared libraries: npx playwright install-deps chromium
    The first export downloads a Chromium build (~150 MB); this happens once.

  Option C - anything else: export STRUCTURIZR_CMD="<full command prefix that accepts 'validate'/'export'>"
EOF
}

install_help_d2() {
  cat <<'EOF'

How to install D2:
    macOS/Linux:  curl -fsSL https://d2lang.com/install.sh | sh -s --
    Homebrew:     brew install d2
    Windows:      scoop install main/d2      (or download from https://github.com/terrastruct/d2/releases)
    Go:           go install oss.terrastruct.com/d2@latest
  Verify with:    d2 --version
  PNG export in d2 < 0.9 uses a headless Chromium that d2 downloads on first use; if that fails
  offline, update d2 (0.9+ has a built-in renderer).
EOF
}
