#!/bin/bash
# xgem iOS build engine — redesigned to handle Swift Package Manager (SPM)
# reliably, not just CocoaPods.
#
# Background (why this exists): Flutter auto-generates a wrapper Swift
# package, FlutterGeneratedPluginSwiftPackage, that aggregates plugin SPM
# dependencies. Its declared minimum iOS platform does not always stay in
# sync with the app's IPHONEOS_DEPLOYMENT_TARGET in project.pbxproj — a
# confirmed, currently-open upstream Flutter bug (flutter/flutter#186804,
# #189422, #162072). A single sed patch to pbxproj alone does not fix this
# reliably: (a) pbxproj has multiple IPHONEOS_DEPLOYMENT_TARGET entries
# across Debug/Release/Profile x Runner/RunnerTests, and (b) even a fully
# correct pbxproj patch doesn't force-regenerate the generated package.
#
# This engine: detects the actual required deployment target from resolved
# SPM plugin manifests (instead of hardcoding a guess), patches every
# pbxproj occurrence, forces regeneration, verifies the regenerated package
# matches, and falls back to directly patching the generated package as a
# documented last resort if the upstream desync bug is still present.
#
# Depends on lib/logger.sh, lib/utils.sh.

ios_pbxproj_path() {
    local project_dir=${1:-.}
    echo "$project_dir/ios/Runner.xcodeproj/project.pbxproj"
}

ios_project_uses_pods() {
    local project_dir=${1:-.}
    [ -f "$project_dir/ios/Podfile" ]
}

# ios_project_uses_spm: authoritative signal is a reference to the generated
# aggregate package inside the Xcode project itself, not just Flutter's
# global config toggle (which reflects intent, not what's actually wired
# into *this* project).
ios_project_uses_spm() {
    local project_dir=${1:-.}
    local pbxproj
    pbxproj=$(ios_pbxproj_path "$project_dir")
    [ -f "$pbxproj" ] && grep -q "FlutterGeneratedPluginSwiftPackage" "$pbxproj"
}

# ios_deployment_target_for_config <Debug|Release|Profile> [project_dir]
# Authoritative: asks Xcode itself via -showBuildSettings rather than
# grepping pbxproj, so it reflects any xcconfig overrides too. Falls back
# to the pbxproj's own declared value if xcodebuild isn't available.
ios_deployment_target_for_config() {
    local config=$1
    local project_dir=${2:-.}
    local -a xcb_args=()

    if [ -f "$project_dir/ios/Runner.xcworkspace/contents.xcworkspacedata" ]; then
        xcb_args=(-workspace "$project_dir/ios/Runner.xcworkspace" -scheme Runner)
    elif [ -d "$project_dir/ios/Runner.xcodeproj" ]; then
        xcb_args=(-project "$project_dir/ios/Runner.xcodeproj" -target Runner)
    else
        return 1
    fi

    if has_cmd xcodebuild; then
        local value
        value=$(xcodebuild -showBuildSettings "${xcb_args[@]}" -configuration "$config" 2>/dev/null \
            | grep -m1 'IPHONEOS_DEPLOYMENT_TARGET' | awk '{print $NF}')
        [ -n "$value" ] && { echo "$value"; return 0; }
    fi

    log_debug "xcodebuild unavailable or gave no result; falling back to pbxproj grep for $config."
    ios_pbxproj_current_max_target "$project_dir"
}

ios_pbxproj_current_max_target() {
    local project_dir=${1:-.}
    local pbxproj
    pbxproj=$(ios_pbxproj_path "$project_dir")
    [ -f "$pbxproj" ] || return 1
    grep -oE 'IPHONEOS_DEPLOYMENT_TARGET = [0-9]+(\.[0-9]+)?' "$pbxproj" \
        | grep -oE '[0-9]+(\.[0-9]+)?' \
        | sort -g | tail -1
}

