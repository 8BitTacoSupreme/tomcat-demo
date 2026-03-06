# Bundled Immutable Package Demo — Speaker Notes

**Thesis:** Every app ships with its own bundled invocation environment as an immutable package. The environment tested by the developer is the exact same environment deployed by the operator. It can't be screwed up.

---

## Pre-Demo Checklist

- [ ] Both versions published:
  ```
  flox show 8BitTacoSupreme/tomcat-demo
  # Should show @1.0.0 and @2.0.0
  ```
- [ ] Consumer environment exists at `/tmp/demo-consumer/`:
  ```
  ls /tmp/demo-consumer/.flox/env/manifest.toml
  ```
- [ ] Port 8080 is clear:
  ```
  pkill -f "org.apache.catalina" 2>/dev/null; echo "clear"
  ```
- [ ] You are in the build environment directory:
  ```
  cd ~/tomcatdemo
  ```

---

## Act 1: The Developer Builds

> "Every app ships with its own environment. Let me show you what that means."

**Show the manifest — this is the bill of materials:**
```
cat .flox/env/manifest.toml
```
> "Tomcat 9, JDK 21, and a build definition. The build command is just `make install`. Nothing fancy."

**Build the package:**
```
flox build
```
> "This builds in a Nix sandbox. The output is a single immutable package in the Nix store."

**Inspect the wrapper script:**
```
cat result-tomcat-demo/bin/tomcat-demo
```
> "Notice the shebang — it points to a specific bash in `/nix/store`. Flox auto-wraps built executables with the full build environment."

**Show the bundled environment:**
```
./result-tomcat-demo/bin/tomcat-demo status
```
> "The wrapper discovers java, catalina.sh — all from the bundled build env. Not from your PATH, not from the host. From the package itself."

**Start it and show the browser:**
```
./result-tomcat-demo/bin/tomcat-demo start
open http://localhost:8080/sample/
```
> "TC9, JDK21, orange badge. And look at the Source line — that's the actual Nix store path. That path IS the package."

```
./result-tomcat-demo/bin/tomcat-demo stop
```

---

## Act 2: Publish & Consume v1

> "Now I publish this package to the Flox catalog. Anyone can install it."

**Publish (already done, but show the command):**
```
# Already published, but the command was:
# flox publish
flox show 8BitTacoSupreme/tomcat-demo
```
> "Version 1.0.0 is in the catalog. Now let's switch to the consumer side."

**Switch to consumer environment:**
```
cd /tmp/demo-consumer
cat .flox/env/manifest.toml
```
> "This is a minimal V2 manifest. No tomcat, no jdk — just a bare environment with the outputs feature flag."

**Install v1:**
```
FLOX_FEATURES_OUTPUTS=1 flox install 8BitTacoSupreme/tomcat-demo@1.0.0
```

**Activate and run:**
```
flox activate -- tomcat-demo start
open http://localhost:8080/sample/
```
> "Same TC9, JDK21, orange badge. Same Nix store path. The operator got the exact package the developer built. No Dockerfile, no image registry, no 'works on my machine'."

```
flox activate -- tomcat-demo stop
```

---

## Act 3: Developer Ships v2

> "Now the developer upgrades to Tomcat 11 and JDK 25."

**Back to the build environment — show the diff:**
```
cd ~/tomcatdemo
```
> "In the manifest, we change tomcat9 → tomcat11, jdk21 → jdk25, version 1.0.0 → 2.0.0. That's it."
> "(This was already done and published — both versions are in the catalog.)"

```
flox show 8BitTacoSupreme/tomcat-demo
```
> "Both 1.0.0 and 2.0.0 are published. Two completely different immutable packages."

---

## Act 4: Operator Upgrades

> "The operator upgrades with one command."

**Switch to consumer:**
```
cd /tmp/demo-consumer
FLOX_FEATURES_OUTPUTS=1 flox install 8BitTacoSupreme/tomcat-demo@2.0.0
```

**Run:**
```
flox activate -- tomcat-demo start
open http://localhost:8080/sample/
```
> "Green badge. TC11, JDK25. Different Nix store path — proving it's a completely different immutable package. The operator didn't compile anything. Didn't edit a Dockerfile. Just changed a version number."

```
flox activate -- tomcat-demo stop
```

---

## Act 5: Rollback & Live Build

> "Something breaks in production. Roll back."

```
FLOX_FEATURES_OUTPUTS=1 flox install 8BitTacoSupreme/tomcat-demo@1.0.0
flox activate -- tomcat-demo start
open http://localhost:8080/sample/
```
> "Orange badge. TC9, JDK21. Same Nix store path as Act 2 — the original package never left the store. Rollback is a pointer swap, not a rebuild. Seconds, not hours."

```
flox activate -- tomcat-demo stop
```

**Audit trail:**
```
flox generations
```
> "Every install, upgrade, and rollback is recorded. Full audit trail."

### Live Build (manual, not automated)

> "Let me show you the full build-publish-deploy loop."

1. Edit `webapp/sample/index.jsp` — change the `demoMessage` string
2. Bump version to `2.0.1` in `.flox/env/manifest.toml`
3. Build and publish:
   ```
   cd ~/tomcatdemo
   flox build && flox publish
   ```
4. Consumer upgrades:
   ```
   cd /tmp/demo-consumer
   FLOX_FEATURES_OUTPUTS=1 flox install 8BitTacoSupreme/tomcat-demo@2.0.1
   flox activate -- tomcat-demo start
   open http://localhost:8080/sample/
   ```
> "New message on the page. Same workflow: edit, build, publish, install. The audience sees the update live."

---

## Closing

> "What we showed:"
> - **Developer** builds once → immutable package with bundled environment
> - **Operator** installs from catalog → exact same package, no drift possible
> - **Upgrade** = change version number, one command
> - **Rollback** = change version number back, one command
> - **Audit** = `flox generations` shows every change
> - **No containers, no image registry, no Dockerfile** — just packages

---

## Troubleshooting

**Port 8080 already in use:**
```
pkill -f "org.apache.catalina"
```

**Consumer install fails with "outputs" error:**
Ensure `FLOX_FEATURES_OUTPUTS=1` is set, and the consumer manifest is version 2.

**`flox publish` fails with "dirty tracked files":**
Commit and push all changes before publishing. The git repo must be clean.
