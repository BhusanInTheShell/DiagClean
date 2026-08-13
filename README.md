<div align="center">
  <h1>DiagClean</h1>
  <p><em>Diagnostic collector + safe cleanup for helpdesk technicians.</em></p>
</div>

<p align="center">
  <a href="https://github.com/BhusanInTheShell/DiagClean/releases"><img src="https://img.shields.io/github/v/tag/BhusanInTheShell/DiagClean?label=version&style=flat-square" alt="Version"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square" alt="License"></a>
  <a href="https://github.com/BhusanInTheShell/DiagClean/commits"><img src="https://img.shields.io/github/commit-activity/m/BhusanInTheShell/DiagClean?style=flat-square" alt="Commits"></a>
  <img src="https://img.shields.io/badge/platform-Windows%20%7C%20macOS-lightgrey?style=flat-square" alt="Platform">
</p>

## Features

- **Five tools, one binary**: a full diagnostic report, a safety-first cleanup utility, an app uninstaller with leftover-file cleanup, a system optimizer, and a disk usage browser, in the same interactive menu
- **One-pass diagnostics**: hardware, disk health/SMART, recent system log errors, installed software, network config, and a performance snapshot — out as a self-contained **HTML and/or PDF** report you can attach to a ticket
- **Safety-first cleanup**: temp files, browser caches, and OS-specific bloat, always previewed in **dry-run** before anything is deleted
- **Uninstall with leftovers**: removes an app plus its caches, preferences, logs, and containers - moved to Trash/Recycle Bin (recoverable), not permanently deleted
- **Optimize**: refreshes DNS/icon/font caches and stuck services (print spooler, Finder/Explorer) - a conservative set of well-known helpdesk fixes, not deep system tweaks
- **Analyze**: navigate any folder, see what's actually eating the space with a proportional bar per entry, drill down, open/reveal, or delete one item at a time
- **Cross-platform by design**: Windows (WMI/Event Log/Registry) and macOS (`system_profiler`/`diskutil`/`log show`) share one CLI and report format
- **Audit trail**: every clean/uninstall/optimize run is logged — what was scanned, what was touched, what failed and why

## Quick Start

**Install via Homebrew (macOS) — recommended:**

```bash
brew install BhusanInTheShell/diagclean/diagclean
```

One command — this taps and installs together (no separate `brew tap` step needed). A
plain `brew install diagclean` (no tap prefix) only works for formulae accepted into
Homebrew's official `homebrew-core` repository, which requires an established usage
track record; not realistic for a brand-new project yet.

> If you see `Refusing to load formula ... from untrusted tap` on an older Homebrew
> version, run `brew trust bhusanintheshell/diagclean` first, then reinstall.

