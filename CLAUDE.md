# font-manager

An actually good font management app for macOS.

## Tech Stack

- **Language**: Swift
- **UI**: SwiftUI
- **Platform**: macOS (native)
- **Key Frameworks**: Core Text, AppKit (for font activation/deactivation APIs)

## Features

- Browse all fonts installed on macOS (system, user, and third-party)
- Preview fonts with customizable sample text and sizes
- Activate and deactivate fonts without deleting them
- Search and filter by font name, family, style, or classification
- Group fonts by family, collection, or custom tags

## Architecture

- **Font enumeration**: `CTFontManagerCopyAvailableFontFamilyNames()` and `NSFontManager`
- **Font activation**: `CTFontManagerRegisterFontsForURL(_:_:_:)` with `.user` scope
- **Font deactivation**: `CTFontManagerUnregisterFontsForURL(_:_:_:)` with `.user` scope
- **Font metadata**: `CTFontDescriptor` for weight, style, classification, file path
- **Persistence**: Track activation state locally (UserDefaults or lightweight JSON file)

## Conventions

This project is managed from the [tc-agent](../tc-agent/CLAUDE.md) workspace.
General rules and patterns are in `../tc-agent/.claude/rules/`.

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
│   └── FontDetailView.swift   # Detail pane with preview and controls
└── Services/
    └── FontService.swift      # Font enumeration, activation, deactivation
```

## Development

```sh
# Regenerate Xcode project (after changing project.yml)
xcodegen generate

# Build
xcodebuild -scheme FontManager -configuration Debug build

# Build and run
xcodebuild -scheme FontManager -configuration Debug build && open ~/Library/Developer/Xcode/DerivedData/FontManager-*/Build/Products/Debug/Font\ Manager.app
```

The `.xcodeproj` is generated from `project.yml` via XcodeGen and is gitignored.
To regenerate it after a fresh clone: `xcodegen generate`.

Update this file as the project evolves.
