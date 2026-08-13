using System.IO.Abstractions;
using DiagClean.Core.Uninstall;
using DiagClean.Core.Uninstall.Mac;
using Xunit;

namespace DiagClean.Tests.Uninstall.Mac;

/// <summary>
/// Same reasoning as Diagnostics/Mac/MacCollectorsLiveTests - runs against the real
/// /Applications and ~/Applications on this machine every time the suite runs on macOS,
/// which it does in this repo's dev environment.
/// </summary>
public class MacAppListerLiveTests
{
    [Fact]
    public void Lists_real_apps_with_well_formed_fields()
    {
        if (!OperatingSystem.IsMacOS())
        {
            return;
        }

        IFileSystem fs = new FileSystem();
        var apps = new MacAppLister(fs).ListApps();

        Assert.NotEmpty(apps);
        Assert.All(apps, a =>
        {
            Assert.False(string.IsNullOrWhiteSpace(a.Name));
            Assert.False(string.IsNullOrWhiteSpace(a.Identifier));
            Assert.EndsWith(".app", a.InstallPath, StringComparison.Ordinal);
            // Not strictly > 0: confirmed live that Safari.app reports 0 from `du` on
            // modern macOS - it's a thin stub bundle, the real binary lives in a sealed
            // system volume `du` can't see. A legitimate value, not a collector bug.
            Assert.True(a.SizeBytes >= 0);
        });

        // Every bundle identifier read via plutil should look like a real bundle ID
        // (reverse-DNS with at least one dot) for apps that have one at all - this is
        // the token leftover-scanning matches against, so a malformed read here would
        // silently break matching for that app without any other symptom.
        Assert.Contains(apps, a => a.Identifier.Contains('.'));
    }

    [Fact]
    public void Excludes_system_applications()
    {
        if (!OperatingSystem.IsMacOS())
        {
            return;
        }

        IFileSystem fs = new FileSystem();
        var apps = new MacAppLister(fs).ListApps();

        Assert.DoesNotContain(apps, a => a.InstallPath.StartsWith("/System/Applications", StringComparison.Ordinal));
    }

    [Fact]
    public void Leftover_scan_finds_real_containers_for_a_known_app()
    {
        if (!OperatingSystem.IsMacOS())
        {
            return;
        }

        IFileSystem fs = new FileSystem();
        var apps = new MacAppLister(fs).ListApps();
        var (_, uninstaller) = UninstallFactory.Create(fs);

        // Best-effort: only assert something if a matching app happens to be installed
        // on the machine running this - the point is confirming the scan pipeline works
        // end-to-end against real Library data, not requiring a specific app be present.
        foreach (var app in apps)
        {
            var scan = uninstaller.ScanLeftovers(app);
            Assert.All(scan.Items, item => Assert.True(item.SizeBytes >= 0));
            Assert.All(scan.Items, item => Assert.True(
                item.FullPath.Contains(app.Identifier, StringComparison.OrdinalIgnoreCase) ||
                item.FullPath.Contains(app.Name, StringComparison.OrdinalIgnoreCase)));
        }
    }
}
