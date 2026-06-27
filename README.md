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
- **Filter by classification** — serif, sans-serif, slab serif, script, display,
  monospaced, or symbol, derived automatically from each font (no tagging needed).
- **Filter by width** — condensed, regular, or expanded.
- **Override Style/Width** — when auto-detection is missing or wrong, set the values
  yourself (per font or across a multi-selection). Overrides live only in this app
  (font files are untouched), persist on-device, and revert per-field. A **Needs
  Style** toggle surfaces every font that still needs classifying.
- **Multi-select** to bulk edit, activate/deactivate, or export many families at once.
- **Group** fonts by family, collection, or source directory.
- **Download as…** — export any font to your choice of format (desktop OTF/TTF,
  WOFF, or WOFF2), per style or the whole family at once. Conversion is invisible:
  pick a format and you get the file.
- **Convert web fonts** — drag a `.woff` / `.woff2` onto the window (or use
  *File ▸ Convert Web Font…*) to turn it into an installable desktop font. The
  result is saved and activated immediately, so it's usable right away.

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
| Classification | CoreText symbolic traits → PANOSE (OS/2 table) → name heuristic |
| Persistence | Local activation state (UserDefaults / lightweight JSON) |
| Single-face extraction | Assembled from `CTFontCopyTable` (works across `.ttc`/`.dfont`) |
| WOFF wrap/unwrap | Pure Swift via the Compression framework (zlib) |
| WOFF2 wrap/unwrap | Bundled Google [`woff2`](https://github.com/google/woff2) + [`brotli`](https://github.com/google/brotli), via the `WOFF2Kit` C++ target |

The app sandbox is **disabled** (see `FontManager.entitlements`) because the
font activation APIs require access outside the sandbox.

Conversions are lossless container/format changes (e.g. WOFF2 ⇄ OTF). The app
does **not** redraw glyph outlines, so it never converts OTF ⇄ TTF.

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

WOFF2Kit/                           # C++ static-lib target
├── woff2kit.h / woff2kit.cc        # extern "C" shim over woff2

ThirdParty/                         # Vendored, self-contained
├── woff2/                          # Google woff2 (encode + decode)
└── brotli/                         # Google brotli (woff2 dependency)
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

TBD for Font Manager itself. Bundled third-party code keeps its own licenses:
[`woff2`](ThirdParty/woff2/LICENSE) (MIT) and
[`brotli`](ThirdParty/brotli/LICENSE) (MIT).

> Note: converting or exporting a font is your responsibility with respect to
> that font's license — some commercial fonts restrict format conversion.
