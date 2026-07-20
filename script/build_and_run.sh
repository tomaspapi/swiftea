#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Swiftea"
SCHEME_NAME="Swiftea"
CONFIGURATION="Debug"
BUNDLE_ID="com.tom.swiftea"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_SPEC="$ROOT_DIR/project.yml"
PROJECT_FILE="$ROOT_DIR/Swiftea.xcodeproj"
PBXPROJ_FILE="$PROJECT_FILE/project.pbxproj"
PREFERRED_DERIVED_DATA_DIR="${TMPDIR%/}/swiftea-deriveddata"
FALLBACK_DERIVED_DATA_DIR="$ROOT_DIR/.deriveddata"
DERIVED_DATA_DIR="$PREFERRED_DERIVED_DATA_DIR"
LEGACY_TEMP_APP_BUNDLE="${TMPDIR%/}/swiftea-dist/$APP_NAME.app"
APP_BUNDLE=""
APP_BINARY=""

run_swift_snippet() {
  /usr/bin/swift -e "$1"
}

update_build_paths() {
  APP_BUNDLE="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION/$APP_NAME.app"
  APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
}

can_write_to_directory() {
  local dir="$1"
  local probe

  mkdir -p "$dir" 2>/dev/null || return 1
  probe="$dir/.swiftea-write-test"
  if ! touch "$probe" >/dev/null 2>&1; then
    return 1
  fi
  rm -f "$probe" 2>/dev/null || true
}

select_derived_data_dir() {
  if can_write_to_directory "$PREFERRED_DERIVED_DATA_DIR"; then
    DERIVED_DATA_DIR="$PREFERRED_DERIVED_DATA_DIR"
  else
    DERIVED_DATA_DIR="$FALLBACK_DERIVED_DATA_DIR"
  fi

  mkdir -p "$DERIVED_DATA_DIR"
  update_build_paths
}

normalize_xcode_project_paths() {
  if [[ ! -f "$PBXPROJ_FILE" ]]; then
    return
  fi

  if [[ ! -w "$PBXPROJ_FILE" ]]; then
    return
  fi

  perl -0pi -e '
    s/path = "\.\.\/\.\.\/\.\.\/\.\.\/Resources\/AppIcon\.icon";/path = Resources\/AppIcon.icon;/g;
    s/path = "\.\.\/\.\.\/\.\.\/\.\.\/Sources";/path = Sources;/g;
    s/path = "\.\.\/\.\.\/\.\.\/\.\.\/Tests";/path = Tests;/g;
  ' "$PBXPROJ_FILE"
}

ensure_xcode_project() {
  if ! command -v xcodegen >/dev/null 2>&1; then
    if [[ ! -d "$PROJECT_FILE" || ! -f "$PBXPROJ_FILE" ]]; then
      echo "xcodegen is required to generate $PROJECT_FILE from $PROJECT_SPEC." >&2
      exit 1
    fi
    return
  fi

  (
    cd "$ROOT_DIR"
    if ! rm -rf "$PROJECT_FILE" 2>/dev/null; then
      if [[ -d "$PROJECT_FILE" && -f "$PBXPROJ_FILE" ]]; then
        echo "warning: Could not regenerate $PROJECT_FILE; using the existing project." >&2
        exit 0
      fi

      echo "Could not remove $PROJECT_FILE and no usable project is available." >&2
      exit 1
    fi

    xcodegen generate --spec "$PROJECT_SPEC"
  )

  normalize_xcode_project_paths
}

build_app() {
  ensure_xcode_project
  mkdir -p "$DERIVED_DATA_DIR"

  xcodebuild \
    -project "$PROJECT_FILE" \
    -scheme "$SCHEME_NAME" \
    -configuration "$CONFIGURATION" \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    CODE_SIGNING_ALLOWED=NO \
    build
}

quit_running_app() {
  APP_BUNDLE_ID="$BUNDLE_ID" run_swift_snippet '
import AppKit
import Foundation

let bundleID = ProcessInfo.processInfo.environment["APP_BUNDLE_ID"]!

func runLoopSlice() {
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
}

var runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
if runningApps.isEmpty {
    exit(0)
}

for app in runningApps {
    app.terminate()
}

let terminateDeadline = Date().addingTimeInterval(3)
while Date() < terminateDeadline {
    runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    if runningApps.isEmpty {
        exit(0)
    }
    runLoopSlice()
}

for app in runningApps {
    app.forceTerminate()
}

let forceDeadline = Date().addingTimeInterval(2)
while Date() < forceDeadline {
    if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
        exit(0)
    }
    runLoopSlice()
}

fputs("Failed to close \(bundleID)\n", stderr)
exit(1)
'
}

remove_legacy_temp_app_bundle() {
  if [[ "$LEGACY_TEMP_APP_BUNDLE" == "$APP_BUNDLE" ]]; then
    return
  fi

  if [[ -d "$LEGACY_TEMP_APP_BUNDLE" ]]; then
    rm -rf "$LEGACY_TEMP_APP_BUNDLE"
  fi
}

remove_previous_build_app_bundle() {
  if [[ -n "$APP_BUNDLE" && -d "$APP_BUNDLE" ]]; then
    rm -rf "$APP_BUNDLE"
  fi

  local app_intermediates="$DERIVED_DATA_DIR/Build/Intermediates.noindex/$APP_NAME.build"
  if [[ -d "$app_intermediates" ]]; then
    rm -rf "$app_intermediates"
  fi
}

open_app() {
  APP_TO_OPEN="$APP_BUNDLE" APP_LAUNCH_ARGUMENTS="${SWIFTEA_APP_ARGUMENTS:-}" run_swift_snippet '
import AppKit
import Foundation

let appPath = ProcessInfo.processInfo.environment["APP_TO_OPEN"]!
let launchArguments = ProcessInfo.processInfo.environment["APP_LAUNCH_ARGUMENTS"] ?? ""
let activateOnLaunch = ProcessInfo.processInfo.environment["SWIFTEA_ACTIVATE_ON_LAUNCH"] == "1"
let appURL = URL(fileURLWithPath: appPath)
let configuration = NSWorkspace.OpenConfiguration()
configuration.activates = activateOnLaunch
configuration.environment = ProcessInfo.processInfo.environment

if !launchArguments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
    configuration.arguments = launchArguments.split(separator: " ").map(String.init)
}

let semaphore = DispatchSemaphore(value: 0)
var openError: Error?

NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
    openError = error
    semaphore.signal()
}

if semaphore.wait(timeout: .now() + 10) == .timedOut {
    fputs("Timed out while opening \(appPath)\n", stderr)
    exit(1)
}

if let openError {
    fputs("Failed to open \(appPath): \(openError.localizedDescription)\n", stderr)
    exit(1)
}
'
}

verify_app_running() {
  APP_BUNDLE_ID="$BUNDLE_ID" run_swift_snippet '
import AppKit

let bundleID = ProcessInfo.processInfo.environment["APP_BUNDLE_ID"]!
exit(NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty ? 1 : 0)
'
}

select_derived_data_dir
quit_running_app
remove_legacy_temp_app_bundle
remove_previous_build_app_bundle
build_app

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    verify_app_running
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
