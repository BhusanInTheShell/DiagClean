import Foundation

/// The complete, fixed set of maintenance actions.
///
/// Deliberately short and deliberately boring: real helpdesk fixes for problems people
/// actually report — DNS not resolving after a network change, the wrong app opening a
/// file, a wedged Finder, garbled text, Spotlight not finding files that exist. No
/// registry-cleaner theatre, no "speed boosters", nothing whose mechanism cannot be
/// explained in one sentence to the person whose machine it is.
///
/// Every command was checked on a real Mac for what it actually returns as an ordinary
/// user, which is how the administrator flags below were set rather than guessed.
public enum OptimizationCatalog {

    private static let lsregister =
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    public static let all: [OptimizationAction] = [
        OptimizationAction(
            id: "font-cache",
            title: "Clear Font Cache",
            fixes: "Garbled, missing or wrongly-substituted text in apps.",
            sideEffect: "Text may render oddly until you log out and back in. The cache rebuilds itself.",
            commands: [MaintenanceCommand("/usr/bin/atsutil", ["databases", "-removeUser"])],
            requiresAdministrator: false,
            impact: .quiet
        ),

        OptimizationAction(
            id: "launchservices-user",
            title: "Rebuild File Associations",
            fixes: "The wrong app opening a file, or duplicate entries in the Open With menu.",
            sideEffect: "The Open With menu is rebuilt as apps re-register; it can look empty for a moment.",
            // The user domain only. The local and system domains need root, and rebuilding
            // just this one still fixes the overwhelming majority of Open With problems.
            commands: [MaintenanceCommand(lsregister, ["-kill", "-r", "-domain", "user"])],
            requiresAdministrator: false,
            impact: .quiet
        ),

        OptimizationAction(
            id: "restart-finder-dock",
            title: "Restart Finder and Dock",
            fixes: "An unresponsive Finder or Dock, and visual glitches that survive a relaunch.",
            // The line the CLI is missing. "Restarts Finder" sounds harmless right up
            // until it closes the twelve windows somebody was working in.
            sideEffect: "Closes every open Finder window and briefly hides the Dock. Any file copy in progress in Finder is interrupted.",
            commands: [
                MaintenanceCommand("/usr/bin/killall", ["Finder"]),
                MaintenanceCommand("/usr/bin/killall", ["Dock"]),
            ],
            requiresAdministrator: false,
            impact: .visible
        ),

        OptimizationAction(
            id: "flush-dns",
            title: "Flush DNS Cache",
            fixes: "“Can't reach this site” after a DNS or network change.",
            sideEffect: "Name lookups are briefly slower while the cache refills.",
            // dscacheutil alone returns success as an ordinary user but achieves close to
            // nothing: on modern macOS the DNS cache lives in mDNSResponder, and
            // signalling it needs root.
            commands: [
                MaintenanceCommand("/usr/bin/dscacheutil", ["-flushcache"]),
                MaintenanceCommand("/usr/bin/killall", ["-HUP", "mDNSResponder"]),
            ],
            requiresAdministrator: true,
            impact: .quiet
        ),

        OptimizationAction(
            id: "rebuild-spotlight",
            title: "Rebuild Spotlight Index",
            fixes: "Spotlight failing to find files that are definitely there.",
            sideEffect: "Search stays incomplete for hours while it reindexes, and the machine runs hot and slow throughout. It keeps going long after DiagClean is closed.",
            commands: [MaintenanceCommand("/usr/bin/mdutil", ["-E", "/"])],
            requiresAdministrator: true,
            impact: .prolonged
        ),
    ]

    /// What this process can actually carry out right now.
    public static func available(isRoot: Bool = Privileges.isRoot) -> [OptimizationAction] {
        all.filter { isRoot || !$0.requiresAdministrator }
    }

    public static func unavailable(isRoot: Bool = Privileges.isRoot) -> [OptimizationAction] {
        all.filter { !isRoot && $0.requiresAdministrator }
    }
}
