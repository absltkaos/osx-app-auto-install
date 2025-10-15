#!/bin/bash

# macOS Setup Script
# This script installs applications and configures zshrc based on configuration files
# Requirements: macOS 15.6.1 or later

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETAILS_DIR="$SCRIPT_DIR/Details"
CONF_DIR="$SCRIPT_DIR/conf.d"

# Default values
INSTALL_PERSONAL_APPS=false
CLEANUP_INSTALLERS=false
VERBOSE=false
DRY_RUN=false
ASDF_INSTALLS_OCCURRED=false
SUDO_REQUIRED=false

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    -p, --personal      Install personal apps (files prefixed with 'personal_')
    -c, --cleanup       Clean up old installers (default: false)
    -v, --verbose       Verbose output (default: false)
    -d, --dry-run       Show what would be installed without making changes
    -h, --help          Show this help message

Examples:
    $0                          # Install all apps from .conf files (excluding personal_*)
    $0 -p                      # Install all apps including personal_* files
    $0 -p -c                   # Install all apps and cleanup installers
    $0 -v                      # Verbose output
    $0 -d                      # Show what would be installed (dry run)
    $0 -d -v                   # Show detailed dry run information

EOF
}

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${BLUE}[VERBOSE]${NC} $1"
    fi
}

# Check if running on macOS 15.6.1 or later
check_macos_version() {
    local os_version
    os_version=$(sw_vers -productVersion)
    local major_version
    major_version=$(echo "$os_version" | cut -d. -f1)
    local minor_version
    minor_version=$(echo "$os_version" | cut -d. -f2)
    local patch_version
    patch_version=$(echo "$os_version" | cut -d. -f3)
    
    if [[ $major_version -lt 15 ]] || [[ $major_version -eq 15 && $minor_version -lt 6 ]] || [[ $major_version -eq 15 && $minor_version -eq 6 && $patch_version -lt 1 ]]; then
        log_error "This script requires macOS 15.6.1 or later. Current version: $os_version"
        exit 1
    fi
    
    log_info "macOS version check passed: $os_version"
}

# Validate sudo access
validate_sudo_access() {
    log_info "Validating sudo access..."
    
    if ! sudo -v; then
        log_error "Failed to validate sudo access. This script requires administrator privileges."
        log_error "Please ensure you have sudo access and try again."
        exit 1
    fi
    
    log_success "Sudo access validated successfully"
}

# Check what needs to be installed (dry run)
check_what_needs_installation() {
    log_info "Checking what needs to be installed..."
    
    # Check if Homebrew needs to be installed
    check_homebrew
    
    # Check all .conf files in conf.d/ directory
    local conf_files
    if [[ "$INSTALL_PERSONAL_APPS" == "true" ]]; then
        # Include all .conf files when -p flag is used
        conf_files=$(find "$CONF_DIR" -name "*.conf" -type f 2>/dev/null | sort)
    else
        # Exclude personal_* files when -p flag is not used
        conf_files=$(find "$CONF_DIR" -name "*.conf" -type f 2>/dev/null | grep -v "/personal_" | sort)
    fi
    
    if [[ -n "$conf_files" ]]; then
        while IFS= read -r conf_file; do
            if [[ -f "$conf_file" ]]; then
                log_verbose "Checking config file: $conf_file"
                check_apps_config "$conf_file"
            fi
        done <<< "$conf_files"
    else
        log_verbose "No .conf files found in $CONF_DIR"
    fi
    
    # Check zshrc modifications
    check_zshrc_modifications
}

# Check apps configuration (dry run)
check_apps_config() {
    local config_file="$1"
    
    log_verbose "Checking config file: $config_file"
    
    while IFS= read -r line; do
        # Skip empty lines and comments
        if [[ -z "$line" ]] || [[ "$line" =~ ^#.*$ ]]; then
            continue
        fi
        
        # Parse structured format: type=app_name::install_method::install_data::app_path
        if [[ "$line" =~ ^([^=]+)=([^:]+)::([^:]+)::(.+)::(.+)$ ]]; then
            local app_type="${BASH_REMATCH[1]}"
            local app_name="${BASH_REMATCH[2]}"
            local install_method="${BASH_REMATCH[3]}"
            local install_data="${BASH_REMATCH[4]}"
            local app_path="${BASH_REMATCH[5]}"
            
            log_verbose "Checking app: $app_name (type: $app_type, method: $install_method)"
            
            case "$app_type" in
                "custom")
                    case "$install_method" in
                        "command")
                            if ! is_app_installed "$app_name" "$app_path"; then
                                log_info "Will install '$app_name' via custom command"
                                SUDO_REQUIRED=true
                            fi
                            ;;
                        "dmg")
                            if ! is_app_installed "$app_name" "$app_path"; then
                                log_info "Will install '$app_name' from DMG"
                                SUDO_REQUIRED=true
                            fi
                            ;;
                        "zip")
                            if ! is_app_installed "$app_name" "$app_path"; then
                                log_info "Will install '$app_name' from ZIP"
                                SUDO_REQUIRED=true
                            fi
                            ;;
                        "dmg_github_release")
                            if ! is_app_installed "$app_name" "$app_path"; then
                                log_info "Will install '$app_name' from GitHub release"
                                if ! discover_github_release_dmg_url "$app_name" "$install_data"; then
                                    log_error "Failed to discover GitHub release DMG URL for '$app_name'"
                                fi
                                SUDO_REQUIRED=true
                            fi
                            ;;
                        "dmg_web_release")
                            if ! is_app_installed "$app_name" "$app_path"; then
                                log_info "Will install '$app_name' from web release page"
                                if ! discover_web_release_dmg_url "$app_name" "$install_data"; then
                                    log_error "Failed to discover web release DMG URL for '$app_name'"
                                fi
                                SUDO_REQUIRED=true
                            fi
                            ;;
                        "dmg_synergy_release")
                            if ! is_app_installed "$app_name" "$app_path"; then
                                log_info "Will install '$app_name' from Synergy release page"
                                if ! discover_synergy_release_dmg_url "$app_name" "$install_data"; then
                                    log_error "Failed to discover Synergy release DMG URL for '$app_name'"
                                fi
                                SUDO_REQUIRED=true
                            fi
                            ;;
                        "manual")
                            log_info "Manual installation required for $app_name: $install_data"
                            ;;
                    esac
                    ;;
                "brew")
                    if ! brew list "$app_name" >/dev/null 2>&1; then
                        log_info "Will install '$app_name' via Homebrew"
                        SUDO_REQUIRED=true
                    fi
                    ;;
                "asdf")
                    if ! asdf list "$app_name" | grep -q "$install_data"; then
                        log_info "Will install '$app_name' version $install_data via asdf"
                        SUDO_REQUIRED=true
                    fi
                    ;;
                "appstore")
                    case "$install_method" in
                        "install")
                            if ! is_app_installed "$app_name" "$app_path"; then
                                log_info "Will install '$app_name' from Mac App Store"
                                if ! discover_app_store_id "$app_name" "$install_data"; then
                                    log_error "Failed to discover App Store ID for '$app_name'"
                                fi
                                SUDO_REQUIRED=true
                            fi
                            ;;
                        "manual")
                            log_info "App Store app '$app_name' - please install manually"
                            ;;
                    esac
                    ;;
            esac
        fi
        
    done < "$config_file"
}

