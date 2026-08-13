using System.IO.Abstractions.TestingHelpers;
using DiagClean.Core.Models;
using DiagClean.Core.Safety;
using DiagClean.Core.Uninstall.Windows;
using Xunit;

namespace DiagClean.Tests.Uninstall.Windows;

/// <summary>
/// WindowsAppUninstaller isn't [SupportedOSPlatform("windows")] - it has no Windows-only
/// API calls, so these run unconditionally on any OS via MockFileSystem.
/// </summary>
public class WindowsAppUninstallerTests
{
    private static InstalledApp MakeApp(string name = "TestApp") => new()
    {
        Name = name,
        Identifier = @"C:\Program Files\TestApp\uninstall.exe",
        InstallPath = @"C:\Program Files\TestApp",
        SizeBytes = 1000
    };

    [Fact]
    public void Removes_confirmed_leftover_items_and_reports_app_removed_false()
    {
        var fs = new MockFileSystem();
        var root = fs.Path.Combine(fs.Path.GetTempPath(), "AppData");
        var leftoverPath = fs.Path.Combine(root, "TestApp");
        fs.AddFile(fs.Path.Combine(leftoverPath, "f"), new MockFileData("data"));

        var app = MakeApp();
        var guard = new PathGuard(fs, [root], []);
        var uninstaller = new WindowsAppUninstaller(fs, guard, [root]);

        var item = new AppLeftoverItem { FullPath = leftoverPath, SizeBytes = 500, IsDirectory = true };
        var outcome = uninstaller.RemoveDirectly(app, [item]);

        // Windows never marks the app itself as removed via RemoveDirectly - that
        // already happened (or didn't) via RunVendorUninstaller, a separate step.
        Assert.False(outcome.AppRemoved);
        Assert.Equal(1, outcome.LeftoverItemsRemoved);
        Assert.Equal(500, outcome.BytesFreed);
        Assert.Empty(outcome.Failures);
        Assert.False(fs.Directory.Exists(leftoverPath));
    }

    [Fact]
    public void Blocks_removal_of_a_path_outside_the_allowed_roots()
    {
        var fs = new MockFileSystem();
        var root = fs.Path.Combine(fs.Path.GetTempPath(), "AppData");
        var outsidePath = fs.Path.Combine(fs.Path.GetTempPath(), "SomewhereElse", "TestApp");
        fs.AddFile(fs.Path.Combine(outsidePath, "f"), new MockFileData("data"));

        var app = MakeApp();
        var guard = new PathGuard(fs, [root], []);
        var uninstaller = new WindowsAppUninstaller(fs, guard, [root]);

        var item = new AppLeftoverItem { FullPath = outsidePath, SizeBytes = 500, IsDirectory = true };
        var outcome = uninstaller.RemoveDirectly(app, [item]);

        Assert.Equal(0, outcome.LeftoverItemsRemoved);
        Assert.Single(outcome.Failures);
        Assert.True(fs.Directory.Exists(outsidePath));
    }

    [Theory]
    [InlineData(@"""C:\Program Files\App\uninstall.exe"" /S", @"C:\Program Files\App\uninstall.exe", "/S")]
    [InlineData(@"C:\Windows\System32\msiexec.exe /X{GUID}", @"C:\Windows\System32\msiexec.exe", "/X{GUID}")]
    [InlineData(@"""C:\App\uninstall.exe""", @"C:\App\uninstall.exe", "")]
    public void Parses_uninstall_string_command_lines_correctly(string commandLine, string expectedFile, string expectedArgs)
    {
        // ParseCommandLine is private - exercised indirectly via RunVendorUninstaller
        // would require actually launching a process, so this documents the expected
        // split via the same quoting rules real UninstallString values use.
        var (file, args) = InvokeParseCommandLine(commandLine);
        Assert.Equal(expectedFile, file);
        Assert.Equal(expectedArgs, args);
    }

    private static (string, string) InvokeParseCommandLine(string commandLine)
    {
        var method = typeof(WindowsAppUninstaller).GetMethod(
            "ParseCommandLine",
            System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Static)!;
        var result = ((string FileName, string Arguments))method.Invoke(null, [commandLine])!;
        return (result.FileName, result.Arguments);
    }
}
