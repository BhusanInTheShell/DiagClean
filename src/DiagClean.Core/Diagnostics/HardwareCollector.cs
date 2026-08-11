using System.Management;
using System.Runtime.Versioning;
using DiagClean.Core.Models;

namespace DiagClean.Core.Diagnostics;

[SupportedOSPlatform("windows")]
public sealed class HardwareCollector : IHardwareCollector
{
    public HardwareInfo Collect()
    {
        var cpuName = "";
        var cores = 0;
        var logical = 0;
        var ramGb = 0d;
        var mbManufacturer = "";
        var mbModel = "";
        var bios = "";
        var gpus = new List<string>();

        // Each WMI class is queried independently and failures are swallowed per-query -
        // some classes (Win32_VideoController in particular) are known to fail on headless
        // servers and certain hypervisors. One flaky class shouldn't discard the CPU/RAM/
        // motherboard data already gathered from the others.
        RunQuery("SELECT Name, NumberOfCores, NumberOfLogicalProcessors FROM Win32_Processor", mo =>
        {
            cpuName = mo["Name"]?.ToString()?.Trim() ?? cpuName;
            cores += ToInt(mo["NumberOfCores"]);
            logical += ToInt(mo["NumberOfLogicalProcessors"]);
        });

        RunQuery("SELECT TotalPhysicalMemory FROM Win32_ComputerSystem", mo =>
        {
            if (mo["TotalPhysicalMemory"] is not null)
            {
                ramGb = Convert.ToDouble(mo["TotalPhysicalMemory"]) / (1024d * 1024 * 1024);
            }
        });

        RunQuery("SELECT Manufacturer, Product FROM Win32_BaseBoard", mo =>
        {
            mbManufacturer = mo["Manufacturer"]?.ToString() ?? "";
            mbModel = mo["Product"]?.ToString() ?? "";
        });

        RunQuery("SELECT SMBIOSBIOSVersion FROM Win32_BIOS", mo =>
        {
            bios = mo["SMBIOSBIOSVersion"]?.ToString() ?? "";
        });

        RunQuery("SELECT Name FROM Win32_VideoController", mo =>
        {
            var name = mo["Name"]?.ToString();
            if (!string.IsNullOrWhiteSpace(name))
            {
                gpus.Add(name);
            }
        });

        return new HardwareInfo
        {
            CpuName = cpuName,
            CpuCores = cores,
            CpuLogicalProcessors = logical,
            TotalRamGb = Math.Round(ramGb, 1),
            MotherboardManufacturer = mbManufacturer,
            MotherboardModel = mbModel,
            BiosVersion = bios,
            GpuNames = gpus
        };
    }

    private static void RunQuery(string wql, Action<ManagementBaseObject> onEach)
    {
        try
        {
            using var searcher = new ManagementObjectSearcher(wql);
            foreach (ManagementBaseObject mo in searcher.Get())
            {
                onEach(mo);
            }
        }
        catch (ManagementException)
        {
            // This particular WMI class is unavailable/unsupported on this machine - the
            // fields it would have populated are left at their defaults.
        }
    }

    private static int ToInt(object? value) => value is null ? 0 : Convert.ToInt32(value);
}