# Check zshrc modifications (dry run)
check_zshrc_modifications() {
    local zshrc_file="$HOME/.zshrc"
    local modifications_file="$CONF_DIR/zshrc_modifications"
    
    if [[ ! -f "$modifications_file" ]]; then
        return 0
    fi
    
    local marker="# macOS Setup Script Modifications"
    if [[ -f "$zshrc_file" ]] && grep -q "$marker" "$zshrc_file"; then
        log_verbose "zshrc modifications already applied"
    else
        log_info "Will apply zshrc modifications"
        # zshrc modifications don't require sudo
    fi
}

# Check if app is already installed
is_app_installed() {
    local app_name="$1"
    local app_path="$2"
    
    # Use realpath to check if the path exists and resolves to a real file/directory
    # realpath returns exit code 0 if successful, non-zero if the path doesn't exist or is broken
    if realpath "$app_path" >/dev/null 2>&1; then
        log_verbose "App '$app_name' is already installed at: $app_path"
        return 0
    else
        log_verbose "App '$app_name' is not installed"
        return 1
    fi
}

# Install Homebrew if not present
install_homebrew() {
    if command -v brew >/dev/null 2>&1; then
        log_info "Homebrew is already installed"
    else
        log_info "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        
        # Add Homebrew to PATH for current session
        if [[ -f "/opt/homebrew/bin/brew" ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [[ -f "/usr/local/bin/brew" ]]; then
            eval "$(/usr/local/bin/brew shellenv)"
        fi
        
        log_success "Homebrew installed successfully"
    fi
    
    # Install mas (Mac App Store command line interface) if not present
    if ! command -v mas >/dev/null 2>&1; then
        log_info "Installing mas (Mac App Store command line interface)..."
        brew install mas
        log_success "mas installed successfully"
    else
        log_verbose "mas is already installed"
    fi
}

# Check if Homebrew needs to be installed
check_homebrew() {
    if ! command -v brew >/dev/null 2>&1; then
        log_info "Will install Homebrew"
        SUDO_REQUIRED=true
    fi
    
    # Also check for mas if we have any App Store apps to install
    if ! command -v mas >/dev/null 2>&1; then
        log_info "Will install mas (Mac App Store command line interface)"
        SUDO_REQUIRED=true
    fi
}

# Install app via Homebrew
install_brew_app() {
    local app_name="$1"
    local install_command="$2"
    
    if brew list "$app_name" >/dev/null 2>&1; then
        log_info "App '$app_name' is already installed via Homebrew"
        return 0
    fi
    
    log_info "Installing '$app_name' via Homebrew..."
    eval "$install_command"
    log_success "Successfully installed '$app_name' via Homebrew"
}

# Download and install app from ZIP
install_zip_app() {
    local app_name="$1"
    local download_url="$2"
    local app_path="$3"
    local installer_name="$4"
    
    if is_app_installed "$app_name" "$app_path"; then
        return 0
    fi
    
    log_info "Installing '$app_name' from ZIP..."
    
    # Create temporary directory for downloads
    local temp_dir
    temp_dir=$(mktemp -d)
    local zip_path="$temp_dir/$installer_name"
    
    # Download ZIP
    log_verbose "Downloading $installer_name from $download_url"
    if ! curl -L -o "$zip_path" "$download_url"; then
        log_error "Failed to download $installer_name"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Extract ZIP
    log_verbose "Extracting $installer_name"
    if ! unzip -q "$zip_path" -d "$temp_dir"; then
        log_error "Failed to extract $installer_name"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Look for .app bundle or .dmg file in extracted contents
    local app_bundle
    app_bundle=$(find "$temp_dir" -name "*.app" -type d | head -1)
    local dmg_file
    dmg_file=$(find "$temp_dir" -name "*.dmg" -type f | head -1)
    
    if [[ -n "$app_bundle" ]]; then
        # Found .app bundle, copy it directly
        log_verbose "Found app bundle: $app_bundle"
        if ! cp -R "$app_bundle" "/Applications/"; then
            log_error "Failed to copy app bundle to /Applications/"
            rm -rf "$temp_dir"
            return 1
        fi
    elif [[ -n "$dmg_file" ]]; then
        # Found .dmg file, mount and install it
        log_verbose "Found DMG file in ZIP: $dmg_file"
        local mount_point
        mount_point=$(mktemp -d)
        if ! hdiutil attach "$dmg_file" -mountpoint "$mount_point" -quiet; then
            log_error "Failed to mount DMG from ZIP: $dmg_file"
            rm -rf "$temp_dir"
            return 1
        fi
        
        # Copy .app bundle from mounted DMG
        local dmg_app
        dmg_app=$(find "$mount_point" -name "*.app" -type d | head -1)
        if [[ -n "$dmg_app" ]]; then
            if ! cp -R "$dmg_app" "/Applications/"; then
                log_error "Failed to copy app from mounted DMG"
                hdiutil detach "$mount_point" -quiet
                rm -rf "$temp_dir"
                return 1
            fi
        else
            log_error "No .app bundle found in mounted DMG"
            hdiutil detach "$mount_point" -quiet
            rm -rf "$temp_dir"
            return 1
        fi
        
        # Unmount DMG
        hdiutil detach "$mount_point" -quiet
    else
        log_error "No .app bundle or .dmg file found in ZIP contents"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Clean up
    rm -rf "$temp_dir"
    
    # Verify installation
    if is_app_installed "$app_name" "$app_path"; then
        log_success "Successfully installed '$app_name' from ZIP"
    else
        log_error "Installation verification failed for '$app_name'"
        return 1
    fi
}

# Download and install app from DMG
install_dmg_app() {
    local app_name="$1"
    local download_url="$2"
    local app_path="$3"
    local installer_name="$4"
    
    if is_app_installed "$app_name" "$app_path"; then
        return 0
    fi
    
    log_info "Installing '$app_name' from DMG..."
    
    # Create temporary directory for downloads
    local temp_dir
    temp_dir=$(mktemp -d)
    local dmg_path="$temp_dir/$installer_name"
    
    # Download DMG
    log_verbose "Downloading $installer_name from $download_url"
    if ! curl -L -o "$dmg_path" "$download_url"; then
        log_error "Failed to download $installer_name"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Mount DMG
    local mount_point
    mount_point=$(mktemp -d)
    if ! hdiutil attach "$dmg_path" -mountpoint "$mount_point" -quiet; then
        log_error "Failed to mount $installer_name"
        rm -rf "$temp_dir" "$mount_point"
        return 1
    fi
    
    # Find and copy app
    local app_to_install
    app_to_install=$(find "$mount_point" -name "*.app" -type d | head -1)
    
    if [[ -z "$app_to_install" ]]; then
        log_error "No .app found in $installer_name"
        hdiutil detach "$mount_point" -quiet
        rm -rf "$temp_dir" "$mount_point"
        return 1
    fi
    
    # Copy app to Applications
    log_verbose "Copying $(basename "$app_to_install") to /Applications"
    if ! cp -R "$app_to_install" /Applications/; then
        log_error "Failed to copy app to /Applications"
        hdiutil detach "$mount_point" -quiet
        rm -rf "$temp_dir" "$mount_point"
        return 1
    fi
    
    # Unmount and cleanup
    hdiutil detach "$mount_point" -quiet
    rm -rf "$temp_dir" "$mount_point"
    
    log_success "Successfully installed '$app_name'"
}

# Get system architecture
get_system_architecture() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        "arm64")
            echo "arm64"
            ;;
        "x86_64")
            echo "x86_64"
            ;;
        *)
            echo "universal"
            ;;
    esac
}

