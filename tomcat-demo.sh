#!/usr/bin/env bash
#
# tomcat-demo — Flox-aware Tomcat launcher
#
# Built as a package via `flox build`. The @out@ placeholder is replaced
# at build time with the Nix store path. At runtime, the wrapper discovers
# Tomcat and JDK from $FLOX_ENV — so upgrading tomcat9→11 in [install]
# doesn't require rebuilding this package.
#
# Usage: tomcat-demo {run|start|stop|restart|status}
#
# Adapted from limeytexan/sample-tomcat-app

set -euo pipefail

out='@out@'

# ── Helpers ──────────────────────────────────────────────────────────────────

die() { echo "ERROR: $*" >&2; exit 1; }

find_java() {
  local java=""
  if [ -n "${FLOX_ENV:-}" ] && [ -x "$FLOX_ENV/bin/java" ]; then
    java="$FLOX_ENV/bin/java"
  elif command -v java &>/dev/null; then
    java="$(command -v java)"
  fi
  [ -n "$java" ] || die "java not found. Activate a Flox environment with a JDK."
  echo "$java"
}

find_catalina() {
  local catalina=""

  # Check $FLOX_ENV/bin first
  if [ -n "${FLOX_ENV:-}" ] && [ -x "$FLOX_ENV/bin/catalina.sh" ]; then
    catalina="$FLOX_ENV/bin/catalina.sh"
  fi

  # Fallback: search share/tomcat*/bin/
  if [ -z "$catalina" ] && [ -n "${FLOX_ENV:-}" ]; then
    for d in "$FLOX_ENV"/share/tomcat*/bin/catalina.sh; do
      if [ -x "$d" ]; then
        catalina="$d"
        break
      fi
    done
  fi

  # Fallback: PATH
  if [ -z "$catalina" ]; then
    catalina="$(command -v catalina.sh 2>/dev/null || true)"
  fi

  [ -n "$catalina" ] || die "catalina.sh not found. Activate a Flox environment with Tomcat."
  echo "$catalina"
}

setup_java_home() {
  local java_bin="$1"
  # Resolve symlinks to find the real path
  local real_java
  real_java="$(readlink -f "$java_bin" 2>/dev/null || realpath "$java_bin" 2>/dev/null || echo "$java_bin")"

  # Walk up from bin/java to the JDK root
  local java_home
  java_home="$(dirname "$(dirname "$real_java")")"

  if [ -d "$java_home/lib" ]; then
    export JAVA_HOME="$java_home"
  else
    # JRE-style layout
    export JRE_HOME="$java_home"
  fi
}

# ── CATALINA_BASE setup ─────────────────────────────────────────────────────

create_base() {
  local base
  base="$(mktemp -d "${TMPDIR:-/tmp}/tomcat-demo.XXXXXX")"

  mkdir -p "$base"/{conf,logs,temp,work,webapps}

  # Copy default config from CATALINA_HOME
  local catalina_home
  catalina_home="$(dirname "$(dirname "$CATALINA_SH")")"
  if [ -d "$catalina_home/conf" ]; then
    cp -r "$catalina_home"/conf/* "$base/conf/"
    chmod -R u+w "$base/conf/"
  fi

  # Symlink webapps from the built package
  if [ -d "$out/webapps" ]; then
    for app in "$out"/webapps/*/; do
      local name
      name="$(basename "$app")"
      ln -sf "$app" "$base/webapps/$name"
    done
  fi

  echo "$base"
}

cleanup_base() {
  if [ -n "${CATALINA_BASE:-}" ] && [ -d "$CATALINA_BASE" ]; then
    chmod -R u+w "$CATALINA_BASE" 2>/dev/null || true
    rm -rf "$CATALINA_BASE"
  fi
}

# ── Commands ─────────────────────────────────────────────────────────────────

cmd_run() {
  JAVA_BIN="$(find_java)"
  CATALINA_SH="$(find_catalina)"
  setup_java_home "$JAVA_BIN"

  export CATALINA_BASE
  CATALINA_BASE="$(create_base)"

  trap cleanup_base EXIT
  echo "CATALINA_BASE=$CATALINA_BASE"
  exec "$CATALINA_SH" run
}

cmd_start() {
  JAVA_BIN="$(find_java)"
  CATALINA_SH="$(find_catalina)"
  setup_java_home "$JAVA_BIN"

  export CATALINA_BASE
  CATALINA_BASE="$(create_base)"

  # Persist base path for stop command
  echo "$CATALINA_BASE" > /tmp/tomcat-demo.base

  echo "CATALINA_BASE=$CATALINA_BASE"
  "$CATALINA_SH" start
}

cmd_stop() {
  local base=""
  if [ -f /tmp/tomcat-demo.base ]; then
    base="$(cat /tmp/tomcat-demo.base)"
  fi

  if [ -n "$base" ] && [ -d "$base" ]; then
    export CATALINA_BASE="$base"

    # Need java/catalina to stop gracefully
    JAVA_BIN="$(find_java)"
    CATALINA_SH="$(find_catalina)"
    setup_java_home "$JAVA_BIN"

    "$CATALINA_SH" stop 2>/dev/null || true
    sleep 2
    chmod -R u+w "$base" 2>/dev/null || true
    rm -rf "$base"
    rm -f /tmp/tomcat-demo.base
    echo "Tomcat stopped and cleaned up."
  else
    echo "No running instance found (no /tmp/tomcat-demo.base)."
  fi

  # Belt and suspenders
  pkill -f "org.apache.catalina" 2>/dev/null || true
}

cmd_status() {
  echo "Package:       $out"
  echo "FLOX_ENV:      ${FLOX_ENV:-<not set>}"
  echo "Java:          $(find_java 2>/dev/null || echo 'not found')"
  echo "Catalina:      $(find_catalina 2>/dev/null || echo 'not found')"
  if [ -f /tmp/tomcat-demo.base ]; then
    echo "CATALINA_BASE: $(cat /tmp/tomcat-demo.base)"
    echo "Running:       yes"
  else
    echo "Running:       no"
  fi
}

# ── Main ─────────────────────────────────────────────────────────────────────

case "${1:-}" in
  run)     cmd_run ;;
  start)   cmd_start ;;
  stop)    cmd_stop ;;
  restart) cmd_stop; cmd_start ;;
  status)  cmd_status ;;
  *)
    echo "Usage: $(basename "$0") {run|start|stop|restart|status}"
    exit 1
    ;;
esac
