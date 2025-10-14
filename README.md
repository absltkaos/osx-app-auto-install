# macOS Setup Script

A comprehensive setup script for macOS 15.6.1+ that installs applications and configures your shell environment with minimal user interaction.

## Features

- **Idempotent**: Safe to run multiple times - won't reinstall already installed apps
- **Configurable**: Uses markdown files to define what to install
- **Flexible**: Supports multiple installation methods (Homebrew, DMG, custom installers, asdf)
- **Shell Integration**: Automatically configures zshrc with your customizations
- **Cleanup**: Optional cleanup of old installer files

## Requirements

- macOS 15.6.1 or later
- Internet connection for downloading applications
- Administrator privileges (sudo access) - **only required if installations are needed**
- asdf version 0.16.0 or later (for asdf-managed tools)

## Usage

**Note**: The script will only request sudo access if installations are actually needed. If everything is already installed, it will complete without requiring elevated permissions.

```bash
# Basic usage - install all apps from .conf files (excluding personal_*)
./setup.sh

# Install all apps including personal_* files
./setup.sh -p

# Install all apps and cleanup old installers
./setup.sh -p -c

# Verbose output for debugging
./setup.sh -v

# Dry run - show what would be installed without making changes
./setup.sh -d

# Detailed dry run with verbose output
./setup.sh -d -v

# Show help
./setup.sh -h
```

### Command Line Options

- `-p, --personal`: Install personal apps (files prefixed with 'personal_')
- `-c, --cleanup`: Clean up old installers (default: false)
- `-v, --verbose`: Verbose output (default: false)
- `-d, --dry-run`: Show what would be installed without making changes
- `-h, --help`: Show help message

## Configuration Files

The script automatically reads **all** `.conf` files from the `conf.d/` directory. This provides maximum flexibility - you can organize your configuration however you prefer:

### Automatic Configuration Discovery
- **All `.conf` files** in `conf.d/` are automatically processed
- **Personal file filtering** - files prefixed with `personal_` are only processed when using the `-p` flag
- **Alphabetical order** - files are processed in sorted order for predictable behavior
- **Easy organization** - create separate files for different purposes (e.g., `work_apps.conf`, `dev_tools.conf`, `personal_games.conf`)

### Example Configuration Files
- `conf.d/common_apps.conf` - Applications for all machines
- `conf.d/personal_apps.conf` - Personal applications  
- `conf.d/example.conf` - Example configurations (commented out)
- `conf.d/zshrc_modifications` - Shell customizations (not a `.conf` file, hardcoded)

**Note**: Homebrew installation is handled automatically by the script and does not need to be listed in the configuration files.

### Configuration Format

Each line in the `.conf` files follows this format:
```
type=app_name::install_method::install_data::app_path
```

**Note**: We use `::` as the delimiter instead of `|` to avoid conflicts with shell pipe commands in the install_data field.

**Types:**
- `custom` - Custom installers (DMG, commands, manual, GitHub releases, web releases)
- `brew` - Homebrew packages  
- `asdf` - asdf version manager tools
- `appstore` - Apple App Store (automatic or manual installation)

**Install Methods:**
- `command` - Execute a shell command
- `dmg` - Download and install from DMG file
- `dmg_github_release` - Download latest DMG from GitHub releases (auto-detects architecture)
- `dmg_web_release` - Download DMG from web release page (auto-detects architecture)
- `dmg_synergy_release` - Download DMG from Synergy's release webpage and extract json from javascript to build the correct download URL
- `manual` - Manual installation (logs instructions)
- `install` - Standard installation (for brew/asdf/appstore)

## Configuration Examples

### Custom Installers
```
custom=steam::dmg::https://cdn.akamai.steamstatic.com/client/installer/steam.dmg::/Applications/Steam.app
custom=devlab::command::curl -sSL https://gitlab.com/evernym/utilities/devlab/install.sh | bash::/usr/local/bin/devlab
custom=github_app::dmg_github_release::https://github.com/owner/repo::/Applications/GitHub App.app
custom=web_app::dmg_web_release::https://example.com/downloads::/Applications/Web App.app
custom=signal::manual::https://signal.org/download/::/Applications/Signal.app
```

