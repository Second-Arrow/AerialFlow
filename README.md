# AerialFlow

A small macOS utility that fixes the Aerials screensaver bug where backgrounds don't automatically switch to the next Aerial video. AerialFlow downloads Aerial videos on demand and provides hotkey support for quick access to wallpaper and screensaver controls.

## Features

- 🔄 **Automatic Background Rotation**: Fixes the macOS Aerials screensaver bug that prevents automatic switching between Aerial videos
- 💤 **Sleep-Aware (Energy Efficient)**: When macOS sleeps or all screens turn off, AerialFlow hibernates its scheduler (no periodic timer wakeups) and resumes intelligently when you wake your Mac
- 📥 **On-demand Downloads**: Downloads the needed Aerial video automatically (uses Apple’s 4K SDR 240fps variant when available in the system catalog)
- 🌗 **Light-Sensitive Filtering**: Optionally filter to darker Aerials outside a configurable “light allowed” time window, based on each Aerial’s preview-image brightness
- ⌨️ **Hotkey Support**: Quick keyboard shortcuts for:
  - **Next Aerial**: Switch to the next Aerial background immediately
  - **Next In Subcategory**: Advance within the current Aerial’s primary subcategory
  - **Exclude current Aerial + Next**: Exclude the current Aerial and immediately switch to the next eligible one
  - **Pause / Continue**: Toggle scheduled rotation on/off
  - **Go To Screensaver**: Launch the screensaver
- 🔧 **Lightweight**: Minimal resource usage, runs quietly in the background

## Requirements

- macOS 15.6 (Sequoia) or later
- Xcode 16 or later (for building from source)
- Swift toolchain bundled with Xcode

## Installation

### Option 1: Download Pre-built Release