# ios_required_spm_deployment_target [project_dir]
# Reads .dart_tool/package_config.json (written by `flutter pub get`) to
# find every resolved package's own ios/Package.swift, and returns the
# highest .iOS(.vNN) platform floor declared across them. This replaces
# hardcoding a guessed value (e.g. "15.0") with an actual measurement of
# what the resolved dependency graph requires.
ios_required_spm_deployment_target() {
    local project_dir=${1:-.}
    local pkg_config="$project_dir/.dart_tool/package_config.json"

    [ -f "$pkg_config" ] || { log_debug "No .dart_tool/package_config.json — run flutter pub get first."; return 1; }
    has_cmd python3 || { log_debug "python3 not found; cannot parse package_config.json."; return 1; }

    python3 - "$pkg_config" <<'PYEOF'
import json, os, re, sys

pkg_config_path = sys.argv[1]
with open(pkg_config_path) as f:
    data = json.load(f)

base_dir = os.path.dirname(os.path.abspath(pkg_config_path))
max_target = 0.0

for pkg in data.get("packages", []):
    root_uri = pkg.get("rootUri", "")
    if root_uri.startswith("file://"):
        root = root_uri[len("file://"):]
    else:
        root = os.path.normpath(os.path.join(base_dir, root_uri))

    manifest = os.path.join(root, "ios", "Package.swift")
    if not os.path.isfile(manifest):
        continue
    try:
        with open(manifest, "r", errors="ignore") as mf:
            content = mf.read()
    except OSError:
        continue

    for m in re.finditer(r"\.iOS\(\.v(\d+(?:_\d+)?)\)", content):
        try:
            fv = float(m.group(1).replace("_", "."))
        except ValueError:
            continue
        max_target = max(max_target, fv)

if max_target > 0:
    print(max_target)
PYEOF
}

# ios_pbxproj_patch_deployment_target <new_target> [project_dir]
# Patches EVERY IPHONEOS_DEPLOYMENT_TARGET occurrence (all configs, all
# targets), unlike a single-match sed. Keeps a timestamped backup.
ios_pbxproj_patch_deployment_target() {
    local new_target=$1
    local project_dir=${2:-.}
    local pbxproj
    pbxproj=$(ios_pbxproj_path "$project_dir")
    [ -f "$pbxproj" ] || die "project.pbxproj not found at $pbxproj"

    local backup="${pbxproj}.xgem-bak-$(date +%Y%m%d%H%M%S)"
    cp "$pbxproj" "$backup"
    log_debug "Backed up pbxproj to $backup"

    local tmp
    tmp=$(mktemp)
    sed -E "s/(IPHONEOS_DEPLOYMENT_TARGET = )[0-9]+(\.[0-9]+)?;/\1${new_target};/g" "$pbxproj" > "$tmp"
    mv "$tmp" "$pbxproj"

    local count
    count=$(grep -c "IPHONEOS_DEPLOYMENT_TARGET = ${new_target};" "$pbxproj")
    log_success "Patched $count IPHONEOS_DEPLOYMENT_TARGET occurrence(s) in project.pbxproj to $new_target."
}

# Locates the generated aggregate package. The exact path has moved across
# Flutter releases, so this feature-detects it via `find` rather than
# assuming a single fixed location.
ios_generated_package_swift_path() {
    local project_dir=${1:-.}
    local guess="$project_dir/ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift"
    if [ -f "$guess" ]; then
        echo "$guess"
        return 0
    fi
    find "$project_dir/ios" -maxdepth 6 -type f -name "Package.swift" \
        -path "*FlutterGeneratedPluginSwiftPackage*" 2>/dev/null | head -1
}

ios_generated_package_target() {
    local project_dir=${1:-.}
    local pkg
    pkg=$(ios_generated_package_swift_path "$project_dir")
    [ -n "$pkg" ] && [ -f "$pkg" ] || return 1
    grep -oE '\.iOS\(\.v[0-9_]+\)' "$pkg" | head -1 | grep -oE '[0-9_]+' | tr '_' '.'
}

