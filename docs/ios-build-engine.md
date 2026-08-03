# The iOS Build Engine

## The problem

Flutter auto-generates a wrapper Swift package, `FlutterGeneratedPluginSwiftPackage`, that aggregates your plugins' Swift Package Manager (SPM) dependencies. Its declared minimum iOS platform can desync from your app's own `IPHONEOS_DEPLOYMENT_TARGET` — **independently, even when your app's own deployment target is already high enough**. This is a confirmed, currently-open upstream Flutter bug: [flutter/flutter#186804](https://github.com/flutter/flutter/issues/186804), [#189422](https://github.com/flutter/flutter/issues/189422), [#162072](https://github.com/flutter/flutter/issues/162072).

The symptom looks like this:

```
error: The package product 'some-plugin' requires minimum platform version 15.0
for the iOS platform, but this target supports 13.0 (in target
'FlutterGeneratedPluginSwiftPackage' from project 'FlutterGeneratedPluginSwiftPackage')
```

A single `sed` patch to `project.pbxproj`'s `IPHONEOS_DEPLOYMENT_TARGET` doesn't reliably fix this, for two reasons:

1. There are multiple `IPHONEOS_DEPLOYMENT_TARGET` entries across Debug/Release/Profile × Runner/RunnerTests — patching one doesn't patch them all.
2. Even a fully-correct patch to your app's own target doesn't force Flutter to regenerate `FlutterGeneratedPluginSwiftPackage` — and even when it does regenerate, the upstream bug means it can still come back with the old, wrong value.

## What xgem does instead

`xgem run flutter build` (iOS target) or `xgem doctor ios`:

1. **Detects** whether the project uses CocoaPods, SwiftPM, or both (and warns if it's a genuine mix, since Flutter's own docs note that can cause dependency cycles).
2. **Computes the actual required deployment target** from your *resolved* SPM plugins — not a guessed/hardcoded value. It scans `ios/Flutter/ephemeral/Packages/.packages/<plugin>/`, which `flutter pub get` itself populates with each SPM-enabled plugin — the authoritative, already-resolved location, rather than reconstructing plugin paths from `.dart_tool/package_config.json` (which turned out to be unreliable: plugin directories there are frequently symlinks into your pub-cache, and different plugins declare their platform floor with either SPM syntax — `.iOS(.v15)` or `.iOS("15.0")` — both are handled).
3. **Reads the actual current deployment target per build configuration** via `xcodebuild -showBuildSettings` (not by grepping the pbxproj file) — this reflects any xcconfig overrides too, and is resilient to Xcode versions that added confusing new build-setting keys (a real one exists: `DEPLOYMENT_TARGET_SETTING_NAME`, whose *value* is literally the string `IPHONEOS_DEPLOYMENT_TARGET`, which an earlier, less careful version of this engine mistook for the deployment target itself).
4. **Checks the generated package independently** — because the bug is exactly that `FlutterGeneratedPluginSwiftPackage`'s own declared platform can be stuck at an old value regardless of what your app's pbxproj already says. Checking only the pbxproj target (an earlier version of this engine did only that) misses this case entirely.
5. **Shows a plan and asks for confirmation** (unless `--yes`/`--dry-run`) before patching *every* `IPHONEOS_DEPLOYMENT_TARGET` occurrence in `project.pbxproj`.
6. **Forces a clean regeneration** (clears `ios/Flutter/ephemeral`, re-runs `flutter pub get`) and verifies the regenerated package now matches.
7. **If it still doesn't** (the upstream bug, still open as of this writing), patches the generated package directly as a documented, loudly-logged last resort — never silently.
8. **As a safety net**, if the archive still fails with Xcode's own `"requires minimum platform version X"` error despite all of the above, xgem parses that directly (Xcode always computes the true requirement correctly) and retries the fix + archive once automatically, rather than trusting its own static analysis to have caught everything.

## Standalone diagnosis

`xgem doctor ios [path]` reports every piece of the above without doing a build: CocoaPods/SwiftPM detection, per-configuration deployment targets, the computed requirement, and what the generated package currently declares — useful for understanding *why* a build might fail before you even attempt one.
