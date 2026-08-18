import Foundation

/// The built-in, non-overridable veto lists. Nothing in configuration can remove an
/// entry here; user configuration can only add more on top.
///
/// Split into two tiers because Clean and Uninstall have genuinely different remits.
/// Clean must never touch app *data* — preferences, containers, saved state — because
/// nothing it does is worth losing somebody's settings over. Uninstall exists precisely
/// to remove those things for one named app. A single shared list would either break
/// Uninstall or quietly widen what Clean can reach, and the second failure is the one
/// nobody would notice.
public enum ProtectedPaths {

    /// Off limits to everything, no exceptions, in every feature. Irreplaceable data,
    /// credentials, and the record of what this tool has already done.
    public static func core(for user: UserPaths) -> [String] {
        [
            // Irreplaceable personal data.
            user.inHome("Desktop"),
            user.inHome("Documents"),
            // Not in the CLI's list, and it should be: a technician running a cleanup
            // on someone else's machine should never be the reason an unsaved download
            // disappears.
            user.inHome("Downloads"),
            user.inHome("Pictures"),
            user.inHome("Movies"),
            user.inHome("Music"),
            user.inHome("Public"),
            "/Users/Shared",

            // Cloud storage. Deleting a synced file deletes it everywhere, on every
            // device, which makes this considerably worse than a normal local mistake.
            user.inHome("Library", "Mobile Documents"),
            user.inHome("Library", "CloudStorage"),

            // Credentials and keys. Never regenerable, and losing them locks someone
            // out of things rather than merely costing them a re-download.
            user.inHome("Library", "Keychains"),
            user.inHome(".ssh"),
            user.inHome(".gnupg"),

            // Mail and message stores are documents in everything but name.
            user.inHome("Library", "Mail"),
            user.inHome("Library", "Messages"),

            // DiagClean's own audit trail. A run that erases the record of previous
            // runs is exactly the wrong behaviour for a tool meant to be defensible.
            user.appSupportDirectory,
        ]
    }

    /// Everything in `core`, plus the app-data directories Clean has no business in.
    /// Uninstall deliberately does not apply these: removing one app's container is the
    /// entire point of uninstalling it.
    public static func forClean(for user: UserPaths) -> [String] {
        core(for: user) + [
            user.inHome("Library", "Containers"),
            user.inHome("Library", "Group Containers"),
            user.inHome("Library", "Preferences"),
            // ~/Library/Safari is browsing history and bookmarks; the Safari *cache*
            // lives under ~/Library/Caches and is fair game.
            user.inHome("Library", "Safari"),
        ]
    }
}
