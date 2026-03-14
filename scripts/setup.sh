#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────────
# openOwl setup script
# Initializes ghostty submodule and builds GhosttyKit xcframework.
# Caches build output by ghostty commit SHA to avoid redundant rebuilds.
# ─────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
GHOSTTY_DIR="$PROJECT_DIR/ghostty"
CACHE_BASE="$HOME/.cache/openowl/ghosttykit"
XCFRAMEWORK_LINK="$PROJECT_DIR/GhosttyKit.xcframework"
RESOURCES_LINK="$PROJECT_DIR/ghostty-resources"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[openOwl]${NC} $1"; }
warn()  { echo -e "${YELLOW}[openOwl]${NC} $1"; }
error() { echo -e "${RED}[openOwl]${NC} $1" >&2; }

# ─── Check prerequisites ───

check_prerequisites() {
    if ! command -v zig &>/dev/null; then
        error "zig not found. Install with: brew install zig"
        exit 1
    fi
    info "zig version: $(zig version)"

    if ! command -v git &>/dev/null; then
        error "git not found"
        exit 1
    fi
}

# ─── Initialize submodule ───

init_submodule() {
    if [ ! -f "$GHOSTTY_DIR/.gitmodules" ] && [ ! -f "$GHOSTTY_DIR/build.zig" ]; then
        info "Initializing ghostty submodule..."
        cd "$PROJECT_DIR"
        git submodule update --init --recursive ghostty
    else
        info "Ghostty submodule already initialized"
    fi
}

# ─── Build GhosttyKit ───

build_ghosttykit() {
    cd "$GHOSTTY_DIR"

    # Get current commit SHA
    local sha
    sha=$(git rev-parse HEAD)
    local cache_dir="$CACHE_BASE/$sha"
    local cached_xcframework="$cache_dir/GhosttyKit.xcframework"

    # Check cache
    if [ -d "$cached_xcframework" ]; then
        info "Using cached GhosttyKit for commit ${sha:0:8}"
    else
        info "Building GhosttyKit for commit ${sha:0:8}..."
        info "This may take 5-10 minutes on first build."

        zig build \
            -Demit-xcframework=true \
            -Dxcframework-target=universal \
            -Doptimize=ReleaseFast

        # Find the built xcframework
        local built_path="$GHOSTTY_DIR/zig-out/macos/GhosttyKit.xcframework"
        if [ ! -d "$built_path" ]; then
            # Try alternative path
            built_path="$GHOSTTY_DIR/macos/GhosttyKit.xcframework"
        fi

        if [ ! -d "$built_path" ]; then
            error "GhosttyKit.xcframework not found after build"
            error "Searched: $GHOSTTY_DIR/zig-out/macos/ and $GHOSTTY_DIR/macos/"
            error "Listing zig-out contents:"
            find "$GHOSTTY_DIR/zig-out" -name "*.xcframework" -type d 2>/dev/null || true
            exit 1
        fi

        # Cache xcframework and resources
        mkdir -p "$cache_dir"
        cp -R "$built_path" "$cached_xcframework"

        # Cache resources (shell-integration, themes, terminfo)
        local resources_src="$GHOSTTY_DIR/zig-out/share/ghostty"
        if [ -d "$resources_src" ]; then
            cp -R "$resources_src" "$cache_dir/resources"
        fi

        # terminfo lives outside the ghostty subdir — merge it into resources
        local terminfo_src="$GHOSTTY_DIR/zig-out/share/terminfo"
        if [ -d "$terminfo_src" ]; then
            mkdir -p "$cache_dir/resources/terminfo"
            cp -R "$terminfo_src"/* "$cache_dir/resources/terminfo/"
        fi

        info "Cached to $cache_dir"
    fi

    # Create symlinks in project root
    ln -sfn "$cached_xcframework" "$XCFRAMEWORK_LINK"
    info "Symlinked GhosttyKit.xcframework → ${sha:0:8}"

    local cached_resources="$cache_dir/resources"
    if [ -d "$cached_resources" ]; then
        ln -sfn "$cached_resources" "$RESOURCES_LINK"
        info "Symlinked ghostty-resources → ${sha:0:8}"
    fi
}

# ─── Verify ───

verify() {
    if [ ! -d "$XCFRAMEWORK_LINK" ]; then
        error "GhosttyKit.xcframework symlink missing"
        exit 1
    fi

    # Check that the header exists
    local header="$XCFRAMEWORK_LINK/macos-arm64_x86_64/Headers/ghostty.h"
    if [ ! -f "$header" ]; then
        error "ghostty.h not found at $header"
        exit 1
    fi

    info "✓ GhosttyKit.xcframework ready"
    info "✓ Header: $header"
}

# ─── Main ───

main() {
    info "Setting up openOwl development environment..."
    check_prerequisites
    init_submodule
    build_ghosttykit
    verify
    info "Setup complete! Run 'xcodegen generate' to create the Xcode project."
}

main "$@"
