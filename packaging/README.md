# Packaging

The installed CLI command is `dclean` (short alias, set via `<AssemblyName>` in
`DiagClean.Cli.csproj`) - the package/formula/PackageIdentifier names below
deliberately stay "diagclean"/"DiagClean" (the project's actual name); only the
executable itself is short.

## `homebrew/diagclean.rb`

The formula for the `BhusanInTheShell/homebrew-diagclean` tap. References the v0.2.0
macOS release tarballs and their real sha256 hashes. Update `version`, both `url`s, and
both `sha256`s together whenever a new version is tagged.

## `homebrew/diagclean-app.rb`

The **cask** for the native macOS app, in the same
`BhusanInTheShell/homebrew-diagclean` tap as the formula above. A cask and a formula
coexist happily and install genuinely different things — `brew install diagclean` puts
the `dclean` command on the PATH, `brew install --cask diagclean-app` puts DiagClean.app
in /Applications.

The app is versioned separately from the CLI (`mac-v0.1.0` tags rather than `v0.3.1`),
because the two ship on their own schedules and pinning them together would mean
retagging one every time the other changed.

Cutting a release:

1. `cd mac && VERSION=x.y.z SIGN_IDENTITY="Developer ID Application: … (TEAMID)" \
   NOTARY_PROFILE=diagclean ./Scripts/package-dmg.sh`
2. Copy the sha256 it prints as its last line into `sha256` in the cask.
3. Bump `version` in the cask to match.
4. Tag `mac-vx.y.z`, attach the DMG to the GitHub release.

The script skips signing and notarisation with an explicit warning when those variables
are unset, so a local build is obviously not a release build. **A DMG that skipped
notarisation is not distributable** — it looks identical to a real one right up until
Gatekeeper refuses it on somebody else's Mac.

Notarisation needs a *Developer ID Application* certificate. An *Apple Development*
certificate is not a substitute: it signs for local use and TestFlight, and notarytool
rejects it. Set the notary profile up once with:

```
xcrun notarytool store-credentials "diagclean" \
  --apple-id you@example.com --team-id TEAMID --password APP-SPECIFIC-PASSWORD
```

## `winget/`

A complete three-file manifest set (version, installer, default locale) for
`BhusanInTheShell.DiagClean`, targeting the `microsoft/winget-pkgs` schema 1.6.0.
Submitted as [microsoft/winget-pkgs#416776](https://github.com/microsoft/winget-pkgs/pull/416776),
pending Microsoft's validation pipeline and review. These files are the source of truth
for that PR - if the manifest needs a fix, edit here first, then copy into a fresh
`manifests/b/BhusanInTheShell/DiagClean/0.2.0/` on a branch of the
`microsoft/winget-pkgs` fork and push.

For a new version: bump `version` in all three files (and the folder name in the fork),
update the installer URL/sha256, and open a new PR the same way.
