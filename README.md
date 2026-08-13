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

- **Two tools, one binary**: a full diagnostic report and a safety-first cleanup utility, in the same interactive menu
- **One-pass diagnostics**: hardware, disk health/SMART, recent system log errors, installed software, network config, and a performance snapshot — out as a self-contained **HTML and/or PDF** report you can attach to a ticket
- **Safety-first cleanup**: temp files, browser caches, and OS-specific bloat, always previewed in **dry-run** before anything is deleted
- **Cross-platform by design**: Windows (WMI/Event Log/Registry) and macOS (`system_profiler`/`diskutil`/`log show`) share one CLI and report format
- **Audit trail**: every clean run is logged — what was scanned, what was deleted, what failed and why

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
diagclean                                       # Interactive menu
diagclean diag                                  # Diagnostic report (HTML by default)
diagclean diag --format pdf                     # ...or PDF, or --format both
diagclean clean --preset quick --dry-run        # Preview only, nothing deleted
diagclean clean --preset deep --yes             # Unattended, skips confirmation

diagclean diag --output ~/reports/machine1.html # Diagnostic report to a specific path
diagclean --help                                # Show all commands
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
$ diagclean diag --format both

Collecting hardware, disk, network, event log, and software data...
Report written to /Users/you/Library/Application Support/DiagClean/reports/DiagClean-Report-your-mac-20260813-170600.html
Report written to /Users/you/Library/Application Support/DiagClean/reports/DiagClean-Report-your-mac-20260813-170600.pdf
```

One self-contained report — hardware, disk health/SMART, recent log errors, installed
software, network config, and a performance snapshot — ready to email or attach to a
ticket. No dependencies to view it: open the HTML in any browser, or send the PDF.

### Quick Clean (dry-run preview)

```
$ diagclean clean --preset deep --dry-run

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

## Platform support

| | Windows | macOS |
|---|---|---|
| Diagnostic collectors | WMI, Event Log, Registry | `system_profiler`, `diskutil`, `sysctl`, unified log (`log show`) |
| Clean targets | Temp, Browser Cache, Windows Update, Installer Leftovers | Temp, Browser Cache, System Caches (`~/Library/Caches`) |
| Distribution | Portable `.exe` (zip), winget PR pending review | Homebrew tap, portable tarball |

Linux isn't supported yet — the architecture (interface-based collectors/targets
selected by a factory) is there to add it the same way macOS was added.

## Safety model (Clean module)

- **Dry-run first, always.** There is no code path that deletes without either an
  explicit `--yes` flag (scripted use) or a typed `DELETE` confirmation (interactive
  use).
- **Two independent checks before any delete**: every path must (1) fall under a
  narrow, hardcoded "allowed roots" list specific to that clean category, and (2) not
  match a protected path — built-in (Desktop, Documents, Pictures, Videos, Music) plus
  anything you add in `appsettings.json`. Both checks run again immediately before
  deletion, not just at scan time, in case the scan is stale by the time it's confirmed.
- **`C:\Windows\Installer` is deliberately never touched** — it's the live MSI cache
  Windows uses for repair/uninstall of installed software. Identifying orphaned entries
  safely requires cross-referencing the MSI product database; getting it wrong breaks
  uninstall/repair for real software, which is worse than leaving a few MB behind.
- **Every clean run is logged** to the platform's app-data directory
  (`%LOCALAPPDATA%\DiagClean\logs\` on Windows, `~/Library/Application Support/DiagClean/logs/`
  on macOS) — what was scanned, what was deleted, what failed and why.

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
                        place that deletes anything)
    Reporting/         Self-contained HTML and PDF report renderers
    Shell/             Process-execution helper the Mac collectors shell out through
    Models/            DTOs shared across the above
  DiagClean.Cli/       Spectre.Console entry point (interactive menu + `diag`/`clean` CLI commands)
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
