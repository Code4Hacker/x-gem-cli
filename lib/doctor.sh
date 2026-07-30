#!/bin/bash
# xgem doctor — environment + feature detection.
# Never assumes; always probes for the actual capability/version/config present.
# Depends on lib/logger.sh, lib/utils.sh (and, for `doctor ios`, lib/ios.sh).

doctor_tool_version() {
    local name=$1
    local version_flag=${2:---version}
    if has_cmd "$name"; then
        "$name" $version_flag 2>&1 | head -1
    else
        echo "not found"
    fi
}

# flutter_supports_flag <command> <flag>
# Feature detection instead of version-gating: probe --help output for the
# flag rather than assuming it exists as of some Flutter version.
flutter_supports_flag() {
    local subcmd=$1
    local flag=$2
    has_cmd flutter || return 1
    flutter "$subcmd" --help 2>/dev/null | grep -q -- "$flag"
}

flutter_config_spm_enabled() {
    has_cmd flutter || { echo "unknown (flutter not found)"; return; }
    local line
    # Anchored to "enable-swift-package-manager:" (the current-value line)
    # so this doesn't instead match the "--[no-]enable-swift-package-manager"
    # flag-syntax help line that `flutter config` also prints.
    line=$(flutter config 2>/dev/null | grep -im1 -E '^[[:space:]]*enable-swift-package-manager:')
    if [ -z "$line" ]; then
        echo "unknown (not reported by this Flutter version)"
    else
        echo "$line" | sed -E 's/^[[:space:]]*//'
    fi
}

doctor_print_general() {
    echo -e "\033[1;36m=== xgem doctor ===\033[0m"
    echo "OS:              $(detect_os)"
    echo "Arch:            $(detect_arch)$( is_apple_silicon && echo ' (Apple Silicon)' )"
    echo "git:             $(doctor_tool_version git)"
    echo "flutter:         $(doctor_tool_version flutter)"
    echo "dart:            $(doctor_tool_version dart)"
    echo "node:            $(doctor_tool_version node)"
    echo "python3:         $(doctor_tool_version python3)"
    echo "go:              $(doctor_tool_version go version)"
    echo "cargo:           $(doctor_tool_version cargo)"
    echo "docker:          $(doctor_tool_version docker)"
    if [ "$(detect_os)" = "darwin" ]; then
        echo "xcodebuild:      $(doctor_tool_version xcodebuild -version)"
        echo "pod (CocoaPods): $(doctor_tool_version pod)"
    fi
}

# doctor_print_ios [project_dir]
doctor_print_ios() {
    local project_dir=${1:-.}
    echo -e "\033[1;36m=== xgem doctor ios ===\033[0m"

    if [ "$(detect_os)" != "darwin" ]; then
        log_warn "iOS builds require macOS. Detected OS: $(detect_os)."
    fi

    echo "flutter:                 $(doctor_tool_version flutter)"
    echo "xcodebuild:              $(doctor_tool_version xcodebuild -version)"
    echo "CocoaPods:                $(doctor_tool_version pod)"
    echo "SPM enabled (global cfg): $(flutter_config_spm_enabled)"

    if [ ! -d "$project_dir/ios" ]; then
        log_warn "No ios/ directory found under '$project_dir' — not a Flutter project with an iOS target, or run this from the project root."
        return 0
    fi

    local uses_pods=no uses_spm=no
    ios_project_uses_pods "$project_dir" && uses_pods=yes
    ios_project_uses_spm "$project_dir" && uses_spm=yes
    echo "Project uses CocoaPods:  $uses_pods"
    echo "Project uses SwiftPM:    $uses_spm"
    if [ "$uses_pods" = "yes" ] && [ "$uses_spm" = "yes" ]; then
        log_warn "Mixed CocoaPods + SwiftPM detected. Flutter's own docs note this can cause complex dependency cycles and build errors — prefer migrating fully to SPM where all plugins support it."
    fi

    for cfg in Debug Release Profile; do
        local t
        t=$(ios_deployment_target_for_config "$cfg" "$project_dir" 2>/dev/null)
        echo "Deployment target [$cfg]: ${t:-unknown}"
    done

    local required generated
    required=$(ios_required_spm_deployment_target "$project_dir" 2>/dev/null)
    if [ -n "$required" ]; then
        echo "Required by resolved SwiftPM plugins: $required"
    else
        echo "Required by resolved SwiftPM plugins: unable to determine (run 'flutter pub get' first, or no SPM plugins declare an explicit floor)"
    fi

    if [ "$uses_spm" = "yes" ]; then
        generated=$(ios_generated_package_target "$project_dir" 2>/dev/null)
        echo "FlutterGeneratedPluginSwiftPackage declares: ${generated:-unknown}"
        if [ -n "$required" ] && [ -n "$generated" ] && _ios_ver_lt "$generated" "$required"; then
            log_warn "This is stale — it declares iOS $generated but plugins need $required. This can happen even when your app's own deployment target is already high enough; 'xgem run flutter build' will detect and fix this."
        fi
    fi

    if [ "$uses_spm" = "yes" ]; then
        ios_known_issue_check
    fi
}

# xgem doctor [ios]
cmd_doctor() {
    case "${1:-}" in
        ios) doctor_print_ios "${2:-.}" ;;
        "")  doctor_print_general ;;
        *)   die "Unknown doctor target '$1'. Usage: xgem doctor [ios]" ;;
    esac
}
