namespace DiagClean.Cli;

public static class AppPaths
{
    public static string DataDirectory =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DiagClean");

    public static string LogsDirectory => Path.Combine(DataDirectory, "logs");

    public static string ReportsDirectory => Path.Combine(DataDirectory, "reports");

    public static string SettingsFilePath =>
        Path.Combine(AppContext.BaseDirectory, "appsettings.json");

    public static void EnsureDataDirectories()
    {
        Directory.CreateDirectory(LogsDirectory);
        Directory.CreateDirectory(ReportsDirectory);
    }
}
