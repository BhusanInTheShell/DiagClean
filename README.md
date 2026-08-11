# DiagClean

A single, focused utility for Windows helpdesk / IT support technicians. Two modes:

1. **Diagnostic Collector** — one pass to gather hardware, disk health/SMART, recent
   Event Log errors, installed software, network config, and a performance snapshot,
   written out as a clean, self-contained HTML report you can email or attach to a
   ticket.
2. **Quick Clean + Optimise** — safety-first cleanup of temp files, browser caches,
   Windows Update leftovers, and orphaned installer files. Always previews in dry-run
   first, always requires explicit confirmation before deleting anything, and logs
   every clean run for an audit trail.

## Tech stack

- **.NET 8 / C#** — WMI (`System.Management`), Event Log (`System.Diagnostics.Eventing.Reader`),
  and the registry are first-class, strongly-typed APIs here, avoiding brittle
  shell-out-and-parse approaches.
- **Spectre.Console** — the interactive terminal UI (tables, progress bars, prompts).
- Publishes as a single self-contained `.exe` — no .NET runtime install needed on the
  target machine.

## Project layout

```
src/
  DiagClean.Core/     Business logic only, no UI dependency, unit-testable.
    Diagnostics/       Collectors (hardware, disks, event log, software, network, perf)
    Cleaning/          Clean targets (temp, browser cache, Windows Update, installers)
    Safety/            PathGuard (whitelist enforcement) + DryRunEngine (the only
                        place that deletes anything)
    Reporting/         Self-contained HTML report renderer
    Models/            DTOs shared across the above
  DiagClean.Cli/       Spectre.Console entry point (interactive menu + `diag`/`clean` CLI commands)
  DiagClean.Tests/     xUnit tests for Core, using a fake filesystem (no real disk access)
```

## Building

Requires the .NET 8 SDK.

```bash
dotnet build DiagClean.sln
```

## Running tests

```bash
dotnet test src/DiagClean.Tests/DiagClean.Tests.csproj
```

## Running

DiagClean is Windows-only at runtime (WMI, Event Log, and registry access are all
Windows APIs) — it builds and tests fine cross-platform, but `diag`/`clean` will print
an error and exit on non-Windows.

Interactive menu (no arguments):

```bash
dotnet run --project src/DiagClean.Cli
```

Scripted / RMM use:

```bash
# Diagnostic report to a specific path
dotnet run --project src/DiagClean.Cli -- diag --output C:\reports\machine1.html

# Preview only, no deletion
dotnet run --project src/DiagClean.Cli -- clean --preset quick --dry-run

# Unattended deep clean (skips the interactive confirmation prompt)
dotnet run --project src/DiagClean.Cli -- clean --preset deep --yes
```

## Publishing a portable executable

```bash
dotnet publish src/DiagClean.Cli/DiagClean.Cli.csproj -c Release -r win-x64
```

The output in `src/DiagClean.Cli/bin/Release/net8.0/win-x64/publish/` is a single
`DiagClean.exe` — copy it anywhere (USB stick, network share) and run it, no install
required. Some diagnostics (SMART, some Event Log sources) and Deep Clean need
Administrator to see/do everything; the tool detects and reports elevation state at
startup either way.

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
- **Every clean run is logged** to `%LOCALAPPDATA%\DiagClean\logs\clean-<date>.log` —
  what was scanned, what was deleted, what failed and why.

## Configuration

`src/DiagClean.Cli/appsettings.json` (next to the published exe):

```json
{
  "protectedPaths": [],
  "presets": {
    "quick": ["TempFiles", "BrowserCache"],
    "deep": ["TempFiles", "BrowserCache", "WindowsUpdate", "InstallerLeftovers"]
  }
}
```

Add paths to `protectedPaths` to extend the built-in whitelist (e.g. a shared drive
mapped into a cache-like location that should never be touched).

## Known limitation

This was developed and unit-tested on macOS, so the Windows-only APIs (WMI SMART
predictions, Event Log message formatting, registry-based software inventory) are
implemented against the documented behavior but have not been exercised against a real
Windows machine yet. Everything platform-agnostic (PathGuard, DryRunEngine, the HTML
report, the clean-target scanning logic, the CLI shell) is covered by the test suite
and verified. Before relying on this for live helpdesk work, run a full smoke test on
a real Windows box — particularly the SMART status matching in `DiskHealthCollector`
and the Event Log queries in `EventLogCollector`/`PerformanceCollector`.
