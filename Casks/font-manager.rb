# Homebrew Cask for Font Manager.
#
# This lives here for convenience — to actually publish it, copy this file into a tap
# repo (e.g. github.com/treyhardin/homebrew-tap) under Casks/, so users can:
#
#   brew install --cask --no-quarantine treyhardin/tap/font-manager
#
# On each release, bump `version` and `sha256` to match the uploaded .dmg
# (`shasum -a 256 Font-Manager-<version>.dmg`).
cask "font-manager" do
  version "1.0.0"
  sha256 "604e1f8d9c4fe72353def23568f976971da161d8724ff049d56b00a3115aecfe"

  url "https://github.com/treyhardin/font-manager/releases/download/v#{version}/Font-Manager-#{version}.dmg"
  name "Font Manager"
  desc "Font management app for macOS — browse, preview, activate, classify, convert"
  homepage "https://github.com/treyhardin/font-manager"

  app "Font Manager.app"

  zap trash: [
    "~/Library/Application Support/Font Manager",
    "~/Library/Preferences/co.trumancreative.FontManager.plist",
    "~/Library/Caches/co.trumancreative.FontManager",
  ]
end
