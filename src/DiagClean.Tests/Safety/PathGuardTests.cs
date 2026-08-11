using System.IO.Abstractions.TestingHelpers;
using DiagClean.Core.Safety;
using Xunit;

namespace DiagClean.Tests.Safety;

public class PathGuardTests
{
    [Fact]
    public void Allows_path_under_allowed_root_when_not_protected()
    {
        var fs = new MockFileSystem();
        var allowedRoot = fs.Path.Combine(fs.Path.GetTempPath(), "AllowedRoot");
        var guard = new PathGuard(fs, [allowedRoot], []);

        var candidate = fs.Path.Combine(allowedRoot, "sub", "file.txt");

        Assert.True(guard.IsAllowed(candidate, out var reason));
        Assert.Null(reason);
    }

    [Fact]
    public void Rejects_path_outside_allowed_roots()
    {
        var fs = new MockFileSystem();
        var allowedRoot = fs.Path.Combine(fs.Path.GetTempPath(), "AllowedRoot");
        var outsideRoot = fs.Path.Combine(fs.Path.GetTempPath(), "SomewhereElse");
        var guard = new PathGuard(fs, [allowedRoot], []);

        Assert.False(guard.IsAllowed(fs.Path.Combine(outsideRoot, "file.txt"), out var reason));
        Assert.Contains("outside", reason);
    }

    [Fact]
    public void Rejects_protected_path_even_when_inside_an_allowed_root()
    {
        var fs = new MockFileSystem();
        var allowedRoot = fs.Path.Combine(fs.Path.GetTempPath(), "AllowedRoot");
        var protectedPath = fs.Path.Combine(allowedRoot, "DoNotTouch");
        var guard = new PathGuard(fs, [allowedRoot], [protectedPath]);

        Assert.False(guard.IsAllowed(fs.Path.Combine(protectedPath, "file.txt"), out var reason));
        Assert.Contains("protected", reason);
    }

    [Fact]
    public void Allows_exact_match_of_the_allowed_root_itself()
    {
        var fs = new MockFileSystem();
        var allowedRoot = fs.Path.Combine(fs.Path.GetTempPath(), "AllowedRoot");
        var guard = new PathGuard(fs, [allowedRoot], []);

        Assert.True(guard.IsAllowed(allowedRoot, out _));
    }

    [Fact]
    public void Does_not_falsely_match_a_sibling_directory_with_a_shared_prefix()
    {
        // "AllowedRoot2" must not be treated as inside "AllowedRoot" purely because it
        // shares a string prefix - a naive StartsWith(root) check would get this wrong.
        var fs = new MockFileSystem();
        var allowedRoot = fs.Path.Combine(fs.Path.GetTempPath(), "AllowedRoot");
        var sibling = fs.Path.Combine(fs.Path.GetTempPath(), "AllowedRoot2");
        var guard = new PathGuard(fs, [allowedRoot], []);

        Assert.False(guard.IsAllowed(sibling, out _));
    }

    [Fact]
    public void Allowed_root_that_is_a_descendant_of_a_protected_root_stays_reachable()
    {
        // Regression guard: browser caches and %TEMP% live under the user's profile
        // directory, but personal folders like Documents must still be off-limits.
        // The two lists must be able to disagree on the same ancestor without one
        // silently swallowing the other.
        var fs = new MockFileSystem();
        var userProfile = fs.Path.Combine(fs.Path.GetTempPath(), "Users", "tech1");
        var appDataLocal = fs.Path.Combine(userProfile, "AppData", "Local");
        var documents = fs.Path.Combine(userProfile, "Documents");

        var guard = new PathGuard(fs, [appDataLocal], [documents]);

        Assert.True(guard.IsAllowed(fs.Path.Combine(appDataLocal, "Temp", "a.tmp"), out _));
        Assert.False(guard.IsAllowed(fs.Path.Combine(documents, "resume.docx"), out _));
    }
}
