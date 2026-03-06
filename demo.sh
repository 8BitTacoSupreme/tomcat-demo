#!/usr/bin/env bash
#
# demo.sh — Automated 5-act demo of Flox immutable package model
#
# Usage:
#   bash demo.sh                  # Interactive mode (press Enter between steps)
#   bash demo.sh --auto           # Auto mode (timed pauses)
#   bash demo.sh --auto --pause 3 # Auto mode with 3s pauses
#   bash demo.sh --act 2          # Jump to specific act
#

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────

DEMO_DIR="$HOME/tomcatdemo"
CONSUMER_DIR="/tmp/demo-consumer"
CATALOG_PKG="8BitTacoSupreme/tomcat-demo"
PORT=8080
AUTO=false
PAUSE=5
START_ACT=1

# ── Parse arguments ──────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    --auto)  AUTO=true; shift ;;
    --pause) PAUSE="$2"; shift 2 ;;
    --act)   START_ACT="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: bash demo.sh [--auto] [--pause N] [--act N]"
      echo "  --auto     Timed pauses instead of waiting for Enter"
      echo "  --pause N  Pause duration in seconds (default: 5)"
      echo "  --act N    Jump to specific act (1-5)"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ── Colors & formatting ─────────────────────────────────────────────────────

BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
MAGENTA='\033[0;35m'
RESET='\033[0m'

banner() {
  echo ""
  echo -e "${BOLD}${MAGENTA}═══════════════════════════════════════════════════════════${RESET}"
  echo -e "${BOLD}${MAGENTA}  $1${RESET}"
  echo -e "${BOLD}${MAGENTA}═══════════════════════════════════════════════════════════${RESET}"
  echo ""
}

narrate() {
  echo -e "${CYAN}▸ $1${RESET}"
}

run_cmd() {
  echo -e "${DIM}\$ $1${RESET}"
  eval "$1"
}

pause_step() {
  if $AUTO; then
    sleep "$PAUSE"
  else
    echo ""
    echo -e "${YELLOW}  ⏎  Press Enter to continue...${RESET}"
    read -r
  fi
}

browse() {
  local url="http://localhost:${PORT}/sample/"
  echo -e "${GREEN}  → Browse: ${url}${RESET}"
  if ! $AUTO; then
    open "$url" 2>/dev/null || true
  fi
  pause_step
}

# ── Setup ────────────────────────────────────────────────────────────────────

setup() {
  # Kill stale Tomcat
  pkill -f "org.apache.catalina" 2>/dev/null || true
  sleep 1

  # Ensure consumer directory exists with v2 manifest
  if [ ! -d "$CONSUMER_DIR/.flox" ]; then
    echo -e "${DIM}Setting up consumer environment at $CONSUMER_DIR...${RESET}"
    mkdir -p "$CONSUMER_DIR"
    (cd "$CONSUMER_DIR" && flox init)
    # Overwrite with minimal v2 manifest
    cat > "$CONSUMER_DIR/.flox/env/manifest.toml" <<'MANIFEST'
version = 2

[install]

[options]
MANIFEST
    echo -e "${GREEN}Consumer environment created.${RESET}"
  fi
}

wait_for_tomcat() {
  local max_wait=15
  local waited=0
  while ! curl -s -o /dev/null "http://localhost:${PORT}/" 2>/dev/null; do
    sleep 1
    waited=$((waited + 1))
    if [ $waited -ge $max_wait ]; then
      echo "Warning: Tomcat did not start within ${max_wait}s"
      return 1
    fi
  done
  sleep 1
}

stop_tomcat() {
  if [ -f /tmp/tomcat-demo.base ]; then
    run_cmd "$1 stop" || true
  fi
  pkill -f "org.apache.catalina" 2>/dev/null || true
  sleep 2
}

# ── Act 1: The Developer Builds ─────────────────────────────────────────────

act1() {
  banner "Act 1: The Developer Builds"

  narrate "Every app ships with its own environment. Let me show you what that means."
  pause_step

  narrate "Show the manifest — this is the bill of materials:"
  run_cmd "cat $DEMO_DIR/.flox/env/manifest.toml"
  pause_step

  narrate "Build the package in a Nix sandbox:"
  run_cmd "cd $DEMO_DIR && flox build"
  pause_step

  narrate "Inspect the wrapper script — notice the /nix/store shebang:"
  run_cmd "head -5 $DEMO_DIR/result-tomcat-demo/bin/tomcat-demo"
  pause_step

  narrate "Show the bundled environment:"
  run_cmd "$DEMO_DIR/result-tomcat-demo/bin/tomcat-demo status"
  pause_step

  narrate "Start Tomcat from the built package:"
  run_cmd "$DEMO_DIR/result-tomcat-demo/bin/tomcat-demo start"
  wait_for_tomcat
  browse

  narrate "Stop Tomcat."
  stop_tomcat "$DEMO_DIR/result-tomcat-demo/bin/tomcat-demo"
  pause_step
}