### Homebrew Packages
```
brew=librewolf::install::librewolf --no-quarantine::/Applications/LibreWolf.app
brew=fzf::install::fzf::/usr/local/bin/fzf
```

### asdf Tools
```
asdf=kubectl::install::1.28.0::/usr/local/bin/kubectl
asdf=python::install::3.14.0::/usr/local/bin/python3.14
```

### App Store Apps
```
# Using App Store ID (recommended for reliability)
appstore=wireguard::install::1451685025::/Applications/WireGuard.app

# Using app name (will search and resolve ID automatically)
appstore=wireguard::install::WireGuard::/Applications/WireGuard.app

# Manual installation (logs instructions)
appstore=some_app::manual::App Name::/Applications/Some App.app
```

## Dry Run Mode

The `--dry-run` option allows you to see what the script would do without making any changes:

- ✅ **Checks all installations**: Shows what apps would be installed
- ✅ **Discovers URLs**: For `dmg_github_release` and `dmg_web_release`, shows the actual DMG URLs that would be downloaded
- ✅ **Resolves App Store IDs**: For App Store apps, shows which ID would be used (including automatic resolution from app names)
- ✅ **No sudo required**: Dry-run mode never asks for elevated permissions
- ✅ **Safe testing**: Perfect for testing configurations before actual installation

### Example Dry Run Output

```bash
$ ./setup.sh --dry-run -v
[INFO] Starting macOS setup script (DRY RUN MODE)...
[INFO] Will install 'cursor' from web release page
[INFO]   Would download DMG from: https://download.cursor.sh/mac/arm64
[INFO] Will install 'wireguard' from Mac App Store
[INFO]   Would install App Store ID: 1451685025 (first of 2 exact matches)
[INFO] Elevated permissions would be required for installation
[INFO] DRY RUN COMPLETE - No changes were made
```

## Idempotency

The script is designed to be idempotent:

- **Apps**: Checks if applications are already installed before attempting installation
- **zshrc**: Uses markers to detect if modifications have already been applied
- **Homebrew**: Checks if packages are already installed
- **asdf**: Checks if tools and versions are already installed

## Safety Features

- **Smart sudo handling**: Only requests elevated permissions when installations are actually needed
- **Dry run checks**: Performs all checks before requesting sudo access
- Creates backups of existing `.zshrc` before modifications
- Validates macOS version before running
- Uses temporary directories for downloads
- Properly unmounts DMG files after installation
- Comprehensive error handling and logging

## Examples

### Install only common development tools
```bash
./setup.sh
```

### Full setup with personal apps
```bash
./setup.sh -p -c -v
```

### Check what would be installed (verbose mode)
```bash
./setup.sh -v
```

## Troubleshooting

### Permission Issues
If you encounter permission issues, ensure the script is executable:
```bash
chmod +x setup.sh
```

### Homebrew Issues
If Homebrew installation fails, you may need to install Xcode Command Line Tools first:
```bash
xcode-select --install
```

### Manual App Store Apps
Apps marked for the Apple App Store require manual installation. The script will log these for your reference.

### asdf Version Compatibility
This script requires asdf version 0.16.0 or later. If you have an older version of asdf, you'll need to upgrade it first. The script uses the new `asdf set --home` command which replaced the deprecated `asdf global` command in version 0.16.0.

The script automatically runs `asdf reshim` after installing any asdf-managed tools to ensure the newly installed tools are available in your PATH.

**Idempotency**: The script properly detects when asdf tools are already installed and skips reinstallation, ensuring the script can be run multiple times safely.

## File Structure

```
Dans-OSX-setup/
├── setup.sh                 # Main setup script
├── README.md               # This file
└── conf.d/                 # Configuration files
    ├── common_apps.conf    # Common applications
    ├── personal_apps.conf  # Personal applications
    ├── zshrc_modifications # Shell customizations
    └── example.conf        # Example configuration
```

## Contributing

To add new applications or modify configurations:

1. Edit the appropriate configuration file in `conf.d/`
2. Follow the structured format: `type=app_name::install_method::install_data::app_path`
3. Test the script with verbose output: `./setup.sh -v`
4. See `conf.d/example.conf` for format examples

## License

This script is provided as-is for personal use. Modify as needed for your environment.
