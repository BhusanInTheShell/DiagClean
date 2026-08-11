namespace DiagClean.Cli;

public static class FormatUtils
{
    private static readonly string[] Units = ["B", "KB", "MB", "GB", "TB"];

    public static string FormatSize(long bytes)
    {
        double value = bytes;
        var unitIndex = 0;
        while (value >= 1024 && unitIndex < Units.Length - 1)
        {
            value /= 1024;
            unitIndex++;
        }

        return unitIndex == 0 ? $"{value:0} {Units[unitIndex]}" : $"{value:0.#} {Units[unitIndex]}";
    }
}
