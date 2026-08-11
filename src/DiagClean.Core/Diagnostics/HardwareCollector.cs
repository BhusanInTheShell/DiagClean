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

        using (var searcher = new ManagementObjectSearcher(
            "SELECT Name, NumberOfCores, NumberOfLogicalProcessors FROM Win32_Processor"))
        {
            foreach (ManagementBaseObject mo in searcher.Get())
            {
                cpuName = mo["Name"]?.ToString()?.Trim() ?? cpuName;
                cores += ToInt(mo["NumberOfCores"]);
                logical += ToInt(mo["NumberOfLogicalProcessors"]);
            }
        }

        using (var searcher = new ManagementObjectSearcher("SELECT TotalPhysicalMemory FROM Win32_ComputerSystem"))
        {
            foreach (ManagementBaseObject mo in searcher.Get())
            {
                if (mo["TotalPhysicalMemory"] is not null)
                {
                    ramGb = Convert.ToDouble(mo["TotalPhysicalMemory"]) / (1024d * 1024 * 1024);
                }
            }
        }

        using (var searcher = new ManagementObjectSearcher("SELECT Manufacturer, Product FROM Win32_BaseBoard"))
        {
            foreach (ManagementBaseObject mo in searcher.Get())
            {
                mbManufacturer = mo["Manufacturer"]?.ToString() ?? "";
                mbModel = mo["Product"]?.ToString() ?? "";
            }
        }

        using (var searcher = new ManagementObjectSearcher("SELECT SMBIOSBIOSVersion FROM Win32_BIOS"))
        {
            foreach (ManagementBaseObject mo in searcher.Get())
            {
                bios = mo["SMBIOSBIOSVersion"]?.ToString() ?? "";
            }
        }

        using (var searcher = new ManagementObjectSearcher("SELECT Name FROM Win32_VideoController"))
        {
            foreach (ManagementBaseObject mo in searcher.Get())
            {
                var name = mo["Name"]?.ToString();
                if (!string.IsNullOrWhiteSpace(name))
                {
                    gpus.Add(name);
                }
            }
        }

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

    private static int ToInt(object? value) => value is null ? 0 : Convert.ToInt32(value);
}
