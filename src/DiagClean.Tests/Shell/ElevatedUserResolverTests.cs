using DiagClean.Core.Shell;
using Xunit;

namespace DiagClean.Tests.Shell;

public class ElevatedUserResolverTests
{
    // This test suite runs as a normal, non-elevated process - Environment.IsPrivilegedProcess
    // is false here, so both resolvers must no-op regardless of SUDO_USER, and
    // CleanTargetFactory's Mac branch must fall back to today's unchanged path resolution.
    // The elevated path itself can't be exercised without actually running as root.

    [Fact]
    public void TryGetOriginalUserTempDir_returns_null_when_not_elevated()
    {
        Assert.False(Environment.IsPrivilegedProcess);
        Assert.Null(ElevatedUserResolver.TryGetOriginalUserTempDir());
    }

    [Fact]
    public void TryGetOriginalUserHomeDir_returns_null_when_not_elevated()
    {
        Assert.False(Environment.IsPrivilegedProcess);
        Assert.Null(ElevatedUserResolver.TryGetOriginalUserHomeDir());
    }
}
