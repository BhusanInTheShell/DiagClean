# Packaging

## `homebrew/diagclean.rb`

The formula for the `BhusanInTheShell/homebrew-diagclean` tap. References the v0.1.0
macOS release tarballs and their real sha256 hashes. Update `version`, both `url`s, and
both `sha256`s together whenever a new version is tagged.

## `winget/`

A complete three-file manifest set (version, installer, default locale) for
`BhusanInTheShell.DiagClean`, targeting the `microsoft/winget-pkgs` schema 1.6.0. This
is **prepared but not submitted** - publishing it means opening a PR against Microsoft's
own repository, which is a public, third-party action that needs an explicit decision
each time, not something to automate. To submit: fork `microsoft/winget-pkgs`, copy
these three files into
`manifests/b/BhusanInTheShell/DiagClean/0.1.0/`, and open a PR (or use the
`wingetcreate`/`winget validate` CLI tools to validate first).
