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
├── FontManagerApp.swift            # App entry point + menu commands
├── FontManager.entitlements        # App sandbox disabled (needed for font APIs)
├── FontManager-Bridging-Header.h   # Exposes WOFF2Kit to Swift
├── Models/
│   └── FontItem.swift              # FontItem and FontMember data models
├── Views/
│   ├── ContentView.swift           # Main layout + drag-to-convert + toast
│   ├── FontListView.swift          # Sidebar font list with search
│   ├── FontDetailView.swift        # Detail pane: preview + Download menus
│   ├── DirectoriesView.swift       # Browse fonts by source directory
│   └── ConversionToast.swift       # Progress/result toast
└── Services/
    ├── FontService.swift           # Enumeration, activation, imported fonts, filtering
    ├── FontClassifier.swift        # Serif/sans/script… from CoreText traits + PANOSE
    ├── FontConversionEngine.swift  # Pure SFNT/WOFF plumbing (no app types)
    ├── FontConversionService.swift # Member-aware export/convert bridge
    ├── ConversionManager.swift     # Drives operations + toast state
    └── WOFF2.swift                 # Swift wrapper over the WOFF2Kit C shim

WOFF2Kit/         # C++ static-lib target: extern "C" shim over Google woff2
ThirdParty/       # Vendored woff2 + brotli sources (self-contained)
```

## Font conversion

Export ("Download as…") and web-font import share one engine. Container/format
conversions only (WOFF/WOFF2 ⇄ OTF/TTF) — outlines are never redrawn, so OTF ⇄ TTF
is intentionally out of scope. WOFF2 uses bundled `woff2`+`brotli` via `WOFF2Kit`;
WOFF uses the Compression framework; single faces are extracted from any container
via `CTFontCopyTable`. Imported fonts are tracked in UserDefaults and re-activated
on launch (`FontSource.imported`).

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
