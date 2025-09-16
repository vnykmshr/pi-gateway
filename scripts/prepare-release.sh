#!/bin/bash
#
# Pi Gateway Release Preparation
# Validates and prepares codebase for release
#

set -euo pipefail
source "$(dirname "$0")/common.sh"

# Configuration
readonly VERSION_FILE="$PI_GATEWAY_ROOT/VERSION"
readonly CHANGELOG_FILE="$PI_GATEWAY_ROOT/CHANGELOG.md"

main() {
    init_logging "prepare-release"

    info "Preparing Pi Gateway release..."

    # Validate version file
    if [[ ! -f "$VERSION_FILE" ]]; then
        error "VERSION file not found"
        exit 1
    fi

    local version
    version=$(cat "$VERSION_FILE")
    success "Version: $version"

    # Run all quality checks
    info "Running quality checks..."

    # Syntax check all scripts
    find "$PI_GATEWAY_ROOT/scripts" -name "*.sh" -exec bash -n {} \; || {
        error "Syntax check failed"
        exit 1
    }
    success "All scripts have valid syntax"

    # Check for common issues
    if find "$PI_GATEWAY_ROOT/scripts" -name "*.sh" -exec grep -l "TODO\|FIXME\|XXX" {} \; | grep -v prepare-release.sh; then
        warning "Found TODO/FIXME markers in scripts"
    else
        success "No pending TODO/FIXME items"
    fi

    # Validate documentation
    for doc in README.md CHANGELOG.md CONTRIBUTING.md LICENSE; do
        if [[ -f "$PI_GATEWAY_ROOT/$doc" ]]; then
            success "Documentation: $doc ✓"
        else
            error "Missing documentation: $doc"
            exit 1
        fi
    done

    info "Release preparation complete for version $version"
    echo
    echo "Next steps:"
    echo "  1. git add -A && git commit -m 'Prepare release $version'"
    echo "  2. git tag v$version"
    echo "  3. git push origin main --tags"
}

main "$@"