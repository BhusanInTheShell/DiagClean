namespace DiagClean.Core.Shell;

/// <summary>
/// When DiagClean runs elevated on macOS (`sudo dclean ...`), APIs that resolve
/// per-user paths based on the *current process's* effective UID - notably
/// Path.GetTempPath(), which maps to confstr(_CS_DARWIN_USER_TEMP_DIR) - resolve to
/// root's own per-boot temp namespace, not the invoking human's. Root's namespace is
/// populated by live system-daemon IPC sockets and lock files (e.g.
/// com.apple.ImageIOXPCService, lockdownmoded), not leftover user junk - scanning it as
/// if it were regular temp clutter finds hundreds of undeletable (and undeletable for
/// good reason - they're in active use) entries instead of real space to reclaim.
///
/// This resolves the original invoking user's temp directory instead, via SUDO_USER,
/// so an elevated run cleans that user's actual files (with permission to remove ones a
/// non-elevated run couldn't touch) rather than wandering into root's own namespace.
/// </summary>
public static class ElevatedUserResolver
{
    public static string? TryGetOriginalUserTempDir()
    {
        if (!OperatingSystem.IsMacOS() || !Environment.IsPrivilegedProcess)
        {
            return null;
        }

        var sudoUser = Environment.GetEnvironmentVariable("SUDO_USER");
        if (string.IsNullOrWhiteSpace(sudoUser) || sudoUser == "root")
        {
            return null;
        }

        // Root can `sudo -u <user>` without re-authenticating, so this doesn't prompt
        // for a second password - it's just asking the OS for that user's own temp dir.
        var output = ShellRunner.Run(
            "sudo", ["-u", sudoUser, "getconf", "DARWIN_USER_TEMP_DIR"], TimeSpan.FromSeconds(5));

        return string.IsNullOrWhiteSpace(output) ? null : output.Trim();
    }

    /// <summary>
    /// Same concern as <see cref="TryGetOriginalUserTempDir"/> but for HOME: whether
    /// `sudo` preserves or resets HOME for the elevated process depends on the
    /// sudoers `env_reset`/`always_set_home` configuration, which varies by machine.
    /// Rather than assume either way, ask `dscl` directly for the invoking user's real
    /// home directory whenever running elevated - cheap, and removes the ambiguity
    /// instead of relying on it going the right way.
    /// </summary>
    public static string? TryGetOriginalUserHomeDir()
    {
        if (!OperatingSystem.IsMacOS() || !Environment.IsPrivilegedProcess)
        {
            return null;
        }

        var sudoUser = Environment.GetEnvironmentVariable("SUDO_USER");
        if (string.IsNullOrWhiteSpace(sudoUser) || sudoUser == "root")
        {
            return null;
        }

        var output = ShellRunner.Run(
            "dscl", [".", "-read", $"/Users/{sudoUser}", "NFSHomeDirectory"], TimeSpan.FromSeconds(5));
        if (string.IsNullOrWhiteSpace(output))
        {
            return null;
        }

        // Output format: "NFSHomeDirectory: /Users/username"
        var separatorIndex = output.IndexOf(':');
        return separatorIndex >= 0 ? output[(separatorIndex + 1)..].Trim() : null;
    }
}
