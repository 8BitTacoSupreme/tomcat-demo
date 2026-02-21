# Tomcat Demo — Automated Mode

Run the full Liberty Mutual Tomcat demo unattended with timed pauses.

## Quick Start

```bash
./demo.sh --auto
```

## Options

| Flag | Description | Default |
|---|---|---|
| `--auto` | Run unattended with timed pauses (no Enter key needed) | Off (interactive) |
| `--pause N` | Set all pause durations to N seconds | 10s browser, 3s output |
| `--act N` | Jump to a specific act (1–5 or `cleanup`) | Run all acts |
| `-h`, `--help` | Show help | — |

### Examples

```bash
# Full demo, automated, default pauses
./demo.sh --auto

# Fast run with 2-second pauses (good for testing)
./demo.sh --auto --pause 2

# Automated, just Act 2 (the upgrade)
./demo.sh --auto --act 2

# Interactive mode, jump to Act 3 (rollback)
./demo.sh --act 3
```

## What Each Act Does

| Act | Title | What Happens |
|---|---|---|
| **1** | The Acquired Company | Activates Tomcat 9 + JDK 21, deploys sample webapp, starts Tomcat |
| **2** | Security Says Upgrade | Swaps manifest to Tomcat 11 + JDK 25, applies with `flox edit -f`, commits |
| **3** | It Broke in Production | Rolls back to Tomcat 9 via `git checkout`, restarts Tomcat |
| **4** | Cross-Platform Consistency | Shows lock file covering 4 platforms (macOS + Linux, ARM + x86) |
| **5** | No More Host Dependencies | Shows `/nix/store/` paths for Java and Tomcat — zero host coupling |
| **cleanup** | Cleanup | Stops Tomcat, restores environment to original state |

## What to Watch For

- **Act 1:** Browser at `http://localhost:8080/sample/` shows Tomcat 9 + JDK 21 (orange "LEGACY" badge)
- **Act 2:** After upgrade, same URL now shows Tomcat 11 + JDK 25 (green "UPGRADED" badge)
- **Act 3:** After rollback, browser flips back to Tomcat 9 (orange again) — visual proof of the pointer swap
- **Act 5:** `readlink -f` output showing `/nix/store/` paths (not `/usr/local/`)

In `--auto` mode, browser-viewable moments print:

```
  ▸ Tomcat is running — visit http://localhost:8080/sample/ in your browser
  ⏳ (auto-continuing in 10s...)
```

## Troubleshooting

### Port 8080 already in use

```bash
lsof -ti:8080 | xargs kill -9 2>/dev/null || true
```

### flox not found

Install Flox from [https://flox.dev](https://flox.dev), then restart your shell.

### Tomcat fails to start

Check if a previous Tomcat instance is still running:

```bash
pkill -f "org.apache.catalina" 2>/dev/null || true
sleep 2
./demo.sh --auto
```

### Demo state is dirty from a previous run

```bash
git checkout HEAD -- .flox/env/
pkill -f "org.apache.catalina" 2>/dev/null || true
```

### `flox edit -f` fails in Act 2

The manifest swap depends on exact string matching. If the manifest format has changed, export and inspect it:

```bash
flox list -c
```

Then manually edit with `flox edit` and re-run from Act 2:

```bash
./demo.sh --auto --act 2
```
