# VVTerm

![iOS](https://img.shields.io/badge/iOS-16.1+-black?style=flat-square&logo=apple)
[![Swift](https://img.shields.io/badge/Swift-5.0+-F05138?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
[![Source License](https://img.shields.io/badge/Source-GPL%203.0-blue?style=flat-square)](LICENSE)
[![Sponsor](https://img.shields.io/badge/Sponsor-GitHub-ff69b4?style=flat-square&logo=github)](https://github.com/sponsors/vivy-company)

Your servers. Everywhere.

![VVTerm](/docs/preview.png)

## Overview

This is a personal fork of [VVTerm](https://github.com/vivy-company/vvterm) by
Vivy Company, changed to fit a tmux-heavy workflow on iPhone and iPad. Thanks to
the VVTerm authors for an excellent base.

VVTerm is an SSH terminal app for iOS. The current codebase targets iOS, uses Ghostty for terminal rendering, libssh2/OpenSSL for SSH transport, CloudKit for sync, and Keychain for local credential storage.

## Current State

- Main app target: `VVTerm`
- Companion target: `VVTermLiveActivity`
- Runtime target: `iOS 16.1+`
- Hardware targets: Apple Silicon / arm64 only
- App-owned code is organized under `VVTerm/App`, `VVTerm/Core`, and `VVTerm/Features`
- The repo also contains tests and native vendor builds

## Implemented Feature Areas

### Terminal and connections

- GPU-accelerated terminal rendering via `GhosttyKit`
- SSH authentication with password, SSH key, and SSH key + passphrase
- Connection modes for standard SSH, Tailscale, Mosh, Eternal Terminal, and Cloudflare Access
- Multi-session connection management with tabs, split panes, reconnect handling, and persisted session state
- tmux-aware startup, attach, install, and recovery flows
- Rich paste and clipboard helpers for terminal input
- iOS keyboard accessory support, including special keys and custom actions
- iOS Live Activity status for active terminal connections

Eternal Terminal connections use the configured SSH authentication and SSH port to run `etterminal`, then connect to `etserver` on TCP port `2022` by default. Install Eternal Terminal on the host and allow inbound traffic to the configured ET port. VVTerm's working-directory and optional tmux startup, attach, installation, and cleanup behavior also applies to ET sessions.

### Servers and organization

- Workspaces with ordering, colors, and environment grouping
- Server metadata including favorites, tags, notes, last-connected timestamps, and biometric-unlock requirements
- Pro limit enforcement for workspaces, servers, tabs, and split panes
- Local-network SSH discovery via Bonjour and subnet probing

### Remote files

- SFTP-backed remote file browser
- Directory browsing with breadcrumbs, sorting, hidden-file toggles, and persisted browser state
- File preview, upload, download, export/share, new folder, rename, move, and delete flows
- Permission editing and remote-file conflict resolution

### Security and sync

- Keychain-backed storage for SSH credentials and Cloudflare service tokens
- CloudKit sync for servers, workspaces, terminal theme preferences, and terminal accessory profile data
- Full-app lock and per-server biometric unlock
- Privacy-mode support

### Customization and productivity

- Built-in and custom terminal themes with validation, storage-path management, and sync-aware preference handling
- Customizable terminal accessory bar with reorderable actions and user-defined shortcuts
- Terminal presets for saved commands/snippets
- Settings surfaces for general, terminal, sync, keychain, pro, and about flows
- Welcome/onboarding and in-app support surfaces

### Stats

- Remote server stats collection with live CPU and memory history

## Architecture

VVTerm uses a feature-first structure for app-owned code.

```text
VVTerm/
├── App/                         # App entry, composition roots, shared root containers
├── Core/                        # Shared infrastructure and cross-feature primitives
│   ├── Logging/
│   ├── Network/
│   ├── Security/
│   ├── SSH/
│   ├── Sync/
│   ├── Terminal/                 # Includes the shared Ghostty bridge
│   └── UI/
├── Features/                    # Product features
│   ├── ConnectionViews/
│   ├── LocalDiscovery/
│   ├── RemoteFiles/
│   ├── Security/
│   ├── Servers/
│   ├── Settings/
│   ├── Stats/
│   ├── Store/
│   ├── Support/
│   ├── TerminalAccessories/
│   ├── TerminalPresets/
│   ├── TerminalSessions/         # Includes Ghostty runtime and platform UI
│   ├── TerminalThemes/
│   └── Welcome/
└── Resources/                   # Bundled assets, themes, terminfo, localizations
```

Feature modules follow these boundaries:

- `Domain`: pure types and rules
- `Application`: state, orchestration, coordinators, managers
- `Infrastructure`: persistence, transport, adapters, external integrations
- `UI`: SwiftUI/UIKit presentation

Other top-level folders in the repo:

```text
VVTerm-iOS/                     # iOS Info.plist and entitlements
VVTermLiveActivity/             # ActivityKit target
VVTermShared/                   # Shared Activity attributes and small shared types
VVTermTests/                    # Unit and integration tests
VVTermUITests/                  # UI tests
Vendor/                         # Vendored native dependencies
scripts/                        # Vendor build and OTA release scripts
docs/                           # README assets
```

## Requirements

- Apple Silicon Mac for development
- Xcode `16.0+`
- iOS `16.1+`
- `zig` and `cmake`

Install the non-Xcode build tools with Homebrew:

```bash
brew install zig cmake
```

## Building From Source

```bash
git clone https://github.com/grillermo/vvterm-app.git
cd vvterm-app

# Build native vendor libraries (GhosttyKit + libssh2/OpenSSL)
./scripts/build.sh all

# Open the project in Xcode
open VVTerm.xcodeproj
```

`./scripts/build.sh` supports `all`, `ghostty`, `ssh`, `clean`, and `help`.
The pinned Ghostty fork includes tracked selection and viewport text for native iOS
selection controls. `Vendor/libghostty/VERSION` records that fork revision.

## Dependencies

Native/vendor dependencies:

- [libghostty](https://github.com/ghostty-org/ghostty) for terminal emulation and rendering
- [libssh2](https://github.com/libssh2/libssh2) for SSH transport
- [OpenSSL](https://github.com/openssl/openssl) for cryptography

Swift package dependencies currently resolved by the Xcode project:

- [Cloudflared](https://github.com/wiedymi/swift-cloudflared)
- [swift-mosh](https://github.com/wiedymi/swift-mosh)
- [swift-et](https://github.com/wiedymi/swift-et)
- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation)
- [TweetNacl](https://github.com/bitmark-inc/tweetnacl-swiftwrap.git)

## Installation

All features are enabled in every build; there are no tiers or purchases.

### Without an Apple Developer account

Each [GitHub release](../../releases) has an **unsigned** `.ipa`. A sideloading
tool signs it on your Mac or PC with your own free Apple ID, then installs it on
your iPhone or iPad. Any of these works:

- [Sideloadly](https://sideloadly.io) (macOS or Windows): the simplest.
- [AltStore](https://altstore.io) or [SideStore](https://sidestore.io): these
  can also refresh the app from the device.

With Sideloadly:

1. Download `VVTerm-<version>-unsigned.ipa` from the latest release.
2. Install Sideloadly and connect the device over USB. On Windows, also install
   iTunes and iCloud from Apple's website, not the Microsoft Store.
3. Drag the `.ipa` into Sideloadly, enter your Apple ID, and press **Start**.
   Sideloadly signs in to Apple to create a free development certificate and
   sends your Apple ID only to Apple.
4. On the device, open **Settings → General → VPN & Device Management**, tap
   your Apple ID, and choose **Trust**.
5. On iOS 16 or later, turn on **Settings → Privacy & Security → Developer
   Mode** and restart when asked.

Limits of a free Apple ID:

- **The app expires after 7 days.** Re-sign it with the same tool before then
  (AltStore and SideStore can do this in the background). Your servers and
  settings are kept as long as you don't delete the app.
- **No iCloud sync.** Free accounts can't use CloudKit, so servers stay on the
  device. Credentials are still stored in the Keychain.
- A free Apple ID can have at most 3 sideloaded apps installed at a time.
- The Live Activity extension needs its own App ID. If the tool reports an App
  ID limit, turn off extensions in its advanced options.

### With an Apple Developer account

Signing values live outside the repository. Create `Config/Local.xcconfig`
(gitignored); it overrides the defaults in `Config/VVTerm.xcconfig`:

```text
VVTERM_BUNDLE_ID = com.yourname.vvterm
DEVELOPMENT_TEAM = ABCDE12345
```

The bundle ID also names the iCloud container (`iCloud.<bundle id>`) and the
keychain group. Then:

- **Ad-hoc OTA install**: set `VVTERM_UPLOAD_BASE` (the public URL of the file
  server that serves your releases) in `.env`. `./deploy` then bumps the
  version, builds a signed `.ipa`, publishes it with an `itms-services://`
  manifest, and prints an install page URL. A Home Screen bookmark on that URL
  always installs the newest release, and the app's **Install Latest** Home
  Screen quick action does the same. See [deploy](deploy).
- **Direct install over USB**: build for a connected device with `xcodebuild`
  and install with `xcrun devicectl device install app`.

## Documentation

- [CONTRIBUTING.md](CONTRIBUTING.md) for contribution workflow
- [SECURITY.md](SECURITY.md) for vulnerability reporting
- [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for third-party notices
- [CLA.md](CLA.md) for the contributor license agreement

## License

Source code in this repository is licensed under GNU GPL v3.0 (`LICENSE`), which applies to
any build you make from it.

Copyright © 2026 Vivy Technologies Co., Limited