**Windows:** download the `.exe` from [Releases](https://github.com/BhusanInTheShell/DiagClean/releases) —
a [winget submission](https://github.com/microsoft/winget-pkgs/pull/416776) is pending review.

**Run:**

```bash
dclean                                       # Interactive menu
dclean diag                                  # Diagnostic report (HTML by default)
dclean diag --format pdf                     # ...or PDF, or --format both
dclean clean --preset quick --dry-run        # Preview only, nothing deleted
dclean clean --preset deep --yes             # Unattended, skips confirmation
dclean uninstall --dry-run                   # Pick apps, preview what would be removed
dclean optimize --dry-run                    # Pick optimizations, preview what would run
dclean analyze                               # Browse disk usage from your home directory
dclean analyze --path ~/Downloads            # ...or start somewhere specific

dclean diag --output ~/reports/machine1.html # Diagnostic report to a specific path
dclean --help                                # Show all commands
```

## Tips

- **Safety**: Clean always previews in dry-run first. Nothing is deleted without either
  `--yes` (scripted use) or typing `DELETE` at the interactive confirmation prompt.
- **Presets**: `quick` cleans temp files + browser caches only. `deep` adds OS-specific
  bloat (Windows Update leftovers on Windows, general app caches on macOS).
- **Elevation**: some diagnostics (SMART, some log sources) and Deep Clean need
  Administrator/root to see and do everything — DiagClean reports elevation state at
  startup either way.
- **Configuration**: edit `appsettings.json` next to the binary to add protected paths
  or customize presets — see [Configuration](#configuration) below.

## Features in Detail

### Diagnostic Collector

```
$ dclean diag --format both

Collecting hardware, disk, network, event log, and software data...
Report written to /Users/you/Library/Application Support/DiagClean/reports/DiagClean-Report-your-mac-20260813-170600.html
Report written to /Users/you/Library/Application Support/DiagClean/reports/DiagClean-Report-your-mac-20260813-170600.pdf
```

One self-contained report — hardware, disk health/SMART, recent log errors, installed
software, network config, and a performance snapshot — ready to email or attach to a
ticket. No dependencies to view it: open the HTML in any browser, or send the PDF.

### Quick Clean (dry-run preview)

```
$ dclean clean --preset deep --dry-run

     Dry-run preview - nothing has been deleted yet
╭──────────────┬───────┬──────────┬─────────────────────╮
│ Category     │ Items │     Size │ Skipped (protected) │
├──────────────┼───────┼──────────┼─────────────────────┤
│ TempFiles    │   304 │ 622.4 KB │                   0 │
│ BrowserCache │     4 │   1.1 MB │                   0 │
│ SystemCaches │    26 │ 166.5 MB │                   0 │
╰──────────────┴───────┴──────────┴─────────────────────╯

334 items, 168.1 MB would be freed.

Dry-run only - nothing was deleted.
```

Dry-run is the only path in the code that can lead to a delete — there's no flag that
skips the preview. Confirm with `DELETE` (interactive) or `--yes` (scripted) to actually
free the space.

### Uninstall (remove apps + leftovers)

```
$ dclean uninstall

Select apps to remove
▶ ☐ Xcode (4111 MB) | Old
  ☐ Android Studio (3051 MB) | Recent
  ☐ Accelerate (14 MB) | Old

     Preview - nothing has been removed yet
╭───────────┬────────────────┬───────────────┬──────────╮
│ App       │ Leftover Items │ Leftover Size │ App Size │
├───────────┼────────────────┼───────────────┼──────────┤
│ Accelerate│              4 │        3.0 MB │    14 MB │
╰───────────┴────────────────┴───────────────┴──────────╯

1 app(s) plus 4 leftover items, 17 MB would be freed (moved to Trash, not permanently deleted).
```

On macOS, the app bundle and every matched leftover (Containers, Group Containers,
Caches, Preferences, Saved Application State, Logs, LaunchAgents) move to `~/.Trash` -
recoverable, unlike Clean's permanent deletion of regenerable cache/temp junk, since
removing the wrong app is a much higher-stakes mistake. Apps unused for 30+ days are
pre-checked in the picker as a nudge toward removing things you've actually stopped
using; recently-used apps start unchecked.

On Windows, there's no equivalent of "move the bundle to Trash" that leaves the system
consistent - removing a Program Files folder without running the vendor's own
uninstaller leaves orphaned registry entries, services, and shortcuts. So each selected
app's own registered uninstaller launches first (interactively, one at a time); leftover
`%APPDATA%`/`%LOCALAPPDATA%`/`%PROGRAMDATA%` residue is then scanned and cleaned as a
separate step afterward.

### Optimize (refresh caches + services)

```
$ dclean optimize

Select optimizations to run
☐ Flush DNS Cache (needs admin) - Clears the local DNS resolver cache...
☐ Rebuild LaunchServices Database (needs admin) - Re-registers every installed app's...
☐ Restart Finder and Dock - Restarts Finder and Dock - both relaunch automatically...
☐ Clear Font Cache - Clears the current user's font cache...
☐ Rebuild Spotlight Index (needs admin, slow) - Forces a full reindex of the boot volume...

Done. 2 succeeded, 0 failed.
  ✓ Restart Finder and Dock: Finder and Dock restarted.
  ✓ Clear Font Cache: Font cache cleared.
```

A deliberately conservative set of well-known, real helpdesk fixes (DNS issues, wrong
default app, Finder/Explorer glitches, missing Spotlight/search results, stuck print
jobs) - not deep system tweaks. Every action reports real success/failure based on the
underlying command's actual exit code, not just "did it run" - confirmed live: running
an admin-only action without elevation correctly reports failure rather than a false
"done". Actions flagged `slow` (a full search-index rebuild can take minutes to hours)
get a separate, explicit confirmation before running.

### Analyze (browse disk usage)

```
$ dclean analyze

Analyze Disk  /Users/you  |  Total: 78.3 GB
████████████████████  53.5%  📁 Library                                41.9 GB
████░░░░░░░░░░░░░░░░  12.4%  📁 .android                                9.7 GB
██░░░░░░░░░░░░░░░░░░   6.6%  📁 .gradle                                 5.1 GB
█░░░░░░░░░░░░░░░░░░░   3.1%  📁 zentrol                                 2.3 GB
.. (go up)
Quit Analyze
```

Select an entry to drill into a folder, or to open/reveal/delete it - one item at a
time, never a bulk selection, since Analyze can navigate (and delete) literally anywhere
on disk rather than a fixed set of known-safe locations like Clean/Uninstall. On macOS
it moves the deleted item to `~/.Trash` (same recoverable guarantee as Uninstall); on
Windows it deletes permanently, since moving to the Recycle Bin from .NET needs a
dependency this project has no way to verify without a real Windows machine - being
upfront that it's permanent there is safer than shipping something unverified.

Built on a selection menu rather than a live-updating raw-keyboard UI: real scans (even
with the fast macOS `du` path) can take several seconds on large real-world folders -
confirmed live scanning a 78GB home directory, 14 seconds - so instant per-keystroke
feedback would be misleading regardless of how it's built. A scanning spinner runs
between every navigation step instead.

## Platform support

| | Windows | macOS |
|---|---|---|
| Diagnostic collectors | WMI, Event Log, Registry | `system_profiler`, `diskutil`, `sysctl`, unified log (`log show`) |
| Clean targets | Temp, Browser Cache, Windows Update, Installer Leftovers | Temp, Browser Cache, System Caches (`~/Library/Caches`) |
| Uninstall | Vendor uninstaller + AppData leftover cleanup | Move app + Library leftovers to Trash |
| Optimize actions | DNS flush, icon cache, Explorer restart, print spooler reset | DNS flush, LaunchServices/Spotlight rebuild, Finder/Dock restart, font cache |
| Analyze | Managed recursive scan, permanent delete | Fast `du`-backed scan, delete moves to Trash |
| Distribution | Portable `.exe` (zip), winget PR pending review | Homebrew tap, portable tarball |

Linux isn't supported yet — the architecture (interface-based collectors/targets
selected by a factory) is there to add it the same way macOS was added.

## Safety model

- **Dry-run first, always.** There is no code path that deletes/removes anything
  without either an explicit `--yes` flag (scripted use) or a typed `DELETE`
  confirmation (interactive use).
- **Two independent checks before any delete**: every path must (1) fall under a
  narrow, hardcoded "allowed roots" list specific to that operation, and (2) not
  match a protected path — built-in (Desktop, Documents, Pictures, Videos, Music) plus
  anything you add in `appsettings.json`. Both checks run again immediately before
  deletion, not just at scan time, in case the scan is stale by the time it's confirmed.
- **`C:\Windows\Installer` is deliberately never touched** — it's the live MSI cache
  Windows uses for repair/uninstall of installed software. Identifying orphaned entries
  safely requires cross-referencing the MSI product database; getting it wrong breaks
  uninstall/repair for real software, which is worse than leaving a few MB behind.
- **Uninstall is recoverable, not permanent.** Removing an app is a much higher-stakes
  mistake than deleting regenerable cache/temp junk, so on macOS the app and its
  leftovers move to `~/.Trash` rather than being deleted outright. On Windows, the app
  itself is never touched directly at all - only its own registered uninstaller can
  remove it consistently (no orphaned registry entries/services/shortcuts).
- **Optimize's actions are a conservative, well-known set** (DNS flush, icon/font
  cache, service restarts) - no deep system tweaks, and every action reports real
  success/failure from the underlying command's actual exit code rather than assuming
  it worked. Actions that can take minutes to hours (a search-index rebuild) require a
  separate, explicit confirmation before running.
- **Analyze deletes one item at a time, never in bulk.** It's the one tool that can
  reach anywhere on disk rather than a fixed set of known-safe locations, so there's no
  "allowed roots" list to check against - the full path and size are always shown, and
  a typed `DELETE` confirmation is required before touching anything, same as everywhere
  else in the app.
- **Every clean/uninstall/optimize run is logged** to the platform's app-data directory
  (`%LOCALAPPDATA%\DiagClean\logs\` on Windows, `~/Library/Application Support/DiagClean/logs/`
  on macOS) — what was scanned, what was touched, what failed and why.

## Configuration

`appsettings.json` (next to the published binary):

```json
{
  "protectedPaths": [],
  "presets": {
    "quick": ["TempFiles", "BrowserCache"],
    "deep": ["TempFiles", "BrowserCache", "WindowsUpdate", "InstallerLeftovers", "SystemCaches"]
  }
}
```

`deep` lists every category that exists on either OS - each platform's Clean module
simply ignores categories that don't have a corresponding target (Windows has no
`SystemCaches` target, macOS has no `WindowsUpdate` target), so one config works for both.
Add paths to `protectedPaths` to extend the built-in whitelist (e.g. a shared drive
mapped into a cache-like location that should never be touched).

## Building from source

Requires the .NET 8 SDK.

```bash
dotnet build DiagClean.sln
dotnet test src/DiagClean.Tests/DiagClean.Tests.csproj
```

On macOS, testing also runs live integration tests against the real machine (real
hardware/disk/performance/software/log data, and a real filesystem scan of the actual
Temp/Caches directories) - genuine regression coverage the Windows side doesn't have,
since this project has no Windows machine available to test on.

```bash
# Publish a portable single-file binary
dotnet publish src/DiagClean.Cli/DiagClean.Cli.csproj -c Release -r osx-arm64 --self-contained true -p:PublishSingleFile=true
# swap the -r value for win-x64 or osx-x64
```

The output under `src/DiagClean.Cli/bin/Release/net8.0/<rid>/publish/` is a single
binary — copy it (along with `appsettings.json` and the `LatoFont/` folder next to it,
both required at runtime) anywhere and run it, no install required.

### Project layout

```
src/
  DiagClean.Core/     Business logic only, no UI dependency, unit-testable.
    Diagnostics/       Collector interfaces + Windows implementations
      Mac/             macOS collector implementations (same interfaces)
    Cleaning/          Clean targets (temp, browser cache, Windows Update,
                        installers, system caches), OS-branching factory
    Safety/            PathGuard (whitelist enforcement) + DryRunEngine (the only
                        place Clean deletes anything)
    Uninstall/         App lister + uninstaller interfaces, Mac (Trash-move) and
                        Windows (vendor uninstaller + leftover cleanup) implementations
    Optimize/          IOptimizationAction + delegate-based implementation, Mac and
                        Windows action lists (each action is a one-shot OS command)
    Analyze/           IDirectoryAnalyzer + deleter - managed recursive scan by default,
                        Mac fast path via `du -k -d 1`
    Reporting/         Self-contained HTML and PDF report renderers
    Shell/             Process-execution helper (with real exit-code reporting) the
                        Mac collectors and Optimize's actions shell out through
    Shared/            Filesystem scan helpers + the Mac Trash-move helper, shared by
                        Cleaning, Uninstall, and Analyze
    Models/            DTOs shared across the above
  DiagClean.Cli/       Spectre.Console entry point (interactive menu + `diag`/`clean`/
                        `uninstall`/`optimize`/`analyze` CLI commands)
  DiagClean.Tests/     xUnit tests - fake-filesystem unit tests plus live tests that
                        run the real macOS collectors/targets against this machine
```

The Diagnostics and Cleaning interfaces (`IHardwareCollector`, `ICleanTarget`, etc.) are
what make cross-platform support possible without duplicating the CLI or report layer -
`Composition.cs` and `CleanTargetFactory` are the only places that branch on
`OperatingSystem.IsWindows()` / `IsMacOS()`.

## Known limitation

The Windows-only APIs (WMI SMART predictions, Event Log message formatting,
registry-based software inventory) are implemented against documented behavior but have
never been exercised against a real Windows machine — this project has no Windows
machine available to test on. The macOS collectors, by contrast, run against this
machine's real hardware/disk/OS data on every test run and have been verified correct
by independently cross-checking their output against the underlying `diskutil`/
`system_profiler`/`sysctl` commands. Before relying on the Windows build for live
helpdesk work, run through [SMOKE_TEST.md](SMOKE_TEST.md) on a real Windows box —
particularly the SMART status matching in `DiskHealthCollector` and the Event Log
queries in `EventLogCollector`/`PerformanceCollector`.

## License

MIT License — see [LICENSE](LICENSE).