# ── Act 2: Publish & Consume v1 ─────────────────────────────────────────────

act2() {
  banner "Act 2: Publish & Consume v1"

  narrate "Show what's in the catalog:"
  run_cmd "flox show $CATALOG_PKG"
  pause_step

  narrate "Switch to the consumer environment:"
  run_cmd "cat $CONSUMER_DIR/.flox/env/manifest.toml"
  narrate "A minimal V2 manifest — no tomcat, no jdk."
  pause_step

  narrate "Install v1.0.0 from the catalog:"
  run_cmd "cd $CONSUMER_DIR && FLOX_FEATURES_OUTPUTS=1 flox install ${CATALOG_PKG}@1.0.0"
  pause_step

  narrate "Activate and start Tomcat:"
  run_cmd "cd $CONSUMER_DIR && flox activate -- tomcat-demo start"
  wait_for_tomcat
  browse

  narrate "Stop Tomcat."
  stop_tomcat "cd $CONSUMER_DIR && flox activate -- tomcat-demo"
  pause_step
}

# ── Act 3: Developer Ships v2 ───────────────────────────────────────────────

act3() {
  banner "Act 3: Developer Ships v2"

  narrate "The developer upgrades: tomcat9 → tomcat11, jdk21 → jdk25, 1.0.0 → 2.0.0"
  narrate "(Both versions are already published to the catalog.)"
  pause_step

  narrate "Show both versions in the catalog:"
  run_cmd "flox show $CATALOG_PKG"
  pause_step
}

# ── Act 4: Operator Upgrades ────────────────────────────────────────────────

act4() {
  banner "Act 4: Operator Upgrades"

  narrate "The operator upgrades with one command:"
  run_cmd "cd $CONSUMER_DIR && FLOX_FEATURES_OUTPUTS=1 flox install ${CATALOG_PKG}@2.0.0"
  pause_step

  narrate "Start Tomcat with the upgraded package:"
  run_cmd "cd $CONSUMER_DIR && flox activate -- tomcat-demo start"
  wait_for_tomcat
  browse

  narrate "Green badge, TC11, JDK25 — a completely different immutable package."
  pause_step

  narrate "Stop Tomcat."
  stop_tomcat "cd $CONSUMER_DIR && flox activate -- tomcat-demo"
  pause_step
}

# ── Act 5: Rollback ─────────────────────────────────────────────────────────

act5() {
  banner "Act 5: Rollback"

  narrate "Something breaks. Roll back to v1.0.0:"
  run_cmd "cd $CONSUMER_DIR && FLOX_FEATURES_OUTPUTS=1 flox install ${CATALOG_PKG}@1.0.0"
  pause_step

  narrate "Start Tomcat — should be back to orange badge:"
  run_cmd "cd $CONSUMER_DIR && flox activate -- tomcat-demo start"
  wait_for_tomcat
  browse

  narrate "Orange badge, TC9, JDK21. Rollback is a pointer swap, not a rebuild."
  pause_step

  narrate "Stop Tomcat."
  stop_tomcat "cd $CONSUMER_DIR && flox activate -- tomcat-demo"
  pause_step

  narrate "Show the audit trail — every change recorded:"
  run_cmd "cd $CONSUMER_DIR && flox generations"
  pause_step

  banner "Demo Complete"
  echo -e "${GREEN}  What we showed:${RESET}"
  echo "    • Developer builds once → immutable package with bundled environment"
  echo "    • Operator installs from catalog → exact same package, no drift"
  echo "    • Upgrade = change version number, one command"
  echo "    • Rollback = change version number back, one command"
  echo "    • Full audit trail with flox generations"
  echo "    • No containers, no image registry, no Dockerfile — just packages"
  echo ""
  echo -e "${YELLOW}  For the live build demo (Act 5 bonus):${RESET}"
  echo "    1. Edit webapp/sample/index.jsp — change demoMessage"
  echo "    2. Bump version to 2.0.1 in .flox/env/manifest.toml"
  echo "    3. flox build && flox publish"
  echo "    4. Consumer: FLOX_FEATURES_OUTPUTS=1 flox install ${CATALOG_PKG}@2.0.1"
  echo ""
}

# ── Main ─────────────────────────────────────────────────────────────────────

setup

acts=(act1 act2 act3 act4 act5)

for i in "${!acts[@]}"; do
  act_num=$((i + 1))
  if [ "$act_num" -ge "$START_ACT" ]; then
    "${acts[$i]}"
  fi
done
