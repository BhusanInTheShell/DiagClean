namespace DiagClean.Cli;

public static class FormatUtils
{
    private static readonly string[] Units = ["B", "KB", "MB", "GB", "TB"];

    public static string FormatSize(long bytes) => FormatSize((double)bytes);

    public static string FormatSize(double bytes)
    {
        var value = bytes;
        var unitIndex = 0;
        while (value >= 1024 && unitIndex < Units.Length - 1)
        {
            value /= 1024;
            unitIndex++;
        }

        return unitIndex == 0 ? $"{value:0} {Units[unitIndex]}" : $"{value:0.#} {Units[unitIndex]}";
    }

    public static string FormatRate(double bytesPerSecond) => $"{FormatSize(bytesPerSecond)}/s";

    /// <summary>Renders a proportional bar using block characters, e.g. "████░░░░░░"
    /// for 40%. Shared by Analyze (relative size of a folder) and Status (percentage of
    /// a resource used).</summary>
    public static string RenderBar(double percent, int width = 20)
    {
        var filled = Math.Clamp((int)Math.Round(percent / 100 * width), 0, width);
        return new string('█', filled) + new string('░', width - filled);
    }
}
