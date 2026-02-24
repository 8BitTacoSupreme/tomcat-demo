#!/usr/bin/env bash
#
# Liberty Mutual Tomcat Demo — for Ben Zaer
# Demonstrates: upgrade, rollback, cross-platform, and isolation with Flox
#
# Prerequisites: flox installed (https://flox.dev)
# No git clone required — all packages come from the Flox catalog.
#
# Usage: bash demo.sh [--auto] [--pause N] [--act N]
#

set -euo pipefail

# ── V2 manifest workaround ─────────────────────────────────────────────────
export FLOX_FEATURES_OUTPUTS=1

# ── Runtime environment ─────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_DIR="${SCRIPT_DIR}/runtime"
FLOX_ARGS=(-d "$RUNTIME_DIR")
MANIFEST="${RUNTIME_DIR}/.flox/env/manifest.toml"

# ── Tomcat state ────────────────────────────────────────────────────────────
CATALINA_BASE_FILE="/tmp/flox-tomcat-demo.base"

# ── Colors & helpers ──────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

AUTO=false
PAUSE_DURATION=10
BRIEF_PAUSE=3
TARGET_ACT=""

banner() {
  echo ""
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${BOLD}${CYAN}  $1${RESET}"
  echo -e "${DIM}  $2${RESET}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo ""
}

narrate() { echo -e "${YELLOW}  ▸ $1${RESET}"; }

run_cmd() {
  echo -e "${DIM}  \$ $1${RESET}"
  eval "$1"
}

pause() {
  echo ""
  if [ "$AUTO" = true ]; then
    echo -e "${GREEN}  ⏳ (auto-continuing in ${BRIEF_PAUSE}s...)${RESET}"
    sleep "$BRIEF_PAUSE"
  else
    echo -e "${GREEN}  ⏎  Press Enter to continue...${RESET}"
    read -r
  fi
  echo ""
}

browser_pause() {
  echo ""
  echo -e "${BOLD}${GREEN}  ▸ Tomcat is running — visit http://localhost:8080/sample/ in your browser${RESET}"
  if [ "$AUTO" = true ]; then
    echo -e "${GREEN}  ⏳ (auto-continuing in ${PAUSE_DURATION}s...)${RESET}"
    sleep "$PAUSE_DURATION"
  else
    echo -e "${GREEN}  ⏎  Press Enter to continue...${RESET}"
    read -r
  fi
  echo ""
}

wait_for_tomcat() {
  local max_attempts=30 attempt=0
  while [ $attempt -lt $max_attempts ]; do
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/sample/ 2>/dev/null | grep -q "200"; then
      return 0
    fi
    sleep 1
    attempt=$((attempt + 1))
  done
  echo -e "${RED}  ✗ Tomcat did not respond within ${max_attempts}s${RESET}"
  return 1
}

# ── Package swap ────────────────────────────────────────────────────────────
# Swaps tomcat and jdk versions by editing the manifest directly.
# Uses stable install IDs (tomcat, jdk) so priority settings are preserved.
swap_packages() {
  local tomcat_pkg="$1" jdk_pkg="$2"
  sed -i '' "s/^tomcat\.pkg-path = .*/tomcat.pkg-path = \"${tomcat_pkg}\"/" "$MANIFEST"
  sed -i '' "s/^jdk\.pkg-path = .*/jdk.pkg-path = \"${jdk_pkg}\"/" "$MANIFEST"
}

