using DiagClean.Core.Models;
using DiagClean.Core.Reporting;
using Xunit;

namespace DiagClean.Tests.Reporting;

public class HtmlReportBuilderTests
{
    [Fact]
    public void Includes_machine_name_and_key_sections()
    {
        var report = new DiagnosticReport
        {
            MachineName = "TEST-PC01",
            GeneratedAt = DateTimeOffset.Now,
            CollectedBy = "tech1",
        };

        var html = HtmlReportBuilder.Build(report);

        Assert.Contains("TEST-PC01", html);
        Assert.Contains("Hardware Summary", html);
        Assert.Contains("Disk Health", html);
        Assert.Contains("Network Configuration", html);
    }

    [Fact]
    public void Html_encodes_untrusted_collector_data_to_prevent_injection()
    {
        var report = new DiagnosticReport
        {
            MachineName = "PC",
            GeneratedAt = DateTimeOffset.Now,
            CollectedBy = "tech",
            InstalledSoftware =
            [
                new InstalledSoftware { Name = "<script>alert(1)</script>", Version = "1.0", Publisher = "Evil" }
            ]
        };

        var html = HtmlReportBuilder.Build(report);

        Assert.DoesNotContain("<script>alert(1)</script>", html);
        Assert.Contains("&lt;script&gt;", html);
    }

    [Fact]
    public void Shows_empty_notices_when_no_data_was_collected()
    {
        var report = new DiagnosticReport
        {
            MachineName = "PC",
            GeneratedAt = DateTimeOffset.Now,
            CollectedBy = "tech",
        };

        var html = HtmlReportBuilder.Build(report);

        Assert.Contains("Hardware data unavailable", html);
        Assert.Contains("No disk data collected", html);
    }

    [Fact]
    public void Surfaces_collector_errors_as_a_notice()
    {
        var report = new DiagnosticReport
        {
            MachineName = "PC",
            GeneratedAt = DateTimeOffset.Now,
            CollectedBy = "tech",
            CollectorErrors = [new CollectorError("Disk Health", "Access denied")]
        };

        var html = HtmlReportBuilder.Build(report);

        Assert.Contains("Disk Health", html);
        Assert.Contains("Access denied", html);
        Assert.Contains("may be incomplete", html);
    }
}
