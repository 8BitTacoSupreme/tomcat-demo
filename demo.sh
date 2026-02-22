#!/usr/bin/env bash
#
# Liberty Mutual Tomcat Demo — for Ben Zaer
# Demonstrates: build, upgrade, rollback, cross-platform, and isolation with Flox
#
# Usage: tomcat-demo-run [--auto] [--pause N] [--act N]
#

set -euo pipefail

# ── Colors & helpers ──────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ── Mode flags ────────────────────────────────────────────────────────────────
AUTO=false
PAUSE_DURATION=10   # seconds for browser-viewable pauses
BRIEF_PAUSE=3       # seconds for output review pauses
TARGET_ACT=""       # set by --act N

# ── Wrapper path ──────────────────────────────────────────────────────────────
WRAPPER="tomcat-demo"

# ── Manifest resolution ──────────────────────────────────────────────────────
find_manifests_dir() {
  local d="${FLOX_ENV:-}/share/manifests"
  [ -d "$d" ] && echo "$d" && return
  # Dev fallback: running from repo checkout
  echo "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/manifests"
}
MANIFESTS_DIR="$(find_manifests_dir)"
BASELINE_MANIFEST="$MANIFESTS_DIR/tomcat9-baseline.toml"
UPGRADE_MANIFEST="$MANIFESTS_DIR/tomcat11-upgrade.toml"

banner() {
  echo ""
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${BOLD}${CYAN}  $1${RESET}"
  echo -e "${DIM}  $2${RESET}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo ""
}

narrate() {
  echo -e "${YELLOW}  ▸ $1${RESET}"
}

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
  local max_attempts=30
  local attempt=0
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

stop_tomcat() {
  $WRAPPER stop 2>/dev/null || true
  # Belt and suspenders
  pkill -f "org.apache.catalina" 2>/dev/null || true
  sleep 1
}

build_app() {
  if command -v tomcat-demo &>/dev/null; then
    narrate "App package already on PATH — skipping build."
    echo -e "${GREEN}  ✓ Package available: $(which tomcat-demo)${RESET}"
  else
    narrate "Building the app package with 'flox build'..."
    run_cmd "flox build"
    echo -e "${GREEN}  ✓ Package built: ./result-tomcat-demo/${RESET}"
  fi
}

# ── Setup ─────────────────────────────────────────────────────────────────────
setup() {
  banner "SETUP" "Initializing demo environment"

  if ! command -v flox &>/dev/null; then
    echo -e "${RED}  ✗ flox is not installed. Install from https://flox.dev${RESET}"
    exit 1
  fi

  narrate "Resetting to baseline (tomcat9 + jdk21)..."
  run_cmd "flox edit -f \"$BASELINE_MANIFEST\""

  echo -e "${GREEN}  ✓ Setup complete${RESET}"
}