# Discover GitHub release DMG URL (for dry-run)
discover_github_release_dmg_url() {
    local app_name="$1"
    local repo_url="$2"
    
    # Extract owner/repo from URL
    local repo_owner_repo
    if [[ "$repo_url" =~ github\.com/([^/]+)/([^/]+) ]]; then
        repo_owner_repo="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    else
        log_warning "Invalid GitHub repository URL: $repo_url"
        return 1
    fi

    # Get latest release info
    log_verbose "Fetching latest release for $repo_owner_repo"
    local release_info
    local curl_exit_code
    release_info=$(curl -s --max-time 10 --connect-timeout 5 "https://api.github.com/repos/$repo_owner_repo/releases/latest" 2>/dev/null)
    curl_exit_code=$?
    
    if [[ $curl_exit_code -ne 0 ]]; then
        log_error "Failed to fetch release information for $repo_owner_repo (curl exit code: $curl_exit_code)"
        return 1
    fi
    
    if [[ -z "$release_info" ]]; then
        log_error "Failed to fetch release information for $repo_owner_repo (empty response)"
        return 1
    fi
    
    # Get system architecture
    local system_arch
    system_arch=$(get_system_architecture)
    log_verbose "System architecture: $system_arch"
    
    # Find appropriate DMG asset
    log_verbose "Searching for DMG assets in GitHub release..."
    local dmg_url
    dmg_url=$(echo "$release_info" | jq -r --arg arch "$system_arch" '
        .assets[] | 
        select(.name | endswith(".dmg")) |
        select(.name | test("universal|" + $arch + "|silicon|apple"; "i")) |
        .browser_download_url' | head -1)
    
    if [[ -z "$dmg_url" || "$dmg_url" == "null" ]]; then
        # Fallback to any DMG
        dmg_url=$(echo "$release_info" | jq -r '.assets[] | select(.name | endswith(".dmg")) | .browser_download_url' | head -1)
    fi
    
    if [[ -z "$dmg_url" || "$dmg_url" == "null" ]]; then
        log_error "No DMG asset found in latest release for $repo_owner_repo"
        log_error "  Please check the repository URL or use a different installer type"
        return 1
    fi
    
    log_info "  Would download DMG from: $dmg_url"
}

# Shared function to find DMG URL from web page content
find_dmg_url_from_web_page() {
    local web_url="$1"
    local page_content="$2"
    local system_arch="$3"
    
    # Extract DMG URLs with preference order
    log_verbose "Searching for DMG download links..."
    local dmg_url
    dmg_url=$(echo "$page_content" | grep -oE 'href="[^"]*\.dmg[^"]*"' | sed 's/href="//g; s/"//g' | while read -r url; do
        # Convert relative URLs to absolute
        if [[ "$url" =~ ^https?:// ]]; then
            echo "$url"
        else
            echo "$web_url$url"
        fi
    done | while read -r url; do
        # Check preferences in order
        if echo "$url" | grep -qi "universal"; then
            echo "$url"
            break
        elif echo "$url" | grep -qi "$system_arch"; then
            echo "$url"
            break
        elif echo "$url" | grep -qi "silicon"; then
            echo "$url"
            break
        elif echo "$url" | grep -qi "apple"; then
            echo "$url"
            break
        fi
    done | head -1)
    
    # Log what we found (outside of command substitution)
    if [[ -n "$dmg_url" ]]; then
        if echo "$dmg_url" | grep -qi "universal"; then
            log_verbose "Found universal DMG: $dmg_url"
        elif echo "$dmg_url" | grep -qi "$system_arch"; then
            log_verbose "Found architecture-specific DMG ($system_arch): $dmg_url"
        elif echo "$dmg_url" | grep -qi "silicon"; then
            log_verbose "Found silicon DMG: $dmg_url"
        elif echo "$dmg_url" | grep -qi "apple"; then
            log_verbose "Found apple DMG: $dmg_url"
        else
            log_verbose "Found DMG: $dmg_url"
        fi
    fi
    
    # If no direct DMG URLs found, look for redirect URLs (like Cursor's API endpoints)
    if [[ -z "$dmg_url" ]]; then
        log_verbose "No direct DMG URLs found, checking for redirect URLs..."
        
        # Look for hrefs that might be redirect URLs (containing download, api, etc.)
        local redirect_urls
        redirect_urls=$(echo "$page_content" | grep -oE 'href="[^"]*"' | sed 's/href="//g; s/"//g' | grep -E "(download|api|release)" | while read -r url; do
            # Convert relative URLs to absolute
            if [[ "$url" =~ ^https?:// ]]; then
                echo "$url"
            else
                echo "$web_url$url"
            fi
        done)
        
        # Try each redirect URL to see if it leads to a DMG
        for redirect_url in $redirect_urls; do
            log_verbose "Checking redirect URL: $redirect_url"
            
            # Follow redirects and check if the final URL is a DMG
            local final_url
            final_url=$(curl -s --max-time 5 --connect-timeout 3 -I "$redirect_url" 2>/dev/null | grep -i "^location:" | sed 's/location: *//i' | tr -d '\r\n')
            
            if [[ -n "$final_url" ]] && echo "$final_url" | grep -qi "\.dmg"; then
                # Check if this DMG matches our architecture preferences
                if echo "$final_url" | grep -qi "universal"; then
                    log_verbose "Found universal DMG via redirect: $final_url"
                    dmg_url="$final_url"
                    break
                elif echo "$final_url" | grep -qi "$system_arch"; then
                    log_verbose "Found architecture-specific DMG via redirect ($system_arch): $final_url"
                    dmg_url="$final_url"
                    break
                elif echo "$final_url" | grep -qi "silicon"; then
                    log_verbose "Found silicon DMG via redirect: $final_url"
                    dmg_url="$final_url"
                    break
                elif echo "$final_url" | grep -qi "apple"; then
                    log_verbose "Found apple DMG via redirect: $final_url"
                    dmg_url="$final_url"
                    break
                fi
            fi
        done
        
        # If still no DMG found, try any redirect that leads to a DMG
        if [[ -z "$dmg_url" ]]; then
            for redirect_url in $redirect_urls; do
                local final_url
                final_url=$(curl -s --max-time 5 --connect-timeout 3 -I "$redirect_url" 2>/dev/null | grep -i "^location:" | sed 's/location: *//i' | tr -d '\r\n')
                
                if [[ -n "$final_url" ]] && echo "$final_url" | grep -qi "\.dmg"; then
                    log_verbose "Found DMG via redirect (fallback): $final_url"
                    dmg_url="$final_url"
                    break
                fi
            done
        fi
    fi
    
    echo "$dmg_url"
}

# Discover web release DMG URL (for dry-run)
discover_web_release_dmg_url() {
    local app_name="$1"
    local web_url="$2"
    
    # Get system architecture
    local system_arch
    system_arch=$(get_system_architecture)
    log_verbose "System architecture: $system_arch"
    
    # Fetch the webpage with timeout
    log_verbose "Fetching release page: $web_url"
    local page_content
    local curl_exit_code
    page_content=$(curl -s --max-time 10 --connect-timeout 5 "$web_url" 2>/dev/null)
    curl_exit_code=$?
    
    if [[ $curl_exit_code -ne 0 ]]; then
        log_error "Failed to fetch release page: $web_url (curl exit code: $curl_exit_code)"
        return 1
    fi
    
    if [[ -z "$page_content" ]]; then
        log_error "Failed to fetch release page: $web_url (empty response)"
        return 1
    fi
    
    # Extract DMG URLs with preference order
    # Use shared function to find DMG URL
    local dmg_url
    dmg_url=$(find_dmg_url_from_web_page "$web_url" "$page_content" "$system_arch")
    
    # If no direct DMG URLs found, look for redirect URLs (like Cursor's API endpoints)
    if [[ -z "$dmg_url" ]]; then
        log_verbose "No direct DMG URLs found, checking for redirect URLs..."
        
        # Look for hrefs that might be redirect URLs (containing download, api, etc.)
        local redirect_urls
        redirect_urls=$(echo "$page_content" | grep -oE 'href="[^"]*"' | sed 's/href="//g; s/"//g' | grep -E "(download|api|release)" | while read -r url; do
            # Convert relative URLs to absolute
            if [[ "$url" =~ ^https?:// ]]; then
                echo "$url"
            else
                echo "$web_url$url"
            fi
        done)
        
        # Try each redirect URL to see if it leads to a DMG
        for redirect_url in $redirect_urls; do
            log_verbose "Checking redirect URL: $redirect_url"
            
            # Follow redirects and check if the final URL is a DMG
            local final_url
            final_url=$(curl -s --max-time 5 --connect-timeout 3 -I "$redirect_url" 2>/dev/null | grep -i "^location:" | sed 's/location: *//i' | tr -d '\r\n')
            
            if [[ -n "$final_url" ]] && echo "$final_url" | grep -qi "\.dmg"; then
                # Check if this DMG matches our architecture preferences
                if echo "$final_url" | grep -qi "universal"; then
                    dmg_url="$final_url"
                    log_verbose "Found universal DMG via redirect: $dmg_url"
                    break
                elif echo "$final_url" | grep -qi "$system_arch"; then
                    dmg_url="$final_url"
                    log_verbose "Found architecture-specific DMG via redirect: $dmg_url"
                    break
                elif [[ -z "$dmg_url" ]]; then
                    # Use this as fallback if no better match found
                    dmg_url="$final_url"
                    log_verbose "Found DMG via redirect (fallback): $dmg_url"
                fi
            fi
        done
    fi
    
    # If still no URL found, take the first DMG from direct links
    if [[ -z "$dmg_url" ]]; then
        dmg_url=$(echo "$page_content" | grep -oE 'href="[^"]*\.dmg[^"]*"' | sed 's/href="//g; s/"//g' | head -1)
        if [[ -n "$dmg_url" && ! "$dmg_url" =~ ^https?:// ]]; then
            dmg_url="$web_url$dmg_url"
        fi
    fi
    
    if [[ -z "$dmg_url" ]]; then
        log_error "No DMG download link found on release page: $web_url"
        log_error "  Please check the URL or use a different installer type"
        return 1
    fi
    
    log_info "  Would download DMG from: $dmg_url"
}

# Discover Synergy release DMG URL (for dry-run)
discover_synergy_release_dmg_url() {
    local app_name="$1"
    local web_url="$2"
    
    # Get system architecture
    local system_arch
    system_arch=$(get_system_architecture)
    log_verbose "System architecture: $system_arch"
    
    # Fetch the webpage with timeout
    log_verbose "Fetching Synergy release page: $web_url"
    local page_content
    local curl_exit_code
    page_content=$(curl -s --max-time 10 --connect-timeout 5 "$web_url" 2>/dev/null)
    curl_exit_code=$?

    if [[ $curl_exit_code -ne 0 ]]; then
        log_error "Failed to fetch Synergy release page: $web_url (curl exit code: $curl_exit_code)"
        return 1
    fi

    if [[ -z "$page_content" ]]; then
        log_error "Failed to fetch Synergy release page: $web_url (empty response)"
        return 1
    fi
    
    # Extract JSON data from JavaScript blocks
    log_verbose "Extracting JSON data from JavaScript blocks"
    local json_data
    json_data=$(echo "$page_content" | grep -oE '\\"mac\\":\[{[^]]+\}' | head -1)
    
    if [[ -z "$json_data" ]]; then
        log_error "No JSON data found in Synergy release page"
        return 1
    fi
    
    # Clean the JSON data by removing escaped quotes and adding missing braces
    json_data=$(echo "$json_data" | sed 's/\\"/"/g')
    json_data="{$json_data}"
    log_verbose "Cleaned JSON data: $json_data"
    
    # Parse JSON to find architecture-specific DMG using regex (more robust than jq for malformed JSON)
    local dmg_filename
    # First try to find exact architecture match (Arm64 for arm64, X64 for x86_64)
    if [[ "$system_arch" == "arm64" ]]; then
        log_verbose "Looking for Arm64 architecture using regex"
        dmg_filename=$(echo "$json_data" | grep -oE '"arch":"Arm64"[^}]*"fileName":"([^"]+)"' | sed 's/.*"fileName":"\([^"]*\)".*/\1/')
        log_verbose "Found filename: '$dmg_filename'"
    elif [[ "$system_arch" == "x86_64" ]]; then
        log_verbose "Looking for X64 architecture using regex"
        dmg_filename=$(echo "$json_data" | grep -oE '"arch":"X64"[^}]*"fileName":"([^"]+)"' | sed 's/.*"fileName":"\([^"]*\)".*/\1/')
        log_verbose "Found filename: '$dmg_filename'"
    fi
    
    # If no exact match, try Universal
    if [[ -z "$dmg_filename" || "$dmg_filename" == "null" ]]; then
        log_verbose "Looking for Universal architecture using regex"
        dmg_filename=$(echo "$json_data" | grep -oE '"arch":"Universal"[^}]*"fileName":"([^"]+)"' | sed 's/.*"fileName":"\([^"]*\)".*/\1/')
    fi
    
    # If still no match, take the first available
    if [[ -z "$dmg_filename" || "$dmg_filename" == "null" ]]; then
        log_verbose "Looking for any filename using regex"
        dmg_filename=$(echo "$json_data" | grep -oE '"fileName":"([^"]+)"' | head -1 | sed 's/"fileName":"\([^"]*\)".*/\1/')
    fi
    
    if [[ -z "$dmg_filename" || "$dmg_filename" == "null" ]]; then
        log_error "No DMG filename found for architecture $system_arch in Synergy JSON data"
        return 1
    fi
    
    # Construct the full download URL
    local dmg_url="https://symless.com/synergy/download/package/synergy-personal-v3/macos-12.0/$dmg_filename"
    
    log_info "  Would download DMG from: $dmg_url"
}

# Discover App Store ID (for dry-run)
discover_app_store_id() {
    local app_name="$1"
    local app_store_id_or_name="$2"
    
    # If it's already a numeric ID, just show it
    if [[ "$app_store_id_or_name" =~ ^[0-9]+$ ]]; then
        log_info "  Would install App Store ID: $app_store_id_or_name"
        return 0
    fi
    
    # Search for the app name
    log_verbose "Searching App Store for: $app_name"
    local search_results
    search_results=$(mas search "$app_name" 2>/dev/null)
    
    if [[ -z "$search_results" ]]; then
        log_warning "  No results found for App Store search: $app_name"
        return 1
    fi
    
    # Look for exact matches first (case-insensitive)
    local exact_matches
    exact_matches=$(echo "$search_results" | grep -i "^[ ]*[0-9][0-9 ]*  $app_name" | awk '{print $1}')
    
    if [[ -n "$exact_matches" ]]; then
        # Count exact matches
        local exact_count
        exact_count=$(echo "$exact_matches" | wc -l | tr -d ' ')
        
        if [[ "$exact_count" -eq 1 ]]; then
            log_info "  Would install App Store ID: $exact_matches (exact match)"
        else
            # Multiple exact matches - pick the first one and warn
            local first_id
            first_id=$(echo "$exact_matches" | head -1)
            log_info "  Would install App Store ID: $first_id (first of $exact_count exact matches)"
            log_verbose "  All exact matches:"
            echo "$exact_matches" | while read -r id; do
                log_verbose "    - $id"
            done
        fi
    else
        # No exact matches, look for any matches
        local all_ids
        all_ids=$(echo "$search_results" | awk '{print $1}' | grep -E '^[0-9]+$')
        
        # Count the number of IDs found
        local id_count
        id_count=$(echo "$all_ids" | wc -l | tr -d ' ')
        
        if [[ "$id_count" -eq 0 ]]; then
            log_warning "  No valid App Store IDs found for: $app_name"
            return 1
        elif [[ "$id_count" -eq 1 ]]; then
            log_info "  Would install App Store ID: $all_ids"
        else
            log_warning "  Multiple App Store IDs found for '$app_name' (no exact matches):"
            echo "$all_ids" | while read -r id; do
                log_warning "    - $id"
            done
            log_warning "  Please specify the exact App Store ID in your configuration"
            return 1
        fi
    fi
}

# Install app from GitHub release
install_github_release_dmg() {
    local app_name="$1"
    local repo_url="$2"
    local app_path="$3"
    
    if is_app_installed "$app_name" "$app_path"; then
        return 0
    fi
    
    log_info "Installing '$app_name' from GitHub release..."
    
    # Extract owner/repo from URL
    local repo_owner_repo
    if [[ "$repo_url" =~ github\.com/([^/]+)/([^/]+) ]]; then
        repo_owner_repo="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    else
        log_error "Invalid GitHub repository URL: $repo_url"
        return 1
    fi
    
    # Get latest release info
    log_verbose "Fetching latest release for $repo_owner_repo"
    local release_info
    local curl_exit_code
    release_info=$(curl -s --max-time 10 --connect-timeout 5 "https://api.github.com/repos/$repo_owner_repo/releases/latest" 2>/dev/null)
    curl_exit_code=$?
    
    if [[ $curl_exit_code -ne 0 ]]; then
        log_error "Failed to fetch release information for $repo_owner_repo (curl exit code: $curl_exit_code)"
        return 1
    fi
    
    if [[ -z "$release_info" ]]; then
        log_error "Failed to fetch release information for $repo_owner_repo (empty response)"
        return 1
    fi
    
    # Get system architecture
    local system_arch
    system_arch=$(get_system_architecture)
    log_verbose "System architecture: $system_arch"
    
    # Find appropriate DMG asset
    log_verbose "Searching for DMG assets in GitHub release..."
    local dmg_url
    dmg_url=$(echo "$release_info" | jq -r --arg arch "$system_arch" '
        .assets[] | 
        select(.name | endswith(".dmg")) |
        select(.name | test("universal|" + $arch + "|silicon|apple"; "i")) |
        .browser_download_url' | head -1)
    
    if [[ -z "$dmg_url" || "$dmg_url" == "null" ]]; then
        # Fallback to any DMG
        dmg_url=$(echo "$release_info" | jq -r '.assets[] | select(.name | endswith(".dmg")) | .browser_download_url' | head -1)
    fi
    
    if [[ -z "$dmg_url" || "$dmg_url" == "null" ]]; then
        log_error "No DMG asset found in latest release for $repo_owner_repo"
        log_error "  Please check the repository URL or use a different installer type"
        return 1
    fi
    
    log_verbose "Found DMG URL: $dmg_url"
    
    # Download and install DMG
    local installer_name
    # Handle URLs with query parameters by extracting just the path and adding .dmg extension
    if [[ "$dmg_url" =~ ^https?:// ]]; then
        # Extract the path part before query parameters and add .dmg extension
        local url_path
        url_path=$(echo "$dmg_url" | sed 's/[?&].*$//' | sed 's/.*\///')
        if [[ "$url_path" == *".dmg" ]]; then
            installer_name="$url_path"
        else
            installer_name="${app_name}.dmg"
        fi
    else
        installer_name=$(basename "$dmg_url")
    fi
    install_dmg_app "$app_name" "$dmg_url" "$app_path" "$installer_name"
}

# Install app from web release page
install_web_release_dmg() {
    local app_name="$1"
    local web_url="$2"
    local app_path="$3"
    
    if is_app_installed "$app_name" "$app_path"; then
        return 0
    fi
    
    log_info "Installing '$app_name' from web release page..."
    
    # Get system architecture
    local system_arch
    system_arch=$(get_system_architecture)
    log_verbose "System architecture: $system_arch"
    
    # Fetch the webpage
    log_verbose "Fetching release page: $web_url"
    local page_content
    local curl_exit_code
    page_content=$(curl -s --max-time 10 --connect-timeout 5 "$web_url" 2>/dev/null)
    curl_exit_code=$?
    
    if [[ $curl_exit_code -ne 0 ]]; then
        log_error "Failed to fetch release page: $web_url (curl exit code: $curl_exit_code)"
        return 1
    fi
    
    if [[ -z "$page_content" ]]; then
        log_error "Failed to fetch release page: $web_url (empty response)"
        return 1
    fi
    
    # Extract DMG URLs with preference order
    # Use shared function to find DMG URL
    local dmg_url
    dmg_url=$(find_dmg_url_from_web_page "$web_url" "$page_content" "$system_arch")
    
    # If no direct DMG URLs found, look for redirect URLs (like Cursor's API endpoints)
    if [[ -z "$dmg_url" ]]; then
        log_verbose "No direct DMG URLs found, checking for redirect URLs..."
        
        # Look for hrefs that might be redirect URLs (containing download, api, etc.)
        local redirect_urls
        redirect_urls=$(echo "$page_content" | grep -oE 'href="[^"]*"' | sed 's/href="//g; s/"//g' | grep -E "(download|api|release)" | while read -r url; do
            # Convert relative URLs to absolute
            if [[ "$url" =~ ^https?:// ]]; then
                echo "$url"
            else
                echo "$web_url$url"
            fi
        done)
        
        # Try each redirect URL to see if it leads to a DMG
        for redirect_url in $redirect_urls; do
            log_verbose "Checking redirect URL: $redirect_url"
            
            # Follow redirects and check if the final URL is a DMG
            local final_url
            final_url=$(curl -s --max-time 5 --connect-timeout 3 -I "$redirect_url" 2>/dev/null | grep -i "^location:" | sed 's/location: *//i' | tr -d '\r\n')
            
            if [[ -n "$final_url" ]] && echo "$final_url" | grep -qi "\.dmg"; then
                # Check if this DMG matches our architecture preferences
                if echo "$final_url" | grep -qi "universal"; then
                    dmg_url="$final_url"
                    log_verbose "Found universal DMG via redirect: $dmg_url"
                    break
                elif echo "$final_url" | grep -qi "$system_arch"; then
                    dmg_url="$final_url"
                    log_verbose "Found architecture-specific DMG via redirect: $dmg_url"
                    break
                elif [[ -z "$dmg_url" ]]; then
                    # Use this as fallback if no better match found
                    dmg_url="$final_url"
                    log_verbose "Found DMG via redirect (fallback): $dmg_url"
                fi
            fi
        done
    fi
    
    # If still no URL found, take the first DMG from direct links
    if [[ -z "$dmg_url" ]]; then
        dmg_url=$(echo "$page_content" | grep -oE 'href="[^"]*\.dmg[^"]*"' | sed 's/href="//g; s/"//g' | head -1)
        if [[ -n "$dmg_url" && ! "$dmg_url" =~ ^https?:// ]]; then
            dmg_url="$web_url$dmg_url"
        fi
    fi
    
    if [[ -z "$dmg_url" ]]; then
        log_error "No DMG download link found on release page: $web_url"
        log_error "  Please check the URL or use a different installer type"
        return 1
    fi
    
    log_verbose "Found DMG URL: $dmg_url"
    
    # Download and install DMG
    local installer_name
    # Handle URLs with query parameters by extracting just the path and adding .dmg extension
    if [[ "$dmg_url" =~ ^https?:// ]]; then
        # Extract the path part before query parameters and add .dmg extension
        local url_path
        url_path=$(echo "$dmg_url" | sed 's/[?&].*$//' | sed 's/.*\///')
        if [[ "$url_path" == *".dmg" ]]; then
            installer_name="$url_path"
        else
            installer_name="${app_name}.dmg"
        fi
    else
        installer_name=$(basename "$dmg_url")
    fi
    install_dmg_app "$app_name" "$dmg_url" "$app_path" "$installer_name"
}

# Install app via custom installer command
install_custom_app() {
    local app_name="$1"
    local install_command="$2"
    local app_path="$3"
    
    if is_app_installed "$app_name" "$app_path"; then
        return 0
    fi
    
    log_info "Installing '$app_name' via custom installer..."
    eval "$install_command"
    log_success "Successfully installed '$app_name'"
}

# Resolve App Store ID from app name
resolve_app_store_id() {
    local app_name="$1"
    local app_store_id="$2"
    
    # If it's already a numeric ID, return it
    if [[ "$app_store_id" =~ ^[0-9]+$ ]]; then
        echo "$app_store_id"
        return 0
    fi
    
    # Search for the app name
    log_verbose "Searching App Store for: $app_name"
    local search_results
    search_results=$(mas search "$app_name" 2>/dev/null)
    
    if [[ -z "$search_results" ]]; then
        log_error "No results found for App Store search: $app_name"
        return 1
    fi
    
    # Look for exact matches first (case-insensitive)
    local exact_matches
    exact_matches=$(echo "$search_results" | grep -i "^[ ]*[0-9][0-9 ]*  $app_name" | awk '{print $1}')
    
    if [[ -n "$exact_matches" ]]; then
        # Count exact matches
        local exact_count
        exact_count=$(echo "$exact_matches" | wc -l | tr -d ' ')
        
        if [[ "$exact_count" -eq 1 ]]; then
            log_verbose "Found exact match App Store ID: $exact_matches"
            echo "$exact_matches"
            return 0
        else
            # Multiple exact matches - pick the first one and warn
            local first_id
            first_id=$(echo "$exact_matches" | head -1)
            log_warning "Multiple exact matches found for '$app_name', using first one: $first_id"
            log_verbose "All exact matches:"
            echo "$exact_matches" | while read -r id; do
                log_verbose "  - $id"
            done
            echo "$first_id"
            return 0
        fi
    fi
    
    # No exact matches, look for any matches
    local all_ids
    all_ids=$(echo "$search_results" | awk '{print $1}' | grep -E '^[0-9]+$')
    
    # Count the number of IDs found
    local id_count
    id_count=$(echo "$all_ids" | wc -l | tr -d ' ')
    
    if [[ "$id_count" -eq 0 ]]; then
        log_error "No valid App Store IDs found for: $app_name"
        return 1
    elif [[ "$id_count" -eq 1 ]]; then
        log_verbose "Found App Store ID: $all_ids"
        echo "$all_ids"
        return 0
    else
        log_error "Multiple App Store IDs found for '$app_name' (no exact matches):"
        echo "$all_ids" | while read -r id; do
            log_error "  - $id"
        done
        log_error "Please specify the exact App Store ID in your configuration"
        return 1
    fi
}

# Install app from Mac App Store
# Install Synergy release DMG
install_synergy_release_dmg() {
    local app_name="$1"
    local web_url="$2"
    local app_path="$3"

    if is_app_installed "$app_name" "$app_path"; then
        return 0
    fi

    log_info "Installing '$app_name' from Synergy release page..."

    # Get system architecture
    local system_arch
    system_arch=$(get_system_architecture)
    log_verbose "System architecture: $system_arch"

    # Fetch the webpage with timeout
    log_verbose "Fetching Synergy release page: $web_url"
    local page_content
    local curl_exit_code
    page_content=$(curl -s --max-time 10 --connect-timeout 5 "$web_url" 2>/dev/null)
    curl_exit_code=$?

    if [[ $curl_exit_code -ne 0 ]]; then
        log_error "Failed to fetch Synergy release page: $web_url (curl exit code: $curl_exit_code)"
        return 1
    fi

    if [[ -z "$page_content" ]]; then
        log_error "Failed to fetch Synergy release page: $web_url (empty response)"
        return 1
    fi

    # Extract JSON data from JavaScript blocks
    log_verbose "Extracting JSON data from JavaScript blocks"
    local json_data
    json_data=$(echo "$page_content" | grep -oE '\\"mac\\":\[{[^]]+\}' | head -1)

    if [[ -z "$json_data" ]]; then
        log_error "No JSON data found in Synergy release page"
        return 1
    fi

    # Clean the JSON data by removing escaped quotes and adding missing braces
    json_data=$(echo "$json_data" | sed 's/\\"/"/g')
    json_data="{$json_data}"

    # Parse JSON to find architecture-specific DMG using regex (more robust than jq for malformed JSON)
    local dmg_filename
    # First try to find exact architecture match (Arm64 for arm64, X64 for x86_64)
    if [[ "$system_arch" == "arm64" ]]; then
        dmg_filename=$(echo "$json_data" | grep -oE '"arch":"Arm64"[^}]*"fileName":"([^"]+)"' | sed 's/.*"fileName":"\([^"]*\)".*/\1/')
    elif [[ "$system_arch" == "x86_64" ]]; then
        dmg_filename=$(echo "$json_data" | grep -oE '"arch":"X64"[^}]*"fileName":"([^"]+)"' | sed 's/.*"fileName":"\([^"]*\)".*/\1/')
    fi
    
    # If no exact match, try Universal
    if [[ -z "$dmg_filename" || "$dmg_filename" == "null" ]]; then
        dmg_filename=$(echo "$json_data" | grep -oE '"arch":"Universal"[^}]*"fileName":"([^"]+)"' | sed 's/.*"fileName":"\([^"]*\)".*/\1/')
    fi
    
    # If still no match, take the first available
    if [[ -z "$dmg_filename" || "$dmg_filename" == "null" ]]; then
        dmg_filename=$(echo "$json_data" | grep -oE '"fileName":"([^"]+)"' | head -1 | sed 's/"fileName":"\([^"]*\)".*/\1/')
    fi

    if [[ -z "$dmg_filename" || "$dmg_filename" == "null" ]]; then
        log_error "No DMG filename found for architecture $system_arch in Synergy JSON data"
        return 1
    fi

    # Construct the full download URL
    local dmg_url="https://symless.com/synergy/download/package/synergy-personal-v3/macos-12.0/$dmg_filename"
    log_verbose "Found DMG URL: $dmg_url"

    # Download and install DMG
    install_dmg_app "$app_name" "$dmg_url" "$app_path" "$dmg_filename"
}

install_mas_app() {
    local app_name="$1"
    local app_store_id_or_name="$2"
    local app_path="$3"
    
    if is_app_installed "$app_name" "$app_path"; then
        return 0
    fi
    
    log_info "Installing '$app_name' from Mac App Store..."
    
    # Resolve the App Store ID
    local app_store_id
    if ! app_store_id=$(resolve_app_store_id "$app_name" "$app_store_id_or_name"); then
        log_error "Failed to resolve App Store ID for '$app_name'"
        return 1
    fi
    
    # Install the app
    log_verbose "Installing App Store ID: $app_store_id"
    if mas install "$app_store_id"; then
        log_success "Successfully installed '$app_name' from Mac App Store"
    else
        log_error "Failed to install '$app_name' from Mac App Store"
        return 1
    fi
}

# Install app via asdf
install_asdf_app() {
    local app_name="$1"
    local version="$2"
    
    # Check if asdf is installed
    if ! command -v asdf >/dev/null 2>&1; then
        log_error "asdf is not installed. Please install it first."
        return 1
    fi
    
    # Check if plugin is installed
    if ! asdf plugin list | grep -q "^$app_name$"; then
        log_info "Adding asdf plugin for $app_name"
        asdf plugin add "$app_name"
    fi
    
    # Check if version is installed
    log_verbose "Checking if $app_name version $version is already installed..."
    if asdf list "$app_name" | grep -q "$version"; then
        log_info "Version $version of $app_name is already installed via asdf"
        return 0
    fi
    
    log_info "Installing $app_name version $version via asdf..."
    asdf install "$app_name" "$version"
    asdf set --home "$app_name" "$version"
    ASDF_INSTALLS_OCCURRED=true
    log_success "Successfully installed $app_name version $version via asdf"
}

# Parse structured config file
parse_apps_config() {
    local config_file="$1"
    
    log_verbose "Parsing config file: $config_file"
    
    while IFS= read -r line; do
        # Skip empty lines and comments
        if [[ -z "$line" ]] || [[ "$line" =~ ^#.*$ ]]; then
            continue
        fi
        
        log_verbose "Processing line: '$line'"
        
        # Parse structured format: type=app_name::install_method::install_data::app_path
        if [[ "$line" =~ ^([^=]+)=([^:]+)::([^:]+)::(.+)::(.+)$ ]]; then
            local app_type="${BASH_REMATCH[1]}"
            local app_name="${BASH_REMATCH[2]}"
            local install_method="${BASH_REMATCH[3]}"
            local install_data="${BASH_REMATCH[4]}"
            local app_path="${BASH_REMATCH[5]}"
            
            log_verbose "Found app: $app_name (type: $app_type, method: $install_method)"
            
            case "$app_type" in
                "custom")
                    case "$install_method" in
                        "command")
                            install_custom_app "$app_name" "$install_data" "$app_path"
                            ;;
                        "dmg")
                            local installer_name
                            # Handle URLs with query parameters by extracting just the path and adding .dmg extension
                            if [[ "$install_data" =~ ^https?:// ]]; then
                                # Extract the path part before query parameters and add .dmg extension
                                local url_path
                                url_path=$(echo "$install_data" | sed 's/[?&].*$//' | sed 's/.*\///')
                                if [[ "$url_path" == *".dmg" ]]; then
                                    installer_name="$url_path"
                                else
                                    installer_name="${app_name}.dmg"
                                fi
                            else
                                installer_name=$(basename "$install_data")
                            fi
                            install_dmg_app "$app_name" "$install_data" "$app_path" "$installer_name"
                            ;;
                        "zip")
                            local installer_name
                            # Handle URLs with query parameters by extracting just the path and adding .zip extension
                            if [[ "$install_data" =~ ^https?:// ]]; then
                                # Extract the path part before query parameters and add .zip extension
                                local url_path
                                url_path=$(echo "$install_data" | sed 's/[?&].*$//' | sed 's/.*\///')
                                if [[ "$url_path" == *".zip" ]]; then
                                    installer_name="$url_path"
                                else
                                    installer_name="${app_name}.zip"
                                fi
                            else
                                installer_name=$(basename "$install_data")
                            fi
                            install_zip_app "$app_name" "$install_data" "$app_path" "$installer_name"
                            ;;
                        "dmg_github_release")
                            install_github_release_dmg "$app_name" "$install_data" "$app_path"
                            ;;
                        "dmg_web_release")
                            install_web_release_dmg "$app_name" "$install_data" "$app_path"
                            ;;
                        "dmg_synergy_release")
                            install_synergy_release_dmg "$app_name" "$install_data" "$app_path"
                            ;;
                        "manual")
                            log_warning "Manual installation required for $app_name: $install_data"
                            ;;
                        *)
                            log_warning "Unknown install method '$install_method' for $app_name"
                            ;;
                    esac
                    ;;
                "brew")
                    case "$install_method" in
                        "install")
                            install_brew_app "$app_name" "brew install $install_data"
                            ;;
                        *)
                            log_warning "Unknown brew method '$install_method' for $app_name"
                            ;;
                    esac
                    ;;
                "asdf")
                    case "$install_method" in
                        "install")
                            install_asdf_app "$app_name" "$install_data"
                            ;;
                        *)
                            log_warning "Unknown asdf method '$install_method' for $app_name"
                            ;;
                    esac
                    ;;
                "appstore")
                    case "$install_method" in
                        "install")
                            install_mas_app "$app_name" "$install_data" "$app_path"
                            ;;
                        "manual")
                            log_warning "App Store app '$app_name' - please install manually"
                            ;;
                        *)
                            log_warning "Unknown install method '$install_method' for App Store app '$app_name'"
                            ;;
                    esac
                    ;;
                *)
                    log_warning "Unknown app type '$app_type' for $app_name"
                    ;;
            esac
        else
            log_warning "Invalid config line format: $line"
        fi
        
    done < "$config_file"
}

# Apply zshrc modifications
apply_zshrc_modifications() {
    local zshrc_file="$HOME/.zshrc"
    local modifications_file="$CONF_DIR/zshrc_modifications"
    
    if [[ ! -f "$modifications_file" ]]; then
        log_warning "zshrc_modifications file not found at $modifications_file"
        return 0
    fi
    
    # Check if modifications are already applied first
    local marker="# macOS Setup Script Modifications"
    if [[ -f "$zshrc_file" ]] && grep -q "$marker" "$zshrc_file"; then
        log_info "zshrc modifications already applied"
        return 0
    fi
    
    log_info "Applying zshrc modifications..."
    
    # Create backup only if we're going to make changes
    if [[ -f "$zshrc_file" ]]; then
        cp "$zshrc_file" "$zshrc_file.backup.$(date +%Y%m%d_%H%M%S)"
        log_verbose "Created backup of existing .zshrc"
    fi
    
    # Add modifications
    {
        echo ""
        echo "$marker"
        echo "# Added on $(date)"
        echo "# ========================================"
        cat "$modifications_file"
        echo ""
        echo "# End of macOS Setup Script Modifications"
    } >> "$zshrc_file"
    
    log_success "zshrc modifications applied successfully"
    return 1  # Indicate changes were made
}

# Cleanup old installers
cleanup_installers() {
    log_info "Cleaning up old installers..."
    
    # Common installer locations
    local download_dir="$HOME/Downloads"
    local temp_dir="/tmp"
    
    # Find and remove common installer files
    local installer_patterns=("*.dmg" "*.pkg" "*.zip" "installer*" "*install*")
    
    for pattern in "${installer_patterns[@]}"; do
        # Clean Downloads directory
        if [[ -d "$download_dir" ]]; then
            find "$download_dir" -name "$pattern" -type f -mtime +7 -delete 2>/dev/null || true
        fi
        
        # Clean temp directory
        find "$temp_dir" -name "$pattern" -type f -mtime +1 -delete 2>/dev/null || true
    done
    
    log_success "Cleanup completed"
}

# Regenerate asdf shims if needed
regenerate_asdf_shims() {
    if [[ "$ASDF_INSTALLS_OCCURRED" == "true" ]]; then
        log_info "Regenerating asdf shims..."
        if command -v asdf >/dev/null 2>&1; then
            asdf reshim
            log_success "asdf shims regenerated successfully"
        else
            log_warning "asdf not found, skipping shim regeneration"
        fi
    fi
}

# Main function
main() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Starting macOS setup script (DRY RUN MODE)..."
    else
        log_info "Starting macOS setup script..."
    fi
    
    # Check macOS version
    check_macos_version
    
    # Check what needs to be installed (dry run)
    check_what_needs_installation
    
    # Only request sudo if we actually need it (and not in dry-run mode)
    if [[ "$SUDO_REQUIRED" == "true" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "Elevated permissions would be required for installation"
        else
            log_info "Elevated permissions required for installation"
            validate_sudo_access
        fi
    else
        log_info "No elevated permissions required - all items are already installed or configured"
    fi
    
    # In dry-run mode, just show what would be done and exit
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN COMPLETE - No changes were made"
        log_info "Run without --dry-run to perform actual installations"
        return 0
    fi
    
    # Install Homebrew first (if needed)
    install_homebrew
    
    # Install apps from all .conf files in conf.d/ directory
    log_info "Installing apps from configuration files..."
    local conf_files
    if [[ "$INSTALL_PERSONAL_APPS" == "true" ]]; then
        # Include all .conf files when -p flag is used
        conf_files=$(find "$CONF_DIR" -name "*.conf" -type f 2>/dev/null | sort)
    else
        # Exclude personal_* files when -p flag is not used
        conf_files=$(find "$CONF_DIR" -name "*.conf" -type f 2>/dev/null | grep -v "/personal_" | sort)
    fi
    
    if [[ -n "$conf_files" ]]; then
        while IFS= read -r conf_file; do
            if [[ -f "$conf_file" ]]; then
                log_verbose "Processing config file: $conf_file"
                parse_apps_config "$conf_file"
            fi
        done <<< "$conf_files"
    else
        log_warning "No .conf files found in $CONF_DIR"
    fi
    
    # Apply zshrc modifications
    local zshrc_changes_made=false
    if apply_zshrc_modifications; then
        zshrc_changes_made=false
    else
        zshrc_changes_made=true
    fi
    
    # Regenerate asdf shims if any asdf installations occurred
    regenerate_asdf_shims
    
    # Cleanup if requested
    if [[ "$CLEANUP_INSTALLERS" == "true" ]]; then
        cleanup_installers
    fi
    
    log_success "Setup completed successfully!"
    
    # Only show reload message if changes were actually made
    if [[ "$zshrc_changes_made" == "true" ]]; then
        log_info "Please restart your terminal or run 'source ~/.zshrc' to apply zshrc changes"
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--personal)
            INSTALL_PERSONAL_APPS=true
            shift
            ;;
        -c|--cleanup)
            CLEANUP_INSTALLERS=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Run main function
main
