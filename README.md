# Font Manager

An actually good font management app for macOS.

Font Manager is a native macOS app for browsing, previewing, and activating or
deactivating the fonts on your system — without deleting them. It's built with
SwiftUI and talks directly to Core Text and AppKit for font enumeration and
activation.

> ⚠️ **Status:** Early development (v0.1.0). Things will change.

## Features

- **Browse** every font installed on macOS — system, user, and third-party.
- **Preview** fonts with customizable sample text and sizes.
- **Activate / deactivate** fonts on demand, without removing the files.
- **Search and filter** by font name, family, style, or classification.
- **Group** fonts by family, collection, or source directory.

## Tech Stack

- **Language:** Swift 6
- **UI:** SwiftUI
- **Platform:** macOS 14.0+ (native)
- **Frameworks:** Core Text, AppKit (for the font activation/deactivation APIs)
- **Project generation:** [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Architecture

| Concern | Approach |
| --- | --- |
| Font enumeration | `CTFontManagerCopyAvailableFontFamilyNames()` and `NSFontManager` |
| Font activation | `CTFontManagerRegisterFontsForURL(_:_:_:)` (`.user` scope) |
| Font deactivation | `CTFontManagerUnregisterFontsForURL(_:_:_:)` (`.user` scope) |
| Font metadata | `CTFontDescriptor` for weight, style, classification, file path |
| Persistence | Local activation state (UserDefaults / lightweight JSON) |

The app sandbox is **disabled** (see `FontManager.entitlements`) because the
font activation APIs require access outside the sandbox.

## Project Structure

```
FontManager/
├── FontManagerApp.swift       # App entry point
├── FontManager.entitlements   # App sandbox disabled (needed for font APIs)
├── Models/
│   └── FontItem.swift         # FontItem and FontMember data models
├── Views/
│   ├── ContentView.swift      # Main NavigationSplitView layout
│   ├── FontListView.swift     # Sidebar font list with search
│   ├── FontDetailView.swift   # Detail pane with preview and controls
│   └── DirectoriesView.swift  # Browse fonts by source directory
└── Services/
    └── FontService.swift      # Font enumeration, activation, deactivation
```

## Development

The `.xcodeproj` is generated from `project.yml` via XcodeGen and is gitignored.

```sh
# Install XcodeGen (once)
brew install xcodegen

# Regenerate the Xcode project (after a fresh clone or editing project.yml)
xcodegen generate

# Build
xcodebuild -scheme FontManager -configuration Debug build

# Build and run
xcodebuild -scheme FontManager -configuration Debug build && \
  open ~/Library/Developer/Xcode/DerivedData/FontManager-*/Build/Products/Debug/Font\ Manager.app
```

## License

TBD.
