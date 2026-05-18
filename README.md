# Webiqu

[![GitHub Stars](https://img.shields.io/github/stars/Webisso/webiqu-ssh-workspace?style=for-the-badge)](https://github.com/Webisso/webiqu-ssh-workspace/stargazers)
[![GitHub Forks](https://img.shields.io/github/forks/Webisso/webiqu-ssh-workspace?style=for-the-badge)](https://github.com/Webisso/webiqu-ssh-workspace/network/members)
[![Open Issues](https://img.shields.io/github/issues/Webisso/webiqu-ssh-workspace?style=for-the-badge)](https://github.com/Webisso/webiqu-ssh-workspace/issues)
[![Last Commit](https://img.shields.io/github/last-commit/Webisso/webiqu-ssh-workspace?style=for-the-badge)](https://github.com/Webisso/webiqu-ssh-workspace/commits/main)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg?style=for-the-badge)](LICENSE)

Repository: https://github.com/Webisso/webiqu-ssh-workspace

Webiqu is a native macOS SSH workspace app built with SwiftUI and SwiftData.
It helps you manage multiple servers from one place with integrated terminal sessions, file browsing, monitoring, and saved commands.

## Download

Prebuilt macOS archives are published on the GitHub Releases page:

- https://github.com/Webisso/webiqu-ssh-workspace/releases

## Highlights

- Server and group management with a sidebar-first macOS UI
- Multi-tab terminal sessions per server
- Remote file browsing and file operations over SSH/SFTP
- Live monitoring (CPU, memory, disk) with charts and refresh controls
- Saved command snippets for repeatable workflows
- Per-server connection settings (SSH agent or key-based auth)
- App-level default key path settings used as fallback for agent mode
- Local persistence via SwiftData, with CloudKit-enabled configuration

## Tech Stack

- Swift
- SwiftUI
- SwiftData
- Charts
- AppKit (for native file panels and macOS integrations)

## Project Structure

- Webiqu/: Main app source
- Webiqu/App/: App composition and logging
- Webiqu/Data/: Models, SSH implementation, security, sync
- Webiqu/Domain/: Domain contracts and monitoring models
- Webiqu/Presentation/: Views and view models
- WebiquTests/: Unit tests
- WebiquUITests/: UI tests

## Requirements

- macOS (Apple Silicon or Intel)
- Xcode 16+
- Swift 5+

## Getting Started

1. Open `Webiqu.xcodeproj` in Xcode.
2. Select the `Webiqu` scheme.
3. Build and run.

CLI build example:

```bash
xcodebuild -project Webiqu.xcodeproj -scheme Webiqu -configuration Debug -sdk macosx build
```

## Release Packaging

Use the release helper to package a built `.app` into `dist/` and optionally create a Git tag:

```bash
scripts/release.sh --app-path webiqu.app --version 1.0.0
```

This produces:

- `dist/webiqu-<version>-macos.zip`
- `dist/webiqu-<version>-macos.zip.sha256`

To create and push a release tag after reviewing the generated files:

```bash
git tag -a v1.0.0 -m "release(v1.0.0): publish macOS build"
git push origin main
git push origin v1.0.0
```

If GitHub CLI is configured, you can then publish the archive directly from `dist/`:

```bash
gh release create v1.0.0 dist/webiqu-1.0.0-macos.zip dist/webiqu-1.0.0-macos.zip.sha256 \
	--title "Webiqu v1.0.0" \
	--notes "Initial macOS release"
```

## Core Workflows

### 1) Add a server

- Create a server group
- Add server host, port, username
- Choose authentication mode:
- `SSH Agent (Default)`
- `Private Key File`

When `SSH Agent (Default)` is selected, Webiqu can use app-level default private/public key paths if configured in app settings.

### 2) Work in server workspace

- Terminal: open multiple terminal tabs per server
- Files: browse, rename, create, delete, upload, download, and edit text files
- Monitoring: inspect CPU/memory/disk with periodic refresh
- Commands: save, edit, run reusable shell commands

### 3) Configure defaults

Use app settings to configure:

- Default private key path
- Default public key path
- Default server color

## Security Notes

- Key handling uses project security services in `Webiqu/Data/Security`.
- Private/public key paths are user-configured and resolved locally.
- Review your macOS sandbox/file permissions before distribution.

## Troubleshooting

- Build issues:
- Clean build folder in Xcode and rebuild.
- Ensure Xcode Command Line Tools are correctly selected.

- SSH connection issues:
- Verify host/port/user
- Verify selected auth mode and key paths
- Check server-side SSH permissions and known_hosts behavior

- Empty terminal tab:
- Ensure the server is connected.
- Opening a new tab creates a separate SSH-backed terminal session.

## Contributing

Contributions are welcome.

- Fork the repository
- Create a feature branch
- Submit a pull request with clear change notes

## License

This project is licensed under the MIT License. See `LICENSE` for details.
