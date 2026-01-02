# AerialFlow

A small macOS utility that fixes the Aerials screensaver bug where backgrounds don't automatically switch to the next Aerial video. AerialFlow automatically downloads Aerial videos in your preferred quality and provides hotkey support for quick access to screensaver controls.

## Features

- 🔄 **Automatic Background Rotation**: Fixes the macOS Aerials screensaver bug that prevents automatic switching between Aerial videos
- 📥 **Automatic Downloads**: Automatically downloads Aerial videos based on your preferred quality:
  - 4K (3840×2160)
  - 4K-240FPS (3840×2160 at 240 frames per second)
- ⌨️ **Hotkey Support**: Quick keyboard shortcuts for:
  - **Next Aerial**: Switch to the next Aerial background immediately
  - **Go To Screensaver**: Launch the screensaver
  - **Lock**: Lock your Mac screen
- 🎨 **Quality Selection**: Choose your preferred video quality in settings
- 🔧 **Lightweight**: Minimal resource usage, runs quietly in the background

## Requirements

- macOS 15.0 (Sequoia) or later
- Xcode 15.0 or later (for building from source)
- Swift 5.0 or later

## Installation

### Option 1: Download Pre-built Release

1. Visit the [Releases](https://github.com/yourusername/AerialFlow/releases) page
2. Download the latest `.dmg` file
3. Open the downloaded file and drag `AerialFlow.app` to your Applications folder
4. Open AerialFlow from Applications (you may need to allow it in System Settings > Privacy & Security)

### Option 2: Build from Source

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/AerialFlow.git
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
4. Select your preferred video quality (4K or 4K-240FPS)
5. AerialFlow will begin downloading videos in the background

### Menu Bar Controls

- Click the menu bar icon to:
  - View current status
  - Access settings
  - Manually trigger next Aerial
  - Open diagnostics view

### Hotkeys

Configure hotkeys in System Settings > Keyboard > Keyboard Shortcuts > App Shortcuts:

- **Next Aerial**: Switch to the next Aerial background
- **Go To Screensaver**: Launch screensaver immediately
- **Lock**: Lock your Mac

Default hotkeys can be customized in the app settings.

### Settings

Access settings via the menu bar icon:

- **Video Quality**: Choose between 4K and 4K-240FPS
- **Rotation Interval**: Set how often backgrounds should rotate (if applicable)
- **Hotkey Configuration**: Customize keyboard shortcuts
- **Download Preferences**: Manage download behavior and storage

## How It Works

AerialFlow works by:

1. **Catalog Management**: Maintains a local catalog of available Aerial videos
2. **Automatic Downloads**: Downloads videos in your preferred quality when available
3. **Rotation Control**: Manages the macOS wallpaper rotation to ensure Aerials switch properly
4. **System Integration**: Integrates with macOS wallpaper and screensaver systems

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
- Check System Settings > Privacy & Security for network permissions

### Hotkeys Not Working

- Ensure AerialFlow has Accessibility permissions:
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

This project is open source and available under the [MIT License](LICENSE).

Copyright (c) 2026 [Second Arrow](https://github.com/secondarrow)

## Acknowledgments

- [Second Arrow](https://github.com/secondarrow) - Development organization
- Apple for the beautiful Aerial screensaver videos
- The macOS community for inspiration and feedback

## Support

If you encounter any issues or have questions:

1. Check the [Issues](https://github.com/yourusername/AerialFlow/issues) page
2. Open a new issue with:
   - macOS version
   - AerialFlow version
   - Steps to reproduce
   - Error messages (if any)

---

Made with ❤️ for macOS users who love beautiful backgrounds
