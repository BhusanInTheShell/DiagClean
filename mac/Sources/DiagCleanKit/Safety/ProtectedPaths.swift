import Foundation

/// The built-in, non-overridable veto list. Nothing in configuration can remove an
/// entry here; user configuration can only add more on top.
///
/// Scoped to places that hold irreplaceable user data or credentials — not to broad
/// system roots. Broad roots are the *ancestors* of directories Clean legitimately
/// needs to reach (`~/Library/Caches` sits under `~/Library`, which sits under the
/// home directory), so protecting them would either break every target or, worse,
/// invite someone to carve exceptions back out. Real scoping comes from each target's
/// narrow allowed-roots list; this exists purely so a bug in one of those lists still
/// can't reach anything that matters.
public enum ProtectedPaths {
    public static func builtIn(for user: UserPaths) -> [String] {
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

            // App state that is not cache: mail stores, containers, preferences.
            user.inHome("Library", "Containers"),
            user.inHome("Library", "Group Containers"),
            user.inHome("Library", "Mail"),
            user.inHome("Library", "Messages"),
            user.inHome("Library", "Preferences"),
            user.inHome("Library", "Safari"),

            // DiagClean's own audit trail. A cleanup that erases the record of previous
            // cleanups is exactly the wrong behaviour for a tool meant to be defensible.
            user.appSupportDirectory,
        ]
    }
}
