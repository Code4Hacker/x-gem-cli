#!/bin/bash
# xgem flutter command group. iOS builds delegate to lib/ios.sh for
# SwiftPM-aware deployment-target reconciliation before ever calling
# `flutter build ios`.
#
# Depends on lib/logger.sh, lib/utils.sh, lib/ios.sh.

cmd_flutter_hard_clean() {
    log_info "Cleaning Flutter project..."
    rm -f pubspec.lock
    flutter clean

    if [ -d ios ]; then
        log_info "Removing iOS ephemeral files..."
        rm -rf ios/Flutter/ephemeral
        (
            cd ios || exit 1
            if [ -f Podfile ]; then
                log_info "CocoaPods detected - removing lock and Pods..."
                rm -f Podfile.lock
                rm -rf Pods
            else
                log_info "Swift Package Manager detected - resolving packages..."
                xcodebuild -resolvePackageDependencies -workspace Runner.xcworkspace -scheme Runner
            fi
        )
    else
        log_info "No iOS target found, skipping iOS-specific cleanup."
    fi

    log_info "Getting Flutter packages..."
    flutter pub get

    if [ -f ios/Podfile ]; then
        log_info "Installing iOS Pods..."
        ( cd ios || exit 1; pod install )
    fi

    log_info "Running Flutter..."
    flutter run -v
}

cmd_flutter_build_runner() {
    log_info "Running Flutter Build Runner..."
    local verbose_choice
    read -r -p "Run in verbose mode? (Y/n): " verbose_choice
    verbose_choice=${verbose_choice:-Y}

    local -a cmd=(flutter pub run build_runner build --delete-conflicting-outputs)
    if [[ "$verbose_choice" == "Y" || "$verbose_choice" == "y" ]]; then
        cmd+=(-v)
    fi
    log_info "Executing: ${cmd[*]}"
    "${cmd[@]}"
}

_flutter_pubspec_version() {
    [ -f pubspec.yaml ] || return 1
    grep '^version:' pubspec.yaml | head -n 1 | awk '{print $2}'
}

_flutter_build_ios() {
    local build_name=$1
    local build_number=$2
    local mode=$3

    require_cmd xcodebuild "iOS builds require Xcode's command-line tools."

    # Must run pub get BEFORE reconciling: the required-deployment-target
    # check reads .dart_tool/package_config.json, and that file only
    # reflects the plugin versions actually in use after a fresh pub get.
    # Reconciling against a stale package_config.json can silently pass a
    # check that the real, just-resolved dependency graph would fail.
    log_info "Regenerating dependencies..."
    flutter pub get

    log_info "Reconciling iOS deployment target against resolved SwiftPM plugins..."
    if ! ios_reconcile_deployment_target "."; then
        die "iOS deployment target could not be reconciled; aborting before build."
    fi

    if ios_project_uses_pods "."; then
        log_info "CocoaPods detected - installing pods..."
        ( cd ios || exit 1; pod install )
    elif ios_project_uses_spm "."; then
        log_info "Swift Package Manager detected - resolving packages..."
        xcodebuild -resolvePackageDependencies -workspace ios/Runner.xcworkspace -scheme Runner
    fi

    log_info "Initializing Flutter iOS Build ($mode)..."
    local log_file
    log_file=$(mktemp)
    if ! flutter build ios "$mode" "--build-name=$build_name" "--build-number=$build_number" > "$log_file" 2>&1; then
        log_error "Build FAILED"
        cat "$log_file"
        die "flutter build ios failed" "$?"
    fi
    log_success "Build complete."

    log_info "Archiving for Xcode Organizer..."
    local archive_date archive_time archive_dir archive_path
    archive_date=$(date +%Y-%m-%d)
    archive_time=$(date +%H.%M.%S)
    archive_dir="$HOME/Library/Developer/Xcode/Archives/$archive_date"
    mkdir -p "$archive_dir"
    archive_path="$archive_dir/Runner $archive_time.xcarchive"

    local -a archive_cmd=(xcodebuild -workspace ios/Runner.xcworkspace \
        -scheme Runner \
        -sdk iphoneos \
        -configuration Release \
        archive \
        -archivePath "$archive_path" \
        "BUILD_NUMBER=$build_number" \
        "MARKETING_VERSION=$build_name" \
        -allowProvisioningUpdates)

    if ! "${archive_cmd[@]}" > "$log_file" 2>&1; then
        # Static pre-checks can miss cases the real SwiftPM resolution
        # catches (different plugin manifest layouts, symlinked package
        # dirs, etc.) — Xcode's own error is authoritative, so parse it
        # directly and retry once before giving up.
        local retry_required
        retry_required=$(ios_parse_required_from_build_log "$log_file")
        if [ -n "$retry_required" ]; then
            log_warn "Archive failed on a SwiftPM platform-version mismatch Xcode reports directly (requires iOS $retry_required). Retrying with that applied..."
            ios_pbxproj_patch_deployment_target "$retry_required" "."
            ios_regenerate_generated_package "."
            local regenerated
            regenerated=$(ios_generated_package_target ".")
            if [ -z "$regenerated" ] || _ios_ver_lt "$regenerated" "$retry_required"; then
                ios_patch_generated_package_target "$retry_required" "."
            fi

            if ! "${archive_cmd[@]}" > "$log_file" 2>&1; then
                log_error "Archive FAILED again after retry"
                cat "$log_file"
                die "xcodebuild archive failed" "$?"
            fi
        else
            log_error "Archive FAILED"
            cat "$log_file"
            die "xcodebuild archive failed" "$?"
        fi
    fi
    log_success "Archive created at: $archive_path"

    if has_cmd osascript; then
        osascript -e '
            tell application "Xcode" to activate
            delay 1
            tell application "System Events" to tell process "Xcode"
                click menu item "Organizer" of menu "Window" of menu bar 1
            end tell
        ' 2>/dev/null
    fi
    open ios/Runner.xcworkspace 2>/dev/null
}

