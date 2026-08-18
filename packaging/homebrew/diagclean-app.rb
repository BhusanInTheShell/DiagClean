# frozen_string_literal: true

# The GUI app, distributed as a notarised DMG. Separate from `diagclean.rb`, which is
# the formula for the `dclean` CLI — a cask and a formula can coexist in the same tap,
# and the two are genuinely different things: one installs a command, the other an
# application bundle into /Applications.
cask "diagclean-app" do
  version "0.1.0"

  # PLACEHOLDER — replace with the sha256 of the notarised DMG before tagging.
  # `Scripts/package-dmg.sh` prints it as its last line. Shipping this as-is fails loudly
  # with a checksum mismatch, which is the intended behaviour: better a clear error than
  # a plausible-looking hash nobody thought to check.
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/BhusanInTheShell/DiagClean/releases/download/mac-v#{version}/DiagClean-#{version}.dmg",
      verified: "github.com/BhusanInTheShell/DiagClean/"
  name "DiagClean"
  desc "Diagnostics, cleanup, uninstall, disk analysis, and system status for Macs"
  homepage "https://github.com/BhusanInTheShell/DiagClean"

  # Matches LSMinimumSystemVersion in the bundle. Installing on an older macOS would
  # produce an app that cannot launch.
  depends_on macos: ">= :sonoma"

  app "DiagClean.app"

  # DiagClean refuses to remove a running application, and the same courtesy applies to
  # removing itself.
  uninstall quit: "com.diagclean.mac"

  # Exactly the leftover set DiagClean's own Uninstall would find for this bundle
  # identifier. A cleanup tool that leaves its own litter behind would be a poor advert
  # for itself.
  zap trash: [
    "~/Library/Application Support/DiagClean",
    "~/Library/Caches/com.diagclean.mac",
    "~/Library/Preferences/com.diagclean.mac.plist",
    "~/Library/Saved Application State/com.diagclean.mac.savedState",
  ]
end
