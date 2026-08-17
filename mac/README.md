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
  Audit/                 the run log
Sources/DiagCleanApp/    SwiftUI, deliberately thin
Tests/DiagCleanKitTests/ real temp directories, real symlinks, no filesystem fakes
```

## Status

**Clean** is built. Status, Uninstall, Analyze, Optimize and Diagnostics appear in the
sidebar with a description of what they'll do, and are available in the CLI today.

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

Clean deletes permanently and says so at the point of confirmation. It does not use the
Trash, because moving a cache to the Trash relocates the bytes instead of reclaiming
them and would free nothing at all. Uninstall, where the stakes are entirely different,
will use the Trash as the CLI does.

Every run is appended to `~/Library/Application Support/DiagClean/logs/` — the same
directory the CLI writes to, so a machine has one audit trail regardless of which tool
did the work. That directory is itself protected: a cleanup that erased the record of
previous cleanups would be exactly the wrong behaviour.

## Testing

53 tests, weighted heavily toward the paths where a bug costs somebody their data. They
run against real temp directories with real symlinks rather than a filesystem fake —
case-insensitive volumes, symlinks and permission errors are precisely the things a
hand-written fake gets subtly wrong, agreeing with the code under test while both are
wrong together.

## Distribution

`Scripts/make-app.sh` assembles the bundle and ad-hoc signs it, which is enough to run
locally. Notarised DMG and Homebrew cask hang off the same script: re-sign with a
Developer ID identity, submit with `notarytool`, staple.
