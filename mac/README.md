# DiagClean for Mac

A native macOS companion to the DiagClean CLI, built in Swift and SwiftUI. Not a
wrapper — the safety rules and platform knowledge are shared with the CLI in intent, but
reimplemented natively so the Mac experience is a real one.

Requires macOS 14+.

```bash
swift test              # the whole test suite, no UI needed
./Scripts/make-app.sh   # assemble .build/DiagClean.app
open .build/DiagClean.app
```

## Layout

```
Sources/DiagCleanKit/    all logic — no SwiftUI, no AppKit, fully testable
  Safety/                PathGuard, ProtectedPaths, path resolution
  Clean/                 targets, scanner, and the single executor that deletes
  Uninstall/             app lister, leftover matching, and the single executor that trashes
  Audit/                 the run log
Sources/DiagCleanApp/    SwiftUI, deliberately thin
Tests/DiagCleanKitTests/ real temp directories, real symlinks, no filesystem fakes
```

## Status

**Clean** and **Uninstall** are built. Status, Analyze, Optimize and Diagnostics appear
in the sidebar with a description of what they'll do, and are available in the CLI today.

## Safety model

Carried over from the CLI, with four macOS-specific corrections.

Every path must pass **two independent checks** before anything touches it: it must be a
strict descendant of one of the narrow, hardcoded allowed roots for that operation, and
it must not fall under a protected path. Both checks run again immediately before
removal, because a preview may be minutes stale by the time somebody confirms it.
`CleanExecutor` is the only type in the codebase that deletes.

What this port fixes relative to the CLI's `PathGuard`:

| | CLI | Mac app |
|---|---|---|
| Protected-path matching | `StringComparison.Ordinal` | case- and Unicode-normalisation-insensitive |
| Allowed root itself | permitted (`candidate == root` passes) | refused — strict descendants only |
| Symlinks | no policy | refused outright, never traversed or sized through |
| `~/Downloads` | not protected | protected |

The case-sensitivity one is not theoretical: the default macOS boot volume is
case-insensitive APFS, so `~/documents/tax` and `~/Documents/tax` are the same file and
an ordinal comparison recognises only one of them as protected.

Two further narrowings, both trading a little reclaimed space for predictability:

- **`/private/tmp` is not touched.** It is shared across every user and daemon and holds
  live sockets and lock files. The CLI includes it; here the per-user `$TMPDIR` is the
  only temp root.
- **Temp entries must be untouched for at least a day.** Anything written in the last few
  minutes almost certainly belongs to something running right now.

### Uninstall

Matching an app's leftover files is where this feature is dangerous, so it is anchored
rather than free-floating. **The CLI matches by bare substring** against the bundle
identifier and the display name, which on a real machine is not a small imprecision:
uninstalling an app called `Flow` offers up eight of Apple's own containers — Shortcuts,
WorkflowKit, the Intelligence runtime — because each contains the letters "flow".
`Numbers` reaches iWork's containers the same way.

Matching here is split into two tiers:

- **Confident** — named for the app's bundle identifier (`com.docker.docker`, or a child
  namespace of it), or a `<id>.plist` / `.savedState` / `.binarycookies` state file, or
  exactly the app's name in a directory where apps conventionally use plain names.
  Ticked by default.
- **Likely** — a name-derived guess: `Docker Desktop` for `Docker`, or a shared group
  container like `group.com.microsoft` that Word and Excel both use. Shown, labelled,
  and never ticked by default.

Anything under `com.apple.*` is refused outright, whatever the app is called.

The cost is honest: a leftover nested inside a vendor directory
(`Application Support/BraveSoftware/Brave-Browser`) is not found, because only the
immediate children of each Library root are examined. Missing a leftover is a much
better failure than trashing somebody's Shortcuts.

Three refusals the CLI does not have:

| | CLI | Mac app |
|---|---|---|
| Apple software | offered for removal | refused, and shown as "Part of macOS" |
| Running apps | no check | refused, re-checked again at removal time |
| Removing itself | possible | refused |

Safari, Keynote, Numbers, Pages, Xcode and iMovie all ship into `/Applications` on a
normal machine, so the first row is not hypothetical.

Uninstall moves everything to the Trash via `FileManager.trashItem`, which records each
item's original location so Finder's Put Back actually works. The CLI moves files into
`~/.Trash` by hand and loses that, which makes its "recoverable" more theoretical than
it sounds.

### Clean

Clean deletes permanently and says so at the point of confirmation. It does not use the
Trash, because moving a cache to the Trash relocates the bytes instead of reclaiming
them and would free nothing at all. Uninstall, where the stakes are entirely different,
uses the Trash.

Protected paths come in two tiers. The **core** list — personal directories, cloud
storage, credentials, mail — is off limits to everything. Clean adds `Containers`,
`Group Containers`, `Preferences` and `~/Library/Safari` on top, because it has no
business in app data; Uninstall deliberately does not apply those, since removing one
app's container is the entire point of uninstalling it.

Every run is appended to `~/Library/Application Support/DiagClean/logs/` — the same
directory the CLI writes to, so a machine has one audit trail regardless of which tool
did the work. That directory is itself protected: a cleanup that erased the record of
previous cleanups would be exactly the wrong behaviour.

## Testing

88 tests, weighted heavily toward the paths where a bug costs somebody their data. They
run against real temp directories with real symlinks rather than a filesystem fake —
case-insensitive volumes, symlinks and permission errors are precisely the things a
hand-written fake gets subtly wrong, agreeing with the code under test while both are
wrong together. The leftover matcher is pure string logic with no filesystem access, and
several of its cases are taken verbatim from a real machine where the CLI's approach
produces dangerous results.

## Distribution

`Scripts/make-app.sh` assembles the bundle and ad-hoc signs it, which is enough to run
locally. Notarised DMG and Homebrew cask hang off the same script: re-sign with a
Developer ID identity, submit with `notarytool`, staple.
