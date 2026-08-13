# DiagClean

A single, focused utility for helpdesk / IT support technicians on Windows and macOS.
Two modes:

1. **Diagnostic Collector** — one pass to gather hardware, disk health/SMART, recent
   system log errors, installed software, network config, and a performance snapshot,
   written out as a clean, self-contained HTML report (and/or PDF) you can email or
   attach to a ticket.
2. **Quick Clean + Optimise** — safety-first cleanup of temp files, browser caches, and
   OS-specific bloat (Windows Update leftovers/installer leftovers on Windows, general
   app caches on macOS). Always previews in dry-run first, always requires explicit
   confirmation before deleting anything, and logs every clean run for an audit trail.

## Platform support

| | Windows | macOS |
|---|---|---|
| Diagnostic collectors | WMI, Event Log, Registry | `system_profiler`, `diskutil`, `sysctl`, unified log (`log show`) |
| Clean targets | Temp, Browser Cache, Windows Update, Installer Leftovers | Temp, Browser Cache, System Caches (`~/Library/Caches`) |
| Distribution | Portable `.exe` (zip), winget manifest prepared | Homebrew tap, portable tarball |

Linux isn't supported yet — the architecture (interface-based collectors/targets
selected by a factory) is there to add it the same way macOS was added.

## Tech stack

- **.NET 8 / C#** — on Windows, WMI (`System.Management`), Event Log
  (`System.Diagnostics.Eventing.Reader`), and the registry are first-class APIs; on
  macOS, there's no WMI equivalent, so the Mac collectors shell out to the same tools a
  native macOS diagnostic script would (`system_profiler`, `diskutil`, `sysctl`,
  `log show`, `vm_stat`) rather than hand-rolling Mach/IOKit interop.
- **Spectre.Console** — the interactive terminal UI (tables, progress bars, prompts),
  identical on both platforms.
- **QuestPDF** — PDF export, pure .NET with no external process dependency (no headless
  browser or wkhtmltopdf binary to ship), which keeps the single-binary story intact on
  both platforms. Runs under the free Community license (see
  [questpdf.com/license](https://www.questpdf.com/license/) — revisit if this is ever
  deployed beyond a small team/company).
- Publishes as a single self-contained binary per platform — no .NET runtime install
  needed on the target machine.

## Project layout

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
what make this possible without duplicating the CLI or report layer per OS -
`Composition.cs` and `CleanTargetFactory` are the only places that branch on
`OperatingSystem.IsWindows()` / `IsMacOS()`.

## Building

Requires the .NET 8 SDK.

```bash
dotnet build DiagClean.sln
```

## Running tests

```bash
dotnet test src/DiagClean.Tests/DiagClean.Tests.csproj
```

On macOS, this also runs live integration tests against the real machine (real
hardware/disk/performance/software/log data, and a real filesystem scan of the actual
Temp/Caches directories) - genuine regression coverage the Windows side doesn't have,
since this project has no Windows machine available to test on (see
[SMOKE_TEST.md](SMOKE_TEST.md)).

## Running

Interactive menu (no arguments):

```bash
dotnet run --project src/DiagClean.Cli
```

Scripted / RMM use:

```bash
# Diagnostic report to a specific path (HTML by default)
dotnet run --project src/DiagClean.Cli -- diag --output ~/reports/machine1.html

# PDF instead - or --format both for HTML and PDF side by side
dotnet run --project src/DiagClean.Cli -- diag --format pdf --output ~/reports/machine1.pdf

# Preview only, no deletion
dotnet run --project src/DiagClean.Cli -- clean --preset quick --dry-run

# Unattended deep clean (skips the interactive confirmation prompt)
dotnet run --project src/DiagClean.Cli -- clean --preset deep --yes
```

## Installing

### macOS (Homebrew)

```bash
brew tap BhusanInTheShell/diagclean
brew install diagclean
```

### Windows

A winget manifest is prepared under `packaging/winget/` but not yet submitted to the
`microsoft/winget-pkgs` repository. Until then, download the published `.exe` from the
[GitHub Releases](https://github.com/BhusanInTheShell/DiagClean/releases) page.

## Publishing a portable executable manually

```bash
# Windows
dotnet publish src/DiagClean.Cli/DiagClean.Cli.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true

# macOS (Apple Silicon)
dotnet publish src/DiagClean.Cli/DiagClean.Cli.csproj -c Release -r osx-arm64 --self-contained true -p:PublishSingleFile=true

# macOS (Intel)
dotnet publish src/DiagClean.Cli/DiagClean.Cli.csproj -c Release -r osx-x64 --self-contained true -p:PublishSingleFile=true
```

The output under `src/DiagClean.Cli/bin/Release/net8.0/<rid>/publish/` is a single
binary — copy it (along with `appsettings.json` and the `LatoFont/` folder next to it,
both required at runtime) anywhere and run it, no install required. Some diagnostics
(SMART, some log sources) and Deep Clean need Administrator/root to see/do everything;
the tool detects and reports elevation state at startup either way.

## Safety model (Clean module)

- **Dry-run first, always.** There is no code path that deletes without either an
  explicit `--yes` flag (scripted use) or a typed `DELETE` confirmation (interactive
  use). `--dry-run` never deletes, full stop.
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