1. Visit the [Releases](https://github.com/second-arrow/AerialFlow/releases) page
2. Download the latest `.dmg` file
3. Open the downloaded file and drag `AerialFlow.app` to your Applications folder
4. Open AerialFlow from Applications (you may need to allow it in System Settings > Privacy & Security)

### Option 2: Build from Source

1. Clone the repository:
   ```bash
   git clone https://github.com/second-arrow/AerialFlow.git
   cd AerialFlow
   ```

2. Open the project in Xcode:
   ```bash
   open AerialFlow/AerialFlow.xcodeproj
   ```

3. Build and run:
   - Select the `AerialFlow` scheme
   - Press `Cmd+R` to build and run, or
   - Use Product > Archive to create a distributable build

## Usage

### First Launch

1. Launch AerialFlow from Applications
2. The app will appear in your menu bar
3. Click the menu bar icon to access settings
4. Use **Next Aerial** (or scheduled rotation) to apply and download Aerials as needed

### Menu Bar Controls

- Click the menu bar icon to:
  - View current status (and errors, if any)
  - Manually trigger **Next Aerial**
  - Open **Setup…** (onboarding / permissions guidance)
  - **Pause / Continue** scheduled rotation
  - Open **Settings** / **About**

### Hotkeys

Configure hotkeys in **AerialFlow → Settings → Hotkeys**:

- **Next Aerial**: Switch to the next Aerial background
- **Next In Subcategory**: Advance within the current Aerial’s primary subcategory
- **Exclude current Aerial + Next**: Exclude current and advance
- **Pause / Continue**: Toggle scheduled rotation
- **Go To Screensaver**: Launch screensaver immediately

Hotkeys are global. If they don’t work, macOS may require **Input Monitoring** and/or **Accessibility** permissions for AerialFlow.

### Settings

Access settings via the menu bar icon:

- **Rotation**: Enable/disable scheduled rotation, choose interval, and optional random mode
- **After sleep / display off**: Choose how AerialFlow resumes rotation after your Mac wakes (keep original time left, rotate immediately, or restart the timer)
- **Light-sensitive filtering**: Enable filtering based on Aerial brightness, configure the allowed-light time range (shown in your system’s 12/24-hour format), and set the sensitivity threshold (values below 0.15 may be too strict)
- **Exclusions**: Exclude categories/subcategories/individual Aerials from selection
- **Storage**: Optionally remove excluded downloaded `.mov` files on a schedule (or run cleanup manually)
- **Hotkeys**: Set global shortcuts
- **Advanced**: Configure download timeout and (optionally) choose/reset the `Index.plist` wallpaper store path

## How It Works

AerialFlow works by:

1. **Catalog Management**: Reads Apple’s Aerial catalog (`entries.json`) as provided by macOS (`idleassetsd`)
2. **Asset Selection**: Picks the next eligible Aerial (respecting exclusions and optional light-sensitive filtering)
3. **On-demand Downloads**: Ensures the chosen Aerial video exists on disk (downloads it if missing)
4. **Wallpaper Application**: Updates the macOS wallpaper store (`Index.plist`) and reloads wallpaper pipelines
5. **Sleep-Aware Scheduling**: Hibernates rotation while your Mac sleeps or screens are off, then resumes based on your chosen behavior
6. **System Integration**: Integrates with macOS wallpaper and screensaver systems (and supports auto-updates via Sparkle)

## Project Structure

```
AerialFlow/
├── AerialFlow/
│   ├── App/              # App lifecycle and global state
│   ├── Core/             # Domain services and business logic
│   ├── Models/           # Data models and value types
│   ├── UI/               # SwiftUI views and view logic
│   └── System/           # System integration helpers
├── AerialFlowTests/      # Unit tests
└── AerialFlowUITests/    # UI tests
```

## Development

### Building

```bash
# Using Xcode
xcodebuild -project AerialFlow/AerialFlow.xcodeproj \
           -scheme AerialFlow \
           -configuration Release \
           build

# Or open in Xcode and build normally
open AerialFlow/AerialFlow.xcodeproj
```

## Releasing (website DMG, scripted)

This repo intentionally **skips App Store distribution**. Releases are produced as a **Developer ID–signed + notarized universal DMG** via scripts.

## Local unsigned builds (no Apple Developer account)

If you don’t have a Developer ID / notarization set up yet, you can still build and run locally.

Build an **unsigned universal** `.app` into `dist/unsigned/`:

```bash
bash Scripts/af build local
```

Optional: create an **unsigned DMG**:

```bash
bash Scripts/af build local --dmg
```

Optional: copy into an install directory (may require `sudo` for `/Applications`):

```bash
bash Scripts/af build local --install-to "/Applications"
```

## Homebrew installation (recommended)

Install via Homebrew Cask (from our own tap):

```bash
brew tap second-arrow/homebrew-tap
brew install --cask aerialflow
```

Upgrade later:

```bash
brew upgrade --cask aerialflow
```

### One-time setup (notarytool keychain profile)

Create a `notarytool` keychain profile on the machine that will build releases:

```bash
xcrun notarytool store-credentials "AerialFlowNotary" \
  --apple-id "<your-apple-id>" \
  --team-id "<your-team-id>" \
  --password "<app-specific-password>"
```

### Build a notarized DMG

Run the release script from the repo root:

```bash
bash Scripts/af release production --notary-profile "AerialFlowNotary"
```

Optional: specify a signing identity explicitly:

```bash
bash Scripts/af release production \
  --notary-profile "AerialFlowNotary" \
  --identity "Developer ID Application: <Name> (<TEAMID>)"
```

### Set the current version (committed)

This updates `MARKETING_VERSION` and bumps `CURRENT_PROJECT_VERSION` in the Xcode project (and commits the change).

```bash
bash Scripts/af version set 1.2.3
```

If you want to set the version without creating a git tag:

```bash
bash Scripts/af version set 1.2.3 --no-tag
```

### Output

Artifacts are written to:
- `dist/*.dmg`
- `dist/*.dmg.sha256.txt`

### Testing

```bash
# Run tests from command line
xcodebuild test \
  -project AerialFlow/AerialFlow.xcodeproj \
  -scheme AerialFlow \
  -destination 'platform=macOS'
```

### Code Style

This project follows Swift best practices:
- Swift Concurrency (`async/await`) for asynchronous operations
- Protocol-oriented design where appropriate
- Clear separation of concerns (UI, Core, Models, System)
- Comprehensive error handling
- Unit tests for core functionality

## Troubleshooting

### Videos Not Downloading

- Check your internet connection
- Verify you have sufficient disk space
- In **Settings → Tools → Diagnostics**, confirm the Aerial catalog (`entries.json`) is readable and the video storage directory is accessible
- Try increasing **Settings → Advanced → Download timeout**

### Hotkeys Not Working

- Ensure AerialFlow has **Input Monitoring** and/or **Accessibility** permissions:
  - System Settings > Privacy & Security > Input Monitoring
  - System Settings > Privacy & Security > Accessibility
  - Add AerialFlow if not present
- Verify hotkey conflicts with other applications

### Backgrounds Not Rotating

- Ensure AerialFlow is running (check menu bar)
- Verify wallpaper settings in System Settings
- Check the Diagnostics view in AerialFlow for error messages

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

MIT License — see [`LICENSE`](LICENSE).

Copyright (c) 2026 [Second Arrow](https://github.com/second-arrow)

## Acknowledgments

- [Second Arrow](https://github.com/second-arrow) - Development organization
- Apple for the beautiful Aerial screensaver videos
- The macOS community for inspiration and feedback

## Support

If you encounter any issues or have questions:

1. Check the [Issues](https://github.com/second-arrow/AerialFlow/issues) page
2. Open a new issue with:
   - macOS version
   - AerialFlow version
   - Steps to reproduce
   - Error messages (if any)

---

Made with ❤️ for macOS users who love beautiful backgrounds