# ── Tomcat lifecycle ────────────────────────────────────────────────────────
start_tomcat() {
  flox activate "${FLOX_ARGS[@]}" -- bash -c '
    set -e
    real_catalina=$(readlink -f $(which catalina.sh))
    export CATALINA_HOME=$(dirname $(dirname "$real_catalina"))
    real_java=$(readlink -f $(which java))
    export JAVA_HOME=$(dirname $(dirname "$real_java"))

    BASE=$(mktemp -d /tmp/flox-tomcat-demo.XXXXXX)
    mkdir -p "$BASE"/{conf,logs,temp,work,webapps}
    cp -r "$CATALINA_HOME"/conf/* "$BASE/conf/"
    chmod -R u+w "$BASE/conf/"
    cp "$FLOX_ENV/webapps/sample.war" "$BASE/webapps/"

    export CATALINA_BASE="$BASE"
    echo "$BASE" > '"$CATALINA_BASE_FILE"'
    catalina.sh start
  '
}

stop_tomcat() {
  if [ -f "$CATALINA_BASE_FILE" ]; then
    local base
    base="$(cat "$CATALINA_BASE_FILE")"
    if [ -d "$base" ]; then
      flox activate "${FLOX_ARGS[@]}" -- bash -c '
        set -e
        real_catalina=$(readlink -f $(which catalina.sh))
        export CATALINA_HOME=$(dirname $(dirname "$real_catalina"))
        real_java=$(readlink -f $(which java))
        export JAVA_HOME=$(dirname $(dirname "$real_java"))
        export CATALINA_BASE="'"$base"'"
        catalina.sh stop 2>/dev/null || true
      '
      sleep 2
      rm -rf "$base"
    fi
    rm -f "$CATALINA_BASE_FILE"
  fi
  pkill -f "org.apache.catalina" 2>/dev/null || true
  sleep 1
}

show_versions() {
  flox activate "${FLOX_ARGS[@]}" -- bash -c '
    real_catalina=$(readlink -f $(which catalina.sh))
    export CATALINA_HOME=$(dirname $(dirname "$real_catalina"))
    catalina.sh version 2>/dev/null | grep "Server number"
    java -version 2>&1 | head -1
  '
}

# ── Setup ─────────────────────────────────────────────────────────────────────
setup() {
  banner "SETUP" "Initializing demo environment"

  if ! command -v flox &>/dev/null; then
    echo -e "${RED}  ✗ flox is not installed. Install from https://flox.dev${RESET}"
    exit 1
  fi

  if [ ! -d "$RUNTIME_DIR/.flox" ]; then
    echo -e "${RED}  ✗ Runtime environment not found at $RUNTIME_DIR${RESET}"
    exit 1
  fi

  # Ensure baseline: tomcat9 + jdk21
  narrate "Ensuring baseline environment (tomcat9 + jdk21 + sample-tomcat-app)..."
  swap_packages "tomcat9" "jdk21"
  # Verify it resolves
  flox list "${FLOX_ARGS[@]}" >/dev/null 2>&1

  echo -e "${GREEN}  ✓ Setup complete${RESET}"
}

# ── Act 1: The Acquired Company ──────────────────────────────────────────────
act1_legacy() {
  banner "ACT 1: THE ACQUIRED COMPANY" "Starting with legacy Tomcat 9 — the inherited stack"

  narrate "Ben's scenario: Liberty acquired a company running Tomcat 9 + JDK 21."
  narrate "This is what they inherited. Let's see what's in the environment."
  echo ""

  narrate "Bill of materials — every package, every version, auditable:"
  run_cmd "flox list ${FLOX_ARGS[*]}"
  pause

  narrate "The sample webapp was published to the Flox catalog."
  narrate "No git clone, no build step — just 'flox install brantley/sample-tomcat-app'."
  pause

  narrate "Starting Tomcat 9..."
  start_tomcat

  narrate "Waiting for Tomcat to come up..."
  if wait_for_tomcat; then
    echo -e "${GREEN}  ✓ Tomcat 9 is running!${RESET}"
    echo ""
    narrate "Verifying the sample app:"
    run_cmd "curl -s http://localhost:8080/sample/ | head -5"
  else
    echo -e "${RED}  ✗ Tomcat failed to start. Check logs.${RESET}"
  fi

  echo ""
  narrate "Versions:"
  show_versions

  echo ""
  narrate "This is the acquired company's stack. It works. But security says:"
  narrate "\"You have 60 days to upgrade. The clock is ticking.\""
  browser_pause

  narrate "Stopping Tomcat before upgrade..."
  stop_tomcat
}

# ── Act 2: Day 60 — Security Says Upgrade ─────────────────────────────────────
act2_upgrade() {
  banner "ACT 2: DAY 60 — SECURITY SAYS UPGRADE" "Upgrading Tomcat 9 → 11 and JDK 21 → 25"

  narrate "The 60-day security window is closing."
  narrate "With Flox, the upgrade is a one-liner — not a week-long project."
  echo ""

  narrate "Before the upgrade — current bill of materials:"
  run_cmd "flox list ${FLOX_ARGS[*]}"
  pause

  narrate "Swapping Tomcat 9 → 11 and JDK 21 → 25 in the manifest:"
  swap_packages "tomcat11" "jdk25"
  echo -e "${GREEN}  ✓ Manifest updated${RESET}"

  echo ""
  narrate "No compilation. No download. Both tomcat9 and tomcat11 are pre-built"
  narrate "in the Nixpkgs binary cache. Switching versions is a pointer swap."
  echo ""
  narrate "Updated bill of materials:"
  run_cmd "flox list ${FLOX_ARGS[*]}"
  pause

  narrate "Starting Tomcat 11 — NO rebuild needed. Same webapp, new runtime."
  start_tomcat

  narrate "Waiting for Tomcat to come up..."
  if wait_for_tomcat; then
    echo -e "${GREEN}  ✓ Tomcat 11 is running!${RESET}"
    echo ""
    narrate "Verifying the sample app:"
    run_cmd "curl -s http://localhost:8080/sample/ | head -5"
  fi

  echo ""
  narrate "Versions:"
  show_versions

  echo ""
  narrate "The 60-day upgrade treadmill just became a one-liner."
  browser_pause

  narrate "Stopping Tomcat before rollback demo..."
  stop_tomcat
}

# ── Act 3: It Broke in Production ─────────────────────────────────────────────
act3_rollback() {
  banner "ACT 3: IT BROKE IN PRODUCTION" "Instant rollback — pointer swap, not rebuild"

  narrate "Uh oh. QA found a compatibility issue with Tomcat 11."
  narrate "Production is down. The team is panicking."
  narrate "With traditional infra, rollback means: rebuild, redeploy, pray."
  narrate "With Flox? It's a pointer swap."
  echo ""

  narrate "Rolling back — swap packages back to Tomcat 9 + JDK 21:"
  swap_packages "tomcat9" "jdk21"
  echo -e "${GREEN}  ✓ Manifest restored to Tomcat 9 + JDK 21${RESET}"
  echo ""

  narrate "Let's verify:"
  run_cmd "flox list ${FLOX_ARGS[*]}"
  pause

  narrate "Starting Tomcat — same webapp discovers Tomcat 9 again."
  start_tomcat

  narrate "Waiting for Tomcat to come up..."
  if wait_for_tomcat; then
    echo -e "${GREEN}  ✓ Tomcat 9 is back!${RESET}"
    echo ""
    narrate "Verifying the sample app:"
    run_cmd "curl -s http://localhost:8080/sample/ | head -5"
  fi

  echo ""
  narrate "Versions:"
  show_versions

  echo ""
  narrate "Rollback is a metadata change, not a rebuild."
  narrate "No redownload. No recompilation. Seconds, not hours."
  browser_pause

  narrate "Stopping Tomcat..."
  stop_tomcat
}

# ── Act 4: Works on My Machine — And Yours ────────────────────────────────────
act4_platform() {
  banner "ACT 4: CROSS-PLATFORM CONSISTENCY" "Same env on dev MacBooks and prod EC2 Linux"

  narrate "Ben's team: devs on MacBooks, production on AWS EC2 Linux."
  narrate "\"Works on my machine\" is not acceptable for 5500 apps."
  echo ""

  narrate "The lock file pins exact versions for ALL platforms:"
  echo ""
  narrate "Platforms covered in the lock file:"
  run_cmd "grep '\"system\"' ${RUNTIME_DIR}/.flox/env/manifest.lock | sort -u"
  echo ""

  narrate "Your devs on MacBooks and your EC2 instances on Linux"
  narrate "get the exact same Tomcat, same JDK, same configs."
  echo ""

  narrate "To share with the team:"
  echo -e "${DIM}  \$ flox push     # push to FloxHub${RESET}"
  echo -e "${DIM}  \$ flox pull     # teammates pull the exact environment${RESET}"
  echo ""
  narrate "Or just commit the .flox/env/ directory to your repo."
  narrate "git clone + flox activate = identical environment everywhere."
  pause
}

# ── Act 5: No More Host Dependencies ──────────────────────────────────────────
act5_isolation() {
  banner "ACT 5: NO MORE HOST DEPENDENCIES" "Everything from the Nix store — zero host coupling"

  narrate "Ben's pain: K8s host dependencies, mount points, host packages."
  narrate "\"Move this container and everything breaks.\""
  narrate "With Flox, everything resolves to the Nix store."
  echo ""

  flox activate "${FLOX_ARGS[@]}" -- bash -c '
    echo -e "  \033[1;33m▸ Where is Java?\033[0m"
    echo -e "  \033[2m  $(which java)\033[0m"
    echo -e "  \033[2m  → $(readlink -f $(which java))\033[0m"
    echo ""
    echo -e "  \033[1;33m▸ Where is Tomcat?\033[0m"
    echo -e "  \033[2m  $(which catalina.sh)\033[0m"
    echo -e "  \033[2m  → $(readlink -f $(which catalina.sh))\033[0m"
    echo ""
    echo -e "  \033[1;33m▸ Where is the sample webapp?\033[0m"
    echo -e "  \033[2m  $FLOX_ENV/webapps/sample.war\033[0m"
  '

  echo ""
  narrate "Notice: everything is in /nix/store/..."
  narrate "Nothing installed to /usr/local. No host packages. No mount point dependencies."
  echo ""

  narrate "The Nix store hash guarantees:"
  narrate "  - Exact same binary on every machine"
  narrate "  - No dependency on host OS packages"
  narrate "  - No conflicts between different app versions"
  echo ""

  narrate "Move this to any container, any VM, any EC2 instance."
  narrate "The environment travels with it. Zero host coupling."
  pause
}

# ── Cleanup ───────────────────────────────────────────────────────────────────
cleanup() {
  banner "CLEANUP" "Stopping services and restoring baseline"

  stop_tomcat
  echo -e "${GREEN}  ✓ Tomcat stopped${RESET}"

  narrate "Restoring baseline (tomcat9 + jdk21)..."
  swap_packages "tomcat9" "jdk21"
  echo -e "${GREEN}  ✓ Baseline restored${RESET}"

  echo ""
  echo -e "${BOLD}${CYAN}  Demo complete!${RESET}"
  echo ""
  narrate "Recap — what we showed Ben:"
  echo -e "  ${GREEN}✓${RESET} Webapp from Flox catalog — no git clone, no build needed"
  echo -e "  ${GREEN}✓${RESET} Tomcat 9 → 11 upgrade — pointer swap, not rebuild"
  echo -e "  ${GREEN}✓${RESET} Instant rollback — seconds, not hours"
  echo -e "  ${GREEN}✓${RESET} Cross-platform consistency (lock file pins all architectures)"
  echo -e "  ${GREEN}✓${RESET} Zero host dependencies (Nix store isolation)"
  echo -e "  ${GREEN}✓${RESET} Bill of materials for compliance (flox list)"
  echo ""
}

# ── Arg parsing ───────────────────────────────────────────────────────────────
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --auto)  AUTO=true; shift ;;
      --pause)
        [ -n "${2:-}" ] || { echo "Error: --pause requires a number" >&2; exit 1; }
        PAUSE_DURATION="$2"; BRIEF_PAUSE="$2"; shift 2 ;;
      --act)
        [ -n "${2:-}" ] || { echo "Error: --act requires 1-5 or 'cleanup'" >&2; exit 1; }
        TARGET_ACT="$2"; shift 2 ;;
      -h|--help)
        echo "Usage: $0 [--auto] [--pause N] [--act N]"
        echo ""
        echo "Options:"
        echo "  --auto      Run unattended with timed pauses"
        echo "  --pause N   Set pause duration in seconds (default: 10)"
        echo "  --act N     Jump to a specific act (1-5 or 'cleanup')"
        exit 0 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
  parse_args "$@"

  banner "LIBERTY MUTUAL TOMCAT DEMO" "For Ben Zaer — Eliminating the 60-day upgrade treadmill"

  if [ "$AUTO" = true ]; then
    narrate "Running in AUTO mode (pauses: ${PAUSE_DURATION}s browser, ${BRIEF_PAUSE}s output)"
    echo ""
  fi

  narrate "This demo shows how Flox eliminates the pain of:"
  narrate "  - 60-day Tomcat upgrade cycles"
  narrate "  - Slow, risky rollbacks"
  narrate "  - Host dependency nightmares"
  narrate "  - \"Works on my machine\" inconsistencies"
  echo ""

  if [ -n "$TARGET_ACT" ]; then
    case "$TARGET_ACT" in
      1) setup; act1_legacy ;;
      2) act2_upgrade ;;
      3) act3_rollback ;;
      4) act4_platform ;;
      5) act5_isolation ;;
      cleanup) cleanup ;;
      *) echo "Usage: $0 [--auto] [--act 1|2|3|4|5|cleanup]"; exit 1 ;;
    esac
    exit 0
  fi

  setup
  act1_legacy
  act2_upgrade
  act3_rollback
  act4_platform
  act5_isolation
  cleanup
}

main "$@"