# ── Act 1: The Acquired Company ──────────────────────────────────────────────
act1_legacy() {
  banner "ACT 1: THE ACQUIRED COMPANY" "Starting with legacy Tomcat 9 — the inherited stack"

  narrate "Ben's scenario: Liberty acquired a company running Tomcat 9 + JDK 21."
  narrate "This is what they inherited. Let's see what's in the environment."
  echo ""

  narrate "Bill of materials — every package, every version, auditable:"
  run_cmd "flox list"
  pause

  narrate "Building the app package — bundles the webapp with a Tomcat launcher."
  narrate "The app is built once as an immutable package. The runtime comes from the environment."
  build_app
  pause

  narrate "Activating the environment and starting the app..."

  # Source the flox profile to get runtime deps
  eval "$(flox activate)"

  narrate "Starting Tomcat 9 via the packaged launcher..."
  run_cmd "$WRAPPER start"
  echo ""

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
  narrate "Tomcat version:"
  run_cmd "catalina.sh version 2>/dev/null | grep 'Server number'"
  narrate "Java version:"
  run_cmd "java -version 2>&1 | head -1"

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
  run_cmd "flox list"
  echo ""

  narrate "Here's the manifest diff — what we're changing:"
  run_cmd "diff \"$BASELINE_MANIFEST\" \"$UPGRADE_MANIFEST\" || true"
  pause

  narrate "Applying the upgrade with 'flox edit -f'..."
  run_cmd "flox edit -f \"$UPGRADE_MANIFEST\""

  echo ""
  narrate "No compilation. No download. Both tomcat9 and tomcat11 are pre-built"
  narrate "in the Nixpkgs binary cache. Flox resolved and cached them already."
  narrate "Switching versions is a pointer swap, not a compile."
  echo ""
  narrate "Updated bill of materials:"
  run_cmd "flox list"

  echo ""
  narrate "In a real workflow, you'd commit the .flox/env/ directory to git here."
  narrate "That gives you a full audit trail of every environment change."
  pause

  narrate "Re-activating with the new packages..."
  eval "$(flox activate)"

  narrate "Starting Tomcat 11 — NO rebuild needed."
  narrate "Same package, new runtime. The wrapper discovers Tomcat 11 from the environment."
  run_cmd "$WRAPPER start"

  narrate "Waiting for Tomcat to come up..."
  if wait_for_tomcat; then
    echo -e "${GREEN}  ✓ Tomcat 11 is running!${RESET}"
    echo ""
    narrate "Verifying the sample app:"
    run_cmd "curl -s http://localhost:8080/sample/ | head -5"
  fi

  echo ""
  narrate "Tomcat version:"
  run_cmd "catalina.sh version 2>/dev/null | grep 'Server number'"
  narrate "Java version:"
  run_cmd "java -version 2>&1 | head -1"

  echo ""
  narrate "The 60-day upgrade treadmill just became a one-liner."
  narrate "And in a real workflow, you'd have a full audit trail in git."
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

  narrate "Rolling back to the previous environment (Tomcat 9 + JDK 21)..."
  run_cmd "flox edit -f \"$BASELINE_MANIFEST\""
  echo ""

  narrate "That's it. Let's verify what we have now:"
  run_cmd "flox list"
  pause

  narrate "Re-activating the rolled-back environment..."
  eval "$(flox activate)"

  narrate "Starting Tomcat — still no rebuild. Same package discovers Tomcat 9 again."
  run_cmd "$WRAPPER start"

  narrate "Waiting for Tomcat to come up..."
  if wait_for_tomcat; then
    echo -e "${GREEN}  ✓ Tomcat 9 is back!${RESET}"
    echo ""
    narrate "Verifying the sample app:"
    run_cmd "curl -s http://localhost:8080/sample/ | head -5"
  fi

  echo ""
  narrate "Tomcat version:"
  run_cmd "catalina.sh version 2>/dev/null | grep 'Server number'"
  narrate "Java version:"
  run_cmd "java -version 2>&1 | head -1"

  echo ""
  narrate "This is the pointer swap. Both versions exist in the Nix store."
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
  run_cmd "grep '\"system\"' .flox/env/manifest.lock | sort -u"
  echo ""

  narrate "Your devs on MacBooks (aarch64-darwin, x86_64-darwin)"
  narrate "and your EC2 instances on Linux (aarch64-linux, x86_64-linux)"
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

  eval "$(flox activate)"

  narrate "Where is Java?"
  run_cmd "which java"
  narrate "Actual Nix store path:"
  run_cmd "readlink -f \$(which java)"
  echo ""

  narrate "Where is Tomcat?"
  run_cmd "which catalina.sh"
  narrate "Actual Nix store path:"
  run_cmd "readlink -f \$(which catalina.sh)"
  echo ""

  narrate "Where is the app package itself?"
  run_cmd "readlink -f \$(which tomcat-demo)"
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
  banner "CLEANUP" "Stopping services and cleaning up"

  stop_tomcat
  echo -e "${GREEN}  ✓ Tomcat stopped${RESET}"

  # Restore to tomcat9 baseline for re-runnability
  flox edit -f "$BASELINE_MANIFEST" 2>/dev/null || true

  echo ""
  echo -e "${BOLD}${CYAN}  Demo complete!${RESET}"
  echo ""
  narrate "Recap — what we showed Ben:"
  echo -e "  ${GREEN}✓${RESET} Built the app once as an immutable package (flox build)"
  echo -e "  ${GREEN}✓${RESET} Tomcat 9 → 11 upgrade — no rebuild needed"
  echo -e "  ${GREEN}✓${RESET} Instant rollback via pointer swap"
  echo -e "  ${GREEN}✓${RESET} Full audit trail (manifest diffs)"
  echo -e "  ${GREEN}✓${RESET} Cross-platform consistency (4 architectures)"
  echo -e "  ${GREEN}✓${RESET} Zero host dependencies (Nix store isolation)"
  echo -e "  ${GREEN}✓${RESET} Bill of materials for compliance (flox list)"
  echo ""
}

# ── Arg parsing ───────────────────────────────────────────────────────────────
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --auto)
        AUTO=true
        shift
        ;;
      --pause)
        if [ -z "${2:-}" ]; then
          echo "Error: --pause requires a number (seconds)" >&2
          exit 1
        fi
        PAUSE_DURATION="$2"
        BRIEF_PAUSE="$2"
        shift 2
        ;;
      --act)
        if [ -z "${2:-}" ]; then
          echo "Error: --act requires a number (1-5 or 'cleanup')" >&2
          exit 1
        fi
        TARGET_ACT="$2"
        shift 2
        ;;
      -h|--help)
        echo "Usage: $0 [--auto] [--pause N] [--act N]"
        echo ""
        echo "Options:"
        echo "  --auto      Run unattended with timed pauses (no Enter key needed)"
        echo "  --pause N   Set pause duration in seconds (default: 10 for browser, 3 for output)"
        echo "  --act N     Jump to a specific act (1-5 or 'cleanup')"
        echo "  -h, --help  Show this help message"
        exit 0
        ;;
      *)
        echo "Unknown option: $1" >&2
        echo "Usage: $0 [--auto] [--pause N] [--act N]" >&2
        exit 1
        ;;
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

  # Allow jumping to a specific act
  if [ -n "$TARGET_ACT" ]; then
    case "$TARGET_ACT" in
      1) setup; act1_legacy ;;
      2) act2_upgrade ;;
      3) act3_rollback ;;
      4) act4_platform ;;
      5) act5_isolation ;;
      cleanup) cleanup ;;
      *) echo "Usage: $0 [--auto] [--pause N] [--act 1|2|3|4|5|cleanup]"; exit 1 ;;
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
