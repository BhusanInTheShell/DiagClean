using System.Runtime.Versioning;
using DiagClean.Core.Models;
using DiagClean.Core.Shell;

namespace DiagClean.Core.Optimize.Mac;

/// <summary>
/// A deliberately conservative set of maintenance actions - real, commonly-needed
/// helpdesk fixes (DNS issues, wrong-app-opens-file, Finder/Dock glitches, missing
/// search results), not deep system tweaks. Every command here was verified live on a
/// real Mac before being wired in, same discipline as the Diagnostics collectors.
/// </summary>
[SupportedOSPlatform("macos")]
public static class MacOptimizationActions
{
    private const string LsregisterPath =
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister";

    public static IReadOnlyList<IOptimizationAction> All =>
    [
        new DelegateOptimizationAction(
            "Flush DNS Cache",
            "Clears the local DNS resolver cache - fixes \"can't reach this site\" issues after a DNS change.",
            requiresElevation: true,
            isSlow: false,
            FlushDns),

        new DelegateOptimizationAction(
            "Rebuild LaunchServices Database",
            "Re-registers every installed app's file-type/URL associations - fixes " +
            "\"the wrong app opens this file\" and duplicate right-click menu entries.",
            requiresElevation: true,
            isSlow: false,
            RebuildLaunchServices),

        new DelegateOptimizationAction(
            "Restart Finder and Dock",
            "Restarts Finder and Dock - both relaunch automatically. Fixes visual " +
            "glitches and an unresponsive Finder or Dock.",
            requiresElevation: false,
            isSlow: false,
            RestartFinderAndDock),

        new DelegateOptimizationAction(
            "Clear Font Cache",
            "Clears the current user's font cache - fixes garbled or missing font " +
            "rendering. Regenerates automatically the next time it's needed.",
            requiresElevation: false,
            isSlow: false,
            ClearFontCache),

        new DelegateOptimizationAction(
            "Rebuild Spotlight Index",
            "Forces a full reindex of the boot volume - fixes \"Spotlight can't find " +
            "files that exist\". Can take anywhere from minutes to hours depending on " +
            "disk size, and search results are incomplete the whole time it runs.",
            requiresElevation: true,
            isSlow: true,
            RebuildSpotlightIndex),
    ];

    private static OptimizationResult FlushDns()
    {
        var flush = ShellRunner.RunWithExitCode("dscacheutil", ["-flushcache"], TimeSpan.FromSeconds(10));
        var reload = ShellRunner.RunWithExitCode("killall", ["-HUP", "mDNSResponder"], TimeSpan.FromSeconds(10));

        return new OptimizationResult
        {
            Success = flush.Succeeded && reload.Succeeded,
            Message = flush.Succeeded && reload.Succeeded
                ? "DNS cache flushed."
                : "Couldn't flush the DNS cache - re-run elevated (sudo)."
        };
    }

    private static OptimizationResult RebuildLaunchServices()
    {
        var result = ShellRunner.RunWithExitCode(
            LsregisterPath,
            ["-kill", "-r", "-domain", "local", "-domain", "system", "-domain", "user"],
            TimeSpan.FromSeconds(60));

        return new OptimizationResult
        {
            Success = result.Succeeded,
            Message = result.Succeeded
                ? "LaunchServices database rebuilt."
                : "Couldn't rebuild the LaunchServices database - re-run elevated (sudo)."
        };
    }

    private static OptimizationResult RestartFinderAndDock()
    {
        var finder = ShellRunner.RunWithExitCode("killall", ["Finder"], TimeSpan.FromSeconds(10));
        var dock = ShellRunner.RunWithExitCode("killall", ["Dock"], TimeSpan.FromSeconds(10));

        return new OptimizationResult
        {
            Success = finder.Succeeded && dock.Succeeded,
            Message = finder.Succeeded && dock.Succeeded
                ? "Finder and Dock restarted."
                : "Couldn't restart Finder/Dock (they may already have been unresponsive)."
        };
    }

    private static OptimizationResult ClearFontCache()
    {
        var result = ShellRunner.RunWithExitCode("atsutil", ["databases", "-removeUser"], TimeSpan.FromSeconds(15));

        return new OptimizationResult
        {
            Success = result.Succeeded,
            Message = result.Succeeded ? "Font cache cleared." : "Couldn't clear the font cache."
        };
    }

    private static OptimizationResult RebuildSpotlightIndex()
    {
        var result = ShellRunner.RunWithExitCode("mdutil", ["-E", "/"], TimeSpan.FromSeconds(30));

        return new OptimizationResult
        {
            Success = result.Succeeded,
            Message = result.Succeeded
                ? "Spotlight reindex started - it continues in the background after this tool exits."
                : "Couldn't start the Spotlight reindex - re-run elevated (sudo)."
        };
    }
}
