# Tomcat Demo — Manual Walkthrough

Step-by-step guide for presenting the Liberty Mutual Tomcat demo to Ben Zaer.

---

## Prerequisites

- **Flox** installed ([https://flox.dev](https://flox.dev))
- **Git** installed
- Port **8080** available on localhost
- No internet access required — the webapp is included in the repo

## Setup

```bash
git clone <repo-url> tomcat-test
cd tomcat-test
```

Verify the environment is ready:

```bash
flox list
```

Expected output — you should see `tomcat9` and `jdk21`:

```
tomcat9: tomcat9 (9.0.x)
jdk21:   jdk21 (21.x)
```

---

## Act 1: The Acquired Company

**Story:** Liberty acquired a company running Tomcat 9 + JDK 21. This is what they inherited.

**Talking point:** _"This is the legacy stack your team just acquired. Flox gives you an auditable bill of materials from day one."_

### Commands

```bash
# Show the bill of materials
flox list
```

```bash
# Activate the environment — this sets up CATALINA_BASE, PATH, etc.
eval "$(flox activate)"
```

```bash
# Deploy the custom webapp (shows live Tomcat/JDK versions in the browser)
cp -r webapp/sample "$CATALINA_BASE/webapps/sample"
```

```bash
# Start Tomcat
catalina.sh start
```

**Browser moment:** Open [http://localhost:8080/sample/](http://localhost:8080/sample/) — the page displays the live Tomcat and JDK versions, color-coded orange for the legacy stack. This is the version fingerprint that will visually change during upgrade and rollback.

```bash
# Verify from the command line
curl -s http://localhost:8080/sample/ | head -5
```

```bash
# Show versions
catalina.sh version 2>/dev/null | grep 'Server number'
java -version 2>&1 | head -1
```

**Talking point:** _"Security says: you have 60 days to upgrade. With traditional tooling, that's a week-long project. With Flox, watch this."_

```bash
# Stop Tomcat before the upgrade
catalina.sh stop
```

---

## Act 2: Day 60 — Security Says Upgrade

**Story:** The 60-day security window is closing. Time to upgrade Tomcat 9 → 11 and JDK 21 → 25.

**Talking point:** _"The 60-day upgrade treadmill is the #1 pain point for teams managing thousands of apps. Flox turns it into a one-liner."_

### Commands

```bash
# Export current manifest
flox list -c > /tmp/manifest-upgrade.toml

# Swap packages in the manifest
sed \
  -e 's/tomcat9.pkg-path = "tomcat9"/tomcat11.pkg-path = "tomcat11"/' \
  -e 's/jdk21.pkg-path = "jdk21"/jdk25.pkg-path = "jdk25"/' \
  -e 's/jdk21.priority = 1/jdk25.priority = 1/' \
  /tmp/manifest-upgrade.toml > /tmp/manifest-upgraded.toml

# Show the diff
diff /tmp/manifest-upgrade.toml /tmp/manifest-upgraded.toml || true
```

**Talking point:** _"Two lines changed in a declarative manifest. That's the entire upgrade."_

```bash
# Apply the upgrade
flox edit -f /tmp/manifest-upgraded.toml
```

```bash
# Verify updated bill of materials
flox list
```

```bash
# Show the lock file changed — this is your audit trail
git diff --stat .flox/env/manifest.lock
```

**Talking point:** _"The lock file diff is your compliance artifact. Every hash, every version, tracked in git."_

```bash
# Commit the upgrade
git add .
git commit -m 'feat: upgrade to tomcat11 + jdk25 (60-day security compliance)'
```

```bash
# Re-activate and deploy
eval "$(flox activate)"
cp -r webapp/sample "$CATALINA_BASE/webapps/sample"
catalina.sh start
```

**Browser moment:** Refresh [http://localhost:8080/sample/](http://localhost:8080/sample/) — the same page now shows Tomcat 11 + JDK 25, color-coded green for the upgraded stack. The version change is immediately visible.

```bash
# Verify versions
catalina.sh version 2>/dev/null | grep 'Server number'
java -version 2>&1 | head -1
```

```bash
# Stop Tomcat
catalina.sh stop
```

---

## Act 3: It Broke in Production

**Story:** QA found a compatibility issue. Production is down. Rollback needed NOW.

**Talking point:** _"With traditional infra, rollback means rebuild, redeploy, pray. With Flox, it's a pointer swap."_

### Commands

```bash
# Roll back to the previous environment — one command
git checkout HEAD~1 -- .flox/env/
```

```bash
# Verify we're back to Tomcat 9
flox list
```

**Talking point:** _"That's it. One command. The old binaries are still in the Nix store — no redownload, no recompilation."_

```bash
# Re-activate and deploy
eval "$(flox activate)"
cp -r webapp/sample "$CATALINA_BASE/webapps/sample"
catalina.sh start
```

**Browser moment:** Refresh [http://localhost:8080/sample/](http://localhost:8080/sample/) — the page is back to orange/legacy, showing Tomcat 9 + JDK 21. The rollback is visually confirmed.

```bash
# Verify we're back on Tomcat 9
catalina.sh version 2>/dev/null | grep 'Server number'
java -version 2>&1 | head -1
```

**Talking point:** _"Rollback is a metadata change, not a rebuild. Seconds, not hours. Both versions coexist in the Nix store."_

```bash
catalina.sh stop
```

---

## Act 4: Cross-Platform Consistency

**Story:** Devs on MacBooks, production on AWS EC2 Linux. "Works on my machine" is not acceptable for 5500 apps.

**Talking point:** _"The lock file pins exact versions for all four platforms. Your Mac dev laptop and your Linux EC2 instance get the exact same stack."_

### Commands

```bash
# Show all platforms covered in the lock file
grep '"system"' .flox/env/manifest.lock | sort -u
```

Expected output — four platforms:

```
"system": "aarch64-darwin"
"system": "aarch64-linux"
"system": "x86_64-darwin"
"system": "x86_64-linux"
```

**Talking point:** _"To share with the team: `flox push` to FloxHub, teammates `flox pull`. Or just commit `.flox/env/` to your repo. `git clone` + `flox activate` = identical environment everywhere."_

---

## Act 5: No More Host Dependencies

**Story:** K8s host dependencies, mount points, host packages — "move this container and everything breaks."

**Talking point:** _"With Flox, everything resolves to the Nix store. Zero coupling to the host OS."_

### Commands

```bash
eval "$(flox activate)"
```

```bash
# Show where Java actually lives
which java
readlink -f $(which java)
```

```bash
# Show where Tomcat actually lives
which catalina.sh
readlink -f $(which catalina.sh)
```

**Talking point:** _"See the `/nix/store/` paths? Nothing in `/usr/local`. No host packages. The hash in the path guarantees: exact same binary on every machine, no dependency conflicts, zero host coupling. Move this to any container, any VM — the environment travels with it."_

---

## Cleanup

```bash
# Stop Tomcat if running
catalina.sh stop 2>/dev/null || true
pkill -f "org.apache.catalina" 2>/dev/null || true

# Restore environment to original state
git checkout HEAD -- .flox/env/
```

---

## Recovery

If something goes wrong mid-demo:

```bash
# Kill any running Tomcat
pkill -f "org.apache.catalina" 2>/dev/null || true

# Reset the environment files
git checkout HEAD -- .flox/env/

# Verify clean state
flox list
```

If port 8080 is stuck:

```bash
lsof -ti:8080 | xargs kill -9 2>/dev/null || true
```

---

## Talking Points Reference Card

| Pain Point | Flox Answer | Demo Moment |
|---|---|---|
| 60-day upgrade cycles | Declarative manifest swap — one command | Act 2: `flox edit -f` |
| Slow, risky rollbacks | Pointer swap via `git checkout` — seconds, not hours | Act 3: `git checkout HEAD~1 -- .flox/env/` |
| Compliance / audit trail | Lock file diffs in git — every hash tracked | Act 2: `git diff --stat .flox/env/manifest.lock` |
| "Works on my machine" | Lock file pins 4 platforms (macOS + Linux, ARM + x86) | Act 4: `grep '"system"' manifest.lock` |
| Host dependency hell | Everything in `/nix/store/` — zero host coupling | Act 5: `readlink -f $(which java)` |
| Bill of materials | `flox list` — auditable, versioned, reproducible | Act 1: `flox list` |
