# Packaging

## `homebrew/diagclean.rb`

The formula for the `BhusanInTheShell/homebrew-diagclean` tap. References the v0.1.0
macOS release tarballs and their real sha256 hashes. Update `version`, both `url`s, and
both `sha256`s together whenever a new version is tagged.

## `winget/`

A complete three-file manifest set (version, installer, default locale) for
`BhusanInTheShell.DiagClean`, targeting the `microsoft/winget-pkgs` schema 1.6.0.
Submitted as [microsoft/winget-pkgs#416776](https://github.com/microsoft/winget-pkgs/pull/416776),
pending Microsoft's validation pipeline and review. These files are the source of truth
for that PR - if the manifest needs a fix, edit here first, then copy into a fresh
`manifests/b/BhusanInTheShell/DiagClean/0.1.0/` on a branch of the
`microsoft/winget-pkgs` fork and push.

For a new version: bump `version` in all three files (and the folder name in the fork),
update the installer URL/sha256, and open a new PR the same way.
