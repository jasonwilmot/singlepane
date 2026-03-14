#!/usr/bin/env bash
# Velocity — Development setup script
# Installs dependencies, builds the project, and runs initial setup.

set -euo pipefail
IFS=$'\n\t'

# ── Colors ──────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log()   { echo -e "${BLUE}[velocity]${NC} $*"; }
ok()    { echo -e "${GREEN}[  ok  ]${NC} $*"; }
warn()  { echo -e "${YELLOW}[ warn ]${NC} $*"; }
error() { echo -e "${RED}[error ]${NC} $*" >&2; }
die()   { error "$@"; exit 1; }

# ── Prerequisites ───────────────────────────────────────────

check_macos() {
    [[ "$(uname -s)" == "Darwin" ]] || die "This script requires macOS."
    log "macOS $(sw_vers -productVersion) detected"
}

check_xcode() {
    if ! xcode-select -p &>/dev/null; then
        warn "Xcode Command Line Tools not found. Installing..."
        xcode-select --install
        die "Please re-run this script after Xcode CLT installation completes."
    fi

    local xcode_version
    xcode_version=$(xcodebuild -version 2>/dev/null | head -1 | awk '{print $2}')

    if [[ -z "$xcode_version" ]]; then
        die "Could not determine Xcode version. Is Xcode installed?"
    fi

    local major_version="${xcode_version%%.*}"
    if (( major_version < 16 )); then
        die "Xcode 16+ required (found $xcode_version)"
    fi

    ok "Xcode $xcode_version"
}

check_homebrew() {
    if ! command -v brew &>/dev/null; then
        warn "Homebrew not found. Installing..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    ok "Homebrew $(brew --version | head -1 | awk '{print $2}')"
}

# ── Dependencies ────────────────────────────────────────────

BREW_DEPS=(
    "swiftlint"
    "swiftformat"
    "xcpretty"
    "libarchive"
    "minizip-ng"
    "sqlite"
)

install_deps() {
    log "Installing dependencies..."

    local missing=()
    for dep in "${BREW_DEPS[@]}"; do
        if ! brew list "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done

    if (( ${#missing[@]} > 0 )); then
        log "Installing: ${missing[*]}"
        brew install "${missing[@]}"
    fi

    ok "All dependencies installed"
}

# ── Project Setup ───────────────────────────────────────────

setup_project() {
    local project_root
    project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    cd "$project_root"

    log "Setting up project at $project_root"

    # Resolve Swift packages
    log "Resolving package dependencies..."
    xcodebuild -resolvePackageDependencies -scheme Velocity 2>/dev/null
    ok "Package dependencies resolved"

    # Create local directories
    local dirs=(
        "$HOME/Library/Application Support/Velocity"
        "$HOME/Library/Caches/Velocity/thumbnails"
        "$HOME/Library/Logs/Velocity"
    )
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
    done
    ok "Local directories created"

    # Copy default config if not present
    local config_dir="$HOME/Library/Application Support/Velocity"
    if [[ ! -f "$config_dir/config.json" ]]; then
        cp Resources/default-config.json "$config_dir/config.json" 2>/dev/null || true
        ok "Default config installed"
    else
        warn "Config already exists, skipping"
    fi
}

# ── Build ───────────────────────────────────────────────────

build_project() {
    log "Building Velocity (Debug)..."

    if ! xcodebuild \
        -scheme Velocity \
        -configuration Debug \
        -derivedDataPath .build/DerivedData \
        build 2>&1 | xcpretty; then
        die "Build failed. Check the output above."
    fi

    ok "Build succeeded"
}

# ── Verify ──────────────────────────────────────────────────

run_tests() {
    log "Running unit tests..."

    if ! xcodebuild \
        -scheme Velocity \
        -configuration Debug \
        -derivedDataPath .build/DerivedData \
        test \
        -only-testing:VelocityTests/Unit 2>&1 | xcpretty; then
        warn "Some tests failed. Check the output above."
        return 1
    fi

    ok "All tests passed"
}

# ── Summary ─────────────────────────────────────────────────

print_summary() {
    echo ""
    echo -e "${BOLD}${GREEN}Setup complete!${NC}"
    echo ""
    echo "  Next steps:"
    echo "    make run          — Build and launch Velocity"
    echo "    make test         — Run all tests"
    echo "    make lint         — Lint the codebase"
    echo "    make help         — Show all targets"
    echo ""
    echo "  Useful shortcuts:"
    echo "    Cmd+Shift+P       — Command palette"
    echo "    F5                — Copy selected files"
    echo "    Cmd+T             — Toggle terminal"
    echo ""
}

# ── Main ────────────────────────────────────────────────────

main() {
    echo ""
    echo -e "${BOLD}Velocity File Manager — Development Setup${NC}"
    echo "─────────────────────────────────────────────"
    echo ""

    check_macos
    check_xcode
    check_homebrew
    install_deps
    setup_project
    build_project

    if [[ "${SKIP_TESTS:-}" != "1" ]]; then
        run_tests
    fi

    print_summary
}

main "$@"
