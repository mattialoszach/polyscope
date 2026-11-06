#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${POLYSCOPE_BUILD_DIR:-$PROJECT_ROOT/build}"
APPLICATIONS_DIR="${POLYSCOPE_APPLICATIONS_DIR:-/Applications}"
[[ "$BUILD_DIR" = /* ]] || BUILD_DIR="$PROJECT_ROOT/$BUILD_DIR"
APP_BUNDLE="$BUILD_DIR/Polyscope.app"

die() { printf 'Polyscope: %s\n' "$*" >&2; exit 1; }

require_macos() {
    [[ "$(uname -s)" == Darwin ]] || die "This app requires macOS 11 or newer."
}

require_tools() {
    require_macos
    xcode-select -p >/dev/null 2>&1 || die "Install Apple's tools with: xcode-select --install"
    command -v cmake >/dev/null 2>&1 || die "Install CMake with: brew install cmake (or download it from https://cmake.org/download/)."
}

check_bundle() {
    /usr/bin/plutil -lint "$1/Contents/Info.plist"
    "$1/Contents/MacOS/Polyscope" --check-resources
    /usr/bin/codesign --verify --strict "$1"
    # Refuse to install a bundle that still depends on a checkout or Homebrew.
    local library
    while IFS= read -r library; do
        case "$library" in
            /System/Library/*|/usr/lib/*|'') ;;
            *) die "App depends on a non-system library: $library" ;;
        esac
    done < <(/usr/bin/otool -L "$1/Contents/MacOS/Polyscope" | /usr/bin/sed '1d; s/^[[:space:]]*//; s/ (.*//')
}

build_app() {
    require_tools
    cmake -S "$PROJECT_ROOT" -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=ON
    cmake --build "$BUILD_DIR" --config Release --parallel "${CMAKE_BUILD_PARALLEL_LEVEL:-8}"
    check_bundle "$APP_BUNDLE"
    printf '\nBuilt %s\n' "$APP_BUNDLE"
}

install_app() {
    require_macos
    [[ -d "$APP_BUNDLE" ]] || die "Build the app first with: make build"
    check_bundle "$APP_BUNDLE"
    local process_status=0
    /usr/bin/pgrep -x Polyscope >/dev/null || process_status=$?
    case "$process_status" in
        0) die "Quit Polyscope before installing an update." ;;
        1) ;;
        *) die "Cannot check whether Polyscope is running. Run this command from Terminal." ;;
    esac
    mkdir -p "$APPLICATIONS_DIR"
    [[ -w "$APPLICATIONS_DIR" ]] || die "Cannot write to $APPLICATIONS_DIR. Use: make install APPLICATIONS_DIR=\"\$HOME/Applications\""
    local destination="$APPLICATIONS_DIR/Polyscope.app"
    [[ ! -L "$destination" ]] || die "Refusing to replace a symbolic link at $destination."
    if [[ -e "$destination" ]]; then
        local identifier
        identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$destination/Contents/Info.plist" 2>/dev/null) || die "An unrelated item exists at $destination."
        [[ "$identifier" == com.polyscope.viewer ]] || die "An unrelated app exists at $destination."
    fi

    # Copy and validate completely before replacing the installed app. Keep the
    # old version in the staging directory until the replacement succeeds.
    local staging
    staging=$(mktemp -d "$APPLICATIONS_DIR/.polyscope-install.XXXXXX")
    trap 'if [[ -d "$staging/previous.app" && ! -e "$destination" ]]; then if ! mv "$staging/previous.app" "$destination"; then printf "Previous app preserved at %s\n" "$staging/previous.app" >&2; exit 1; fi; fi; /bin/rm -rf "$staging"' EXIT
    /usr/bin/ditto "$APP_BUNDLE" "$staging/Polyscope.app"
    check_bundle "$staging/Polyscope.app"
    if [[ -e "$destination" ]]; then
        mv "$destination" "$staging/previous.app"
    fi
    mv "$staging/Polyscope.app" "$destination"
    /bin/rm -rf "$staging"
    trap - EXIT
    printf '\nInstalled %s\nLaunch it from Finder, Spotlight, or: open "%s"\n' "$destination" "$destination"
}

case "${1:-help}" in
    setup)
        require_macos
        xcode-select -p >/dev/null 2>&1 || die "Run xcode-select --install, finish the installation, then run make setup again."
        if ! command -v cmake >/dev/null 2>&1; then
            command -v brew >/dev/null 2>&1 || die "Install CMake from https://cmake.org/download/ or install Homebrew, then run make setup again."
            brew install cmake
        fi
        cmake --version
        printf '\nReady. Run make install to build and install Polyscope.\n'
        ;;
    build) build_app ;;
    install) build_app; install_app ;;
    # Used after a successful build to install without compiling again.
    install-built) install_app ;;
    update)
        require_tools
        [[ -z "$(git -C "$PROJECT_ROOT" status --porcelain)" ]] || die "Commit or stash local changes before updating. Use make install to install your current local code."
        git -C "$PROJECT_ROOT" pull --ff-only
        build_app
        install_app
        ;;
    run)
        build_app
        shift
        /usr/bin/open "$APP_BUNDLE" --args "$@"
        ;;
    test)
        build_app
        ctest --test-dir "$BUILD_DIR" -C Release --output-on-failure
        ;;
    icon)
        require_tools
        mkdir -p "$BUILD_DIR/swift-cache"
        CLANG_MODULE_CACHE_PATH="$BUILD_DIR/swift-cache" swift -module-cache-path "$BUILD_DIR/swift-cache" "$PROJECT_ROOT/scripts/generate-icon.swift" "$PROJECT_ROOT/assets/icons"
        ;;
    help)
        cat <<'HELP'
make setup    Check developer tools and install CMake if needed
make build    Build a self-contained Release app in build/Polyscope.app
make install  Build and install /Applications/Polyscope.app
make update   Pull with --ff-only, rebuild, and replace the installed app
make run      Build and launch Polyscope
make test     Build and run all tests, including a relocated app check
make icon     Regenerate the checked-in app icon with macOS tools

Optional: make install APPLICATIONS_DIR="$HOME/Applications"
          make build BUILD_DIR="build-release"
HELP
        ;;
    *) die "Unknown command: $1. Run make help." ;;
esac