cmd_flutter_build() {
    echo -e "\033[1;34m--- Flutter Build Orchestrator ---\033[0m"

    local current_name="" current_num="" current_full
    if current_full=$(_flutter_pubspec_version) && [ -n "$current_full" ]; then
        current_name=${current_full%%+*}
        current_num=${current_full#*+}
        [ "$current_name" = "$current_num" ] && current_num="1"
        log_info "Current pubspec.yaml version: $current_full"
    fi

    local build_name build_number is_release
    read -r -p "Enter build version name [${current_name:-1.0.0}]: " build_name
    build_name=${build_name:-${current_name:-1.0.0}}

    read -r -p "Enter build number [${current_num:-1}]: " build_number
    build_number=${build_number:-${current_num:-1}}

    read -r -p "Is this a release build? (Y/n) [default: y]: " is_release
    is_release=${is_release:-y}

    if [ -f pubspec.yaml ]; then
        local new_version="${build_name}+${build_number}"
        log_success "Updating pubspec.yaml to version: $new_version"
        local tmp
        tmp=$(mktemp)
        sed -e "s/^version:.*/version: $new_version/" pubspec.yaml > "$tmp" && mv "$tmp" pubspec.yaml
    fi

    echo ""
    echo "Select Target Platform:"
    echo "1) APK (Android)"
    echo "2) iOS"
    echo "3) macOS"
    echo "4) Windows"
    echo "5) Linux"
    local platform_choice
    read -r -p "Choose [1-5]: " platform_choice
    if ! [[ "$platform_choice" =~ ^[1-5]$ ]]; then
        die "Invalid platform choice '$platform_choice'."
    fi

    local mode="--release"
    [[ "$is_release" == "n" || "$is_release" == "N" ]] && mode="--debug"

    if [ "$platform_choice" -eq 2 ]; then
        _flutter_build_ios "$build_name" "$build_number" "$mode"
        return
    fi

    log_info "Initializing Flutter Build ($mode) for version $build_name+$build_number..."
    case $platform_choice in
        1) flutter build apk "$mode" "--build-name=$build_name" "--build-number=$build_number" ;;
        3) flutter build macos "$mode" "--build-name=$build_name" "--build-number=$build_number" ;;
        4) flutter build windows "$mode" "--build-name=$build_name" "--build-number=$build_number" ;;
        5) flutter build linux "$mode" "--build-name=$build_name" "--build-number=$build_number" ;;
    esac
}

# xgem run flutter <script> — native dispatch, called before falling back to
# any generated .xgem-automate/flutter/<script>.sh template.
flutter_native_command_exists() {
    local script=$1
    case "$script" in
        hard-clean|build|build-runner) return 0 ;;
        *) return 1 ;;
    esac
}

flutter_run_native_command() {
    local script=$1
    case "$script" in
        hard-clean)   cmd_flutter_hard_clean ;;
        build)        cmd_flutter_build ;;
        build-runner) cmd_flutter_build_runner ;;
        *) die "No native flutter command for '$script'." ;;
    esac
}
