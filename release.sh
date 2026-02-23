#!/bin/bash

set -e  # Exit on error

# Configuration
DEFAULT_BRANCH="main"
VERSION_PATTERN='^v[0-9]+\.[0-9]+$'

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
usage() {
    cat <<EOF
Usage: $0 [VERSION] [OPTIONS]

Automate the release process for this repository.

Arguments:
  VERSION    Version to release (e.g., v1.7 or 1.7)
             If not provided, auto-increments from the latest tag

Options:
  --dry-run  Show what would be done without making changes
  --help     Display this help message

Examples:
  $0              # Auto-increment from latest tag (v1.6 -> v1.7)
  $0 v1.8         # Release version 1.8
  $0 1.8          # Same as above (v prefix is optional)
  $0 --dry-run    # Show what would happen without executing

The script will:
  1. Validate prerequisites (clean git status, gh CLI installed)
  2. Determine the version (from argument or auto-increment)
  3. Create version tag (e.g., v1.7) and major tag (e.g., v1)
  4. Push tags to origin
  5. Create GitHub release with auto-generated notes

EOF
    exit 0
}

log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

get_latest_tag() {
    local latest=$(git tag -l 'v*.*' | sort -V | tail -n1)
    if [ -z "$latest" ]; then
        log_error "No existing version tags found"
        log_info "Please create the first release manually, e.g.:"
        log_info "  git tag v1.0"
        log_info "  git push origin v1.0"
        exit 1
    fi
    echo "$latest"
}

increment_version() {
    local version=$1
    # Extract major and minor version (v1.6 -> 1.6)
    local numbers=$(echo "$version" | sed 's/^v//')
    local major=$(echo "$numbers" | cut -d. -f1)
    local minor=$(echo "$numbers" | cut -d. -f2)

    # Increment minor version
    minor=$((minor + 1))

    echo "v${major}.${minor}"
}

validate_version() {
    local version=$1
    if ! [[ "$version" =~ $VERSION_PATTERN ]]; then
        log_error "Invalid version format: $version"
        log_info "Version must match pattern: vX.Y (e.g., v1.7)"
        exit 1
    fi
}

normalize_version() {
    local version=$1
    # Add 'v' prefix if not present
    if [[ ! "$version" =~ ^v ]]; then
        version="v${version}"
    fi
    echo "$version"
}

check_tag_exists() {
    local tag=$1
    if git rev-parse "refs/tags/$tag" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if gh CLI is installed
    if ! command -v gh &> /dev/null; then
        log_error "GitHub CLI (gh) is not installed"
        log_info "Install it from: https://cli.github.com/"
        exit 1
    fi

    # Check if gh is authenticated
    if ! gh auth status &> /dev/null; then
        log_error "GitHub CLI is not authenticated"
        log_info "Run: gh auth login"
        exit 1
    fi

    # Check if working directory is clean
    if ! git diff-index --quiet HEAD -- 2>/dev/null; then
        log_error "Working directory has uncommitted changes"
        log_info "Please commit or stash your changes before releasing"
        git status --short
        exit 1
    fi

    # Check current branch
    local current_branch=$(git branch --show-current)
    if [ "$current_branch" != "$DEFAULT_BRANCH" ]; then
        log_warning "You are on branch '$current_branch', not '$DEFAULT_BRANCH'"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Release cancelled"
            exit 0
        fi
    fi

    # Fetch latest tags from remote
    log_info "Fetching latest tags from remote..."
    git fetch --tags --quiet

    log_success "All prerequisites satisfied"
}

extract_major_version() {
    local version=$1
    echo "$version" | grep -oE 'v[0-9]+'
}

create_tags() {
    local version=$1
    local major_version=$2
    local dry_run=$3

    log_info "Creating tags..."

    if [ "$dry_run" = true ]; then
        log_info "[DRY RUN] Would create tag: $version"
        log_info "[DRY RUN] Would force-update tag: $major_version"
    else
        git tag "$version"
        log_success "Created tag: $version"

        git tag "$major_version" -f
        log_success "Force-updated tag: $major_version"
    fi
}

push_tags() {
    local version=$1
    local major_version=$2
    local dry_run=$3

    log_info "Pushing tags to origin..."

    if [ "$dry_run" = true ]; then
        log_info "[DRY RUN] Would push: git push origin $version $major_version -f"
    else
        git push origin "$version" "$major_version" -f
        log_success "Pushed tags to origin"
    fi
}

create_github_release() {
    local version=$1
    local dry_run=$2

    log_info "Creating GitHub release..."

    if [ "$dry_run" = true ]; then
        log_info "[DRY RUN] Would create release: gh release create $version --generate-notes --verify-tag"
    else
        gh release create "$version" --generate-notes --verify-tag
        log_success "Created GitHub release: $version"
    fi
}

cleanup_on_error() {
    local version=$1
    local major_version=$2

    log_warning "Cleaning up tags due to error..."

    # Try to delete local tags if they exist
    if check_tag_exists "$version"; then
        git tag -d "$version" 2>/dev/null || true
        log_info "Deleted local tag: $version"
    fi

    # Note: We don't delete the major version tag locally as it might have existed before
    log_info "You may need to manually clean up remote tags if they were pushed"
}

main() {
    local version=""
    local dry_run=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                usage
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            *)
                if [ -z "$version" ]; then
                    version=$1
                else
                    log_error "Unexpected argument: $1"
                    usage
                fi
                shift
                ;;
        esac
    done

    echo "🚀 Twingate GitHub Action Release Script"
    echo

    # Check prerequisites first
    if [ "$dry_run" = false ]; then
        check_prerequisites
        echo
    else
        log_warning "Running in DRY RUN mode - no changes will be made"
        echo
    fi

    # Determine version
    if [ -z "$version" ]; then
        local latest_tag=$(get_latest_tag)
        version=$(increment_version "$latest_tag")
        log_info "Latest tag: $latest_tag"
        log_info "Auto-incremented to: $version"
    else
        version=$(normalize_version "$version")
        log_info "Using specified version: $version"
    fi

    # Validate version format
    validate_version "$version"

    # Check if tag already exists
    if check_tag_exists "$version"; then
        log_error "Tag $version already exists"
        log_info "If you want to re-release, delete the tag first:"
        log_info "  git tag -d $version"
        log_info "  git push origin :refs/tags/$version"
        exit 1
    fi

    # Extract major version
    local major_version=$(extract_major_version "$version")

    echo
    log_info "Release Summary:"
    echo "  Version:       $version"
    echo "  Major tag:     $major_version"
    echo "  Dry run:       $dry_run"
    echo

    # Confirm with user
    if [ "$dry_run" = false ]; then
        read -p "Proceed with release? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Release cancelled"
            exit 0
        fi
        echo
    fi

    # Set up error handling
    if [ "$dry_run" = false ]; then
        trap 'cleanup_on_error "$version" "$major_version"' ERR
    fi

    # Execute release steps
    create_tags "$version" "$major_version" "$dry_run"
    push_tags "$version" "$major_version" "$dry_run"
    create_github_release "$version" "$dry_run"

    # Success!
    echo
    log_success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if [ "$dry_run" = true ]; then
        log_success "DRY RUN COMPLETE"
        log_info "No changes were made. Run without --dry-run to execute."
    else
        log_success "RELEASE COMPLETE!"
        log_info "Version $version has been released"
        log_info "GitHub Release: https://github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner)/releases/tag/$version"
    fi
    log_success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Run main function
main "$@"
