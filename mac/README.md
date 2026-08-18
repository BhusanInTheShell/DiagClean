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
  Analyze/               directory walker, the denylist guard, and single-item removal
  Status/                native counters, the rate arithmetic, and health thresholds
  Diagnostics/           collectors, redaction, and the single HTML renderer
  Optimize/              the action catalogue and the runner that reports real exit codes
  Audit/                 the run log
Sources/DiagCleanApp/    SwiftUI, deliberately thin
Tests/DiagCleanKitTests/ real temp directories, real symlinks, no filesystem fakes
```

## Status

All six sections are built: **Status**, **Clean**, **Uninstall**, **Analyze**,
**Optimize** and **Diagnostics**.

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

### Diagnostics

Diagnostics has no destructive surface at all. Its risk is disclosure: a report is
attached to a ticket, forwarded, and sometimes reaches a third-party vendor, carrying the
computer name, the user's name, IP and MAC addresses, DNS servers and a complete
inventory of everything installed. So the screen is built around what leaves the machine.

- **Every section is individually includable**, and each says in plain words what it
  contains. Sections that identify the machine or its owner are badged as such.
- **Excluding a section means it is never collected**, not collected and then hidden. The
  difference matters when the reason for excluding it was that it should not exist in a
  file somebody might forward.
- **Redaction** replaces the computer name, user name, IP and MAC addresses and DNS
  servers with a visible marker, and the report says at the top that it was redacted — a
  reader who does not know will otherwise read the marker as a collection failure. macOS
  version and hardware are kept, since they identify the software, not the person.
- **The report is saved where the technician chooses and sent nowhere.** Nothing uploads;
  nothing writes to a default location behind their back.

Collectors run in isolation, as in the CLI: one hitting a permission wall is recorded
against its section rather than aborting the run, because a technician on somebody else's
machine needs the report they can get. A section that explains why it is missing beats one
that silently is not there.

There is one renderer. The PDF is produced from the same HTML rather than by a second
builder, so the two formats cannot drift apart the way the CLI's separate HTML and PDF
builders can. Everything user-supplied is HTML-escaped — an app named `<script>` is a real
thing somebody can install, and this document is built by string concatenation and then
opened in a browser.

**Known limitation:** the PDF is one continuous page rather than paginated sheets.
`NSPrintOperation` is the call that paginates, and on a detached `WKWebView` it hung the
main thread and wrote nothing; an earlier variant produced a 311 MB file with three
million objects. `createPDF` is fast and correct, and its single tall page attaches and
reads fine. The HTML is the primary format and any browser paginates it properly on print.

### Status

Status is read-only, so the risk is not destruction — it is quietly reporting the wrong
number. Two things follow from that.

**Everything comes from a direct system call**, not from parsing a command's output. The
CLI spawns `iostat`, `vm_stat`, `pmset`, `netstat` and `ps` for a single reading; a
dashboard refreshing every two seconds would be launching five processes a tick all day,
and a human-readable table is a format that can change underneath you. `host_statistics`,
`getloadavg`, `getifaddrs`, `IOPSCopyPowerSourcesInfo` and `proc_pidinfo` are what those
tools use themselves. Verified against the system's own numbers: our CPU figure reads
2.6% where `top` reports 2.59% busy.

**Free disk space is reported the way the user sees it.** `volumeAvailableCapacityForImportantUsage`
counts space macOS can reclaim on demand, and is what Finder and System Settings show. The
CLI reports the raw figure instead, which on the development machine reads 4 GB lower —
a tool that disagrees with Finder looks broken even when it is being precise. The
purgeable difference is named on the card rather than left as a mystery.

The rate arithmetic lives in `StatusCalculator`, pure and free of any system call, because
that is where a dashboard actually goes wrong: subtracting two counters when one has
wrapped, when no time has passed, or when a process did not exist a moment ago is how a
status view ends up claiming 4000% CPU or crediting a just-launched app with every
nanosecond it has ever used. All of it is testable without a machine in any state.

Where the machine will not answer, it says so instead of substituting a zero. macOS
refuses task info for another user's processes without elevation — about 40% of them on a
normal machine, all system daemons — so the busiest-processes list reports the count it
could not read. A list quietly missing a third of the machine will eventually mislead
somebody hunting a runaway daemon.

Health verdicts prefer the signal that means something: macOS's own memory pressure over
raw used-percentage, since a healthy Mac routinely sits above 80% because unused RAM is
wasted RAM. Disk is judged on absolute free space with proportion only able to escalate
that verdict — a 4 TB disk at 95% full has 200 GB free and is fine.

The menu bar item is opt-in and off by default. It takes a strip of screen the user did
not offer, so it is something they turn on. Sampling stops whenever nothing is displaying
it, so the app is never quietly polling behind a hidden window.

### Optimize

Optimize changes system state without deleting anything, so the honesty question moves
from "what will this destroy" to "what will the person sitting at this machine notice".
Every action carries a side-effect line the CLI does not have. "Restarts Finder" reads as
harmless right up until it closes the twelve windows somebody was working in, so the row
says exactly that, and says it on the row rather than burying it in the confirmation.

Only quiet, unprivileged actions are ticked by default; anything the user will notice is
a decision they make rather than one they inherit. The confirmation shows the exact
commands — a technician about to restart somebody's Finder is entitled to see
`killall Finder` before it happens rather than take it on trust.

Success is the command's real exit status, never the assumption that running it worked.
That is not academic: `killall -HUP mDNSResponder` as an ordinary user prints "No matching
processes belonging to you were found" and exits 1, so a tool that assumed success would
report a flushed DNS cache having flushed nothing. Every command in a multi-command action
must succeed — a DNS cache cleared but a resolver never signalled is a failure dressed as
a fix.

**DiagClean ships no privilege-escalation path**, deliberately. Prompting for an admin
password and running a shell as root is security-sensitive machinery, and shipping one
that has not been properly exercised is worse than shipping a smaller feature. Flush DNS
and Rebuild Spotlight need root, so they are listed, labelled and left unavailable, with
the CLI named as the way to run them — rather than offered as a checkbox certain to fail.
Which actions need root was established by running them on a real Mac and reading the exit
codes, not by guessing.

### Analyze

Analyze is the one feature that can reach anywhere on the disk rather than into a fixed
set of known-safe locations, so it inverts the usual shape: a denylist plus a sensitivity
tier, rather than a narrow allowlist.

The CLI's position is that there is no allowed-roots list Analyze could sensibly check
against, since browsing anywhere is the point, so its only protection is procedural — one
item at a time, full path shown, typed confirmation. That is right about *browsing* and
gives up too early on *removal*. Browsing is read-only and harmless; a disk browser has no
business trashing `/System` or a home folder no matter how carefully it asks first.

- **Refused outright**: volume roots, the home folder, `/System`, `/usr`, `/bin`,
  `/Library`, **`~/Library`**, `~/Applications`, the personal folders themselves,
  keychains and `.ssh`, DiagClean's own logs, and `.app` bundles — which point at
  Uninstall instead, so leftovers are handled properly rather than orphaned.
- **Allowed but flagged personal**: anything *inside* Documents, Desktop, Downloads,
  Pictures, Movies, Music, or iCloud Drive. Removable — finding a forgotten 40 GB export
  in Movies is a real reason to use this — but the confirmation says plainly that this is
  personal data rather than asking the same neutral question it asks about a cache.
- **Allowed**: everything else.

The container/contents split matters: `~/Library` at 46 GB is the largest thing in a
typical home folder and is exactly what a disk browser surfaces first. Removing it takes
every app's preferences, containers and keychains. Removing something *inside* it is
ordinary work.

Sizes are measured natively and concurrently, streaming in as each child finishes, so rows
appear while the scan is still running and Cancel actually stops it. The CLI shells out to
`du -k -d 1`, which is a single fast call that arrives all at once and cannot be
interrupted.

Removal is one item at a time — there is deliberately no multi-selection to get wrong —
and always to the Trash.

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

172 tests, weighted heavily toward the paths where a bug costs somebody their data. They
run against real temp directories with real symlinks rather than a filesystem fake —
case-insensitive volumes, symlinks and permission errors are precisely the things a
hand-written fake gets subtly wrong, agreeing with the code under test while both are
wrong together. The leftover matcher is pure string logic with no filesystem access, and
several of its cases are taken verbatim from a real machine where the CLI's approach
produces dangerous results.

## Distribution

`Scripts/make-app.sh` assembles a debug bundle and ad-hoc signs it — enough to run on the
machine that built it, and nothing more.

`Scripts/package-dmg.sh` builds the real thing: a universal release binary (arm64 and
x86_64 in one bundle, so one DMG installs everywhere), the hardened runtime, a Developer
ID signature, notarisation and a stapled ticket.

```bash
VERSION=0.1.0 \
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE=diagclean \
./Scripts/package-dmg.sh
```

With those variables unset it still produces a DMG, ad-hoc signed and un-notarised, and
says so loudly at both steps. That distinction matters more than it looks: an
un-notarised DMG is indistinguishable from a real one until Gatekeeper refuses it on
somebody else's Mac, so the script never lets the two look alike in its output.

Notarisation requires a **Developer ID Application** certificate. An *Apple Development*
certificate will not do — it signs for local use and TestFlight, and `notarytool` rejects
it.

The Homebrew cask lives at `packaging/homebrew/diagclean-app.rb`, alongside the CLI's
formula in the same tap. Release steps are in `packaging/README.md`.