# Last-resort workaround for the still-open upstream desync bug: directly
# patch the generated package's platform declaration. Always logged loudly
# — this is a documented workaround for a known bug, never a silent hack.
ios_patch_generated_package_target() {
    local new_target=$1
    local project_dir=${2:-.}
    local pkg
    pkg=$(ios_generated_package_swift_path "$project_dir")
    if [ -z "$pkg" ] || [ ! -f "$pkg" ]; then
        log_warn "Could not locate FlutterGeneratedPluginSwiftPackage/Package.swift to patch."
        return 1
    fi

    log_warn "Working around known Flutter SPM bug (flutter/flutter#186804): the regenerated package still doesn't match your deployment target, so patching it directly."
    local token=${new_target//./_}
    local tmp
    tmp=$(mktemp)
    sed -E "s/\.iOS\(\.v[0-9_]+\)/.iOS(.v${token})/g" "$pkg" > "$tmp"
    mv "$tmp" "$pkg"
    log_success "Patched generated package platform to iOS $new_target."
}

ios_regenerate_generated_package() {
    local project_dir=${1:-.}
    log_info "Clearing ephemeral iOS config to force a clean regeneration..."
    rm -rf "$project_dir/ios/Flutter/ephemeral"
    ( cd "$project_dir" && flutter pub get )
}

ios_known_issue_check() {
    log_warn "Known upstream issue (flutter/flutter#186804, #189422, #162072): FlutterGeneratedPluginSwiftPackage's deployment target can desync from your app's IPHONEOS_DEPLOYMENT_TARGET. Currently open — xgem detects and works around it automatically below."
}

# ios_reconcile_deployment_target [project_dir]
# The core "self-healing" step: detect a required-vs-current mismatch, plan
# the fix, confirm (unless --yes/--dry-run), apply, regenerate, verify, and
# fall back to the documented workaround if the upstream bug is still biting.
# Returns 0 if no action was needed or the fix succeeded; 1 if it couldn't
# reconcile and the caller should stop before attempting a build.
ios_reconcile_deployment_target() {
    local project_dir=${1:-.}

    ios_project_uses_spm "$project_dir" || { log_debug "Project does not use SwiftPM; skipping deployment-target reconciliation."; return 0; }

    local required current
    required=$(ios_required_spm_deployment_target "$project_dir")
    current=$(ios_deployment_target_for_config "Release" "$project_dir")

    if [ -z "$required" ]; then
        log_debug "Could not determine a required deployment target from resolved SPM plugins; skipping reconciliation."
        return 0
    fi
    if [ -z "$current" ]; then
        log_warn "Could not determine the project's current deployment target; proceeding without reconciliation."
        return 0
    fi

    ios_known_issue_check

    if awk -v a="$required" -v b="$current" 'BEGIN{exit !(a>b)}'; then
        log_warn "Resolved SwiftPM plugins require iOS $required, but the project targets iOS $current."
        echo "Plan:"
        echo "  1. Set IPHONEOS_DEPLOYMENT_TARGET = $required across every build configuration in project.pbxproj"
        echo "  2. Clear ios/Flutter/ephemeral and re-run 'flutter pub get' to regenerate FlutterGeneratedPluginSwiftPackage"
        echo "  3. Verify the regenerated package declares iOS $required; if it still doesn't (known upstream bug), patch it directly"

        if ! confirm "Apply this fix?"; then
            log_warn "Skipped. The build will likely fail SwiftPM resolution until the deployment target is reconciled manually."
            return 1
        fi

        ios_pbxproj_patch_deployment_target "$required" "$project_dir"
        ios_regenerate_generated_package "$project_dir"

        local regenerated
        regenerated=$(ios_generated_package_target "$project_dir")
        if [ "$regenerated" = "$required" ]; then
            log_success "Generated package now correctly declares iOS $regenerated."
        else
            log_warn "Generated package declares '${regenerated:-unknown}' after regeneration, not $required."
            ios_patch_generated_package_target "$required" "$project_dir"
        fi
    else
        log_debug "Deployment target ($current) already satisfies SwiftPM requirement ($required)."
    fi

    return 0
}
