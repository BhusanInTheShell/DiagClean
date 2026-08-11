# Windows Smoke Test

Everything in this repo was written and unit-tested on macOS, so the Windows-only APIs
(WMI, Event Log, registry, performance counters) have documented-correct usage but have
never actually run against a real Windows machine. Run through this checklist on a real
Windows 10/11 box before relying on DiagClean for live helpdesk work.

## Setup

```powershell
dotnet publish src/DiagClean.Cli/DiagClean.Cli.csproj -c Release -r win-x64
cd src/DiagClean.Cli/bin/Release/net8.0/win-x64/publish
.\DiagClean.exe
```

Try it once as a standard user and once elevated (Run as Administrator) - several
things behave differently between the two.

## Diagnostic collector

Run `.\DiagClean.exe diag` (or the menu option) and open the resulting HTML report.

- [ ] **Hardware section** - CPU name/cores, RAM total, motherboard, BIOS version, GPU
      name(s) all populated and plausible (not all showing "0" or blank).
- [ ] **Disk Health** - every physical disk shows up with a plausible size. Free space
      per disk roughly matches what Explorer shows for its partitions. SMART status
      shows Healthy/Warning/Failing on drives that expose predictive data, or Unknown
      on ones that don't (NVMe/RAID-controlled drives commonly won't expose it - that's
      expected, not a bug).
- [ ] **Event Log** - entries appear, sorted newest-first, with readable messages (not
      all "(description unavailable...)" — a few of those are normal for third-party
      drivers, but if *every* entry shows that, something's wrong with `FormatDescription`).
- [ ] **Installed Software** - matches roughly what's in "Apps & Features". Try this on
      a 64-bit machine with both 32-bit and 64-bit apps installed to confirm the
      `WOW6432Node` registry path is actually being read.
- [ ] **Network** - adapter names, IPs, DNS servers, gateway all correct. Test on a
      machine with both a Wi-Fi and Ethernet adapter (only one usually "Up").
- [ ] **Performance** - CPU load is a believable number (not always 0 or always 100).
      Open Task Manager alongside and sanity-check memory-used % and uptime.
- [ ] Run once as **standard user** - confirm the report still generates (possibly with
      fewer Disk Health / Event Log details) rather than crashing.
- [ ] Trigger a genuine collector failure if you can (e.g. run on a machine with
      Performance Counters disabled via GPO) and confirm the report still generates
      with a "Collection Notices" section instead of the whole tool crashing.

## Clean module

**Use a disposable/test VM for this section if at all possible.**

- [ ] `DiagClean.exe clean --preset quick --dry-run` - confirm it lists real files under
      `%TEMP%` and browser cache folders with believable sizes, and that **nothing is
      deleted** (check file timestamps/existence after).
- [ ] Run the interactive Quick Clean, let it reach the confirmation prompt, and type
      something other than `DELETE` (e.g. press Enter) - confirm it cancels cleanly and
      nothing is deleted.
- [ ] Run it again and actually type `DELETE` - confirm files are actually removed and
      the summary's freed-space number is in the right ballpark.
- [ ] Open a file in a browser cache folder (or otherwise lock a file in `%TEMP%`) before
      running Clean - confirm the tool reports it as a failure in the summary rather
      than crashing the whole run.
- [ ] Confirm `%LOCALAPPDATA%\DiagClean\logs\clean-<date>.log` was written with the
      details of what was deleted.
- [ ] Try Deep Clean (needs admin) and confirm the Windows Update /
      Delivery Optimization paths are found - this one is expected to report some
      "locked file" failures if the Windows Update service is running, which is normal.
- [ ] Confirm your Desktop, Documents, Pictures files are untouched after every run
      above - this is the one that must never fail.

## If something's off

The most likely failure points, in order of likelihood:

1. `DiskHealthCollector`'s `MSStorageDriver_FailurePredictStatus` → `Win32_DiskDrive`
   matching (`src/DiagClean.Core/Diagnostics/DiskHealthCollector.cs`) - the two classes
   don't share a clean key, so the substring match is a best-effort heuristic. If SMART
   status looks wrong, this is where to look first.
2. `EventLogCollector.SafeFormatDescription` - if a lot of messages come back empty,
   check whether the underlying provider's message DLL is actually missing or whether
   the XPath query itself needs adjusting.
3. Free-space-per-physical-disk in `DiskHealthCollector.SumFreeSpaceForDrive` - dynamic
   disks or Storage Spaces volumes may not associate cleanly through
   `Win32_DiskPartition`/`Win32_LogicalDisk`.
