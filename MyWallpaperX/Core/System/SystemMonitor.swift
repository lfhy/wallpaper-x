//
//  SystemMonitor.swift
//  MyWallpaperX
//
//  系统状态监控 — CPU、内存、网络速率、GPU 使用率、SMC 温度（沙盒降级）
//  本文件遵循 macOS26 设计规范，尽量调用原生接口实现
//

import Foundation
import Darwin
import IOKit
import IOKit.ps

// MARK: - 数据模型

struct SystemStats {
    /// CPU 总使用率 0.0 ~ 1.0
    var cpuUsage: Double = 0
    /// 已用物理内存（字节）
    var memUsed: UInt64 = 0
    /// 总物理内存（字节）
    var memTotal: UInt64 = 0
    /// 网络上行字节/秒
    var netUpBytesPerSec: Double = 0
    /// 网络下行字节/秒
    var netDownBytesPerSec: Double = 0
    /// GPU 使用率 0.0 ~ 1.0，nil 表示读取失败
    var gpuUsage: Double? = nil
    /// CPU 温度（摄氏度），nil 表示沙盒/权限受限读不到
    var cpuTemperature: Double? = nil
    /// GPU 温度（摄氏度），nil 表示读不到
    var gpuTemperature: Double? = nil
}

// MARK: - SystemMonitor

/// 轻量系统指标采集器。
/// 调用 `refresh()` 更新 `stats`，由外部驱动（菜单打开时 / 定时器）。
/// 网速计算需要两次采样差值，第一次调用时速率显示为 0。
final class SystemMonitor {

    static let shared = SystemMonitor()

    private(set) var stats = SystemStats()

    // 网络上次采样
    private var lastNetUp: UInt64 = 0
    private var lastNetDown: UInt64 = 0
    private var lastNetSampleTime: Date = .distantPast

    // CPU 上次采样的 ticks
    private var lastCPUTicks: (user: UInt64, sys: UInt64, idle: UInt64, nice: UInt64) = (0, 0, 0, 0)

    private init() {}

    // MARK: - 主入口

    /// 刷新所有指标，写入 `stats`。在 main thread 调用安全（I/O 开销极小）。
    func refresh() {
        refreshRuntimeStats()
        readSMCTemperatures(into: &stats)
    }

    /// 刷新状态栏运行时指标。
    /// 只覆盖 CPU / 内存 / 网络 / GPU，避免高频刷新时反复访问 SMC。
    func refreshRuntimeStats() {
        stats.cpuUsage  = readCPUUsage()
        readMemory(into: &stats)
        readNetwork(into: &stats)
        stats.gpuUsage  = readGPUUsage()
    }

    // MARK: - CPU 使用率

    private func readCPUUsage() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return stats.cpuUsage }

        let user = UInt64(info.cpu_ticks.0)
        let sys  = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2)
        let nice = UInt64(info.cpu_ticks.3)

        let dUser  = user &- lastCPUTicks.user
        let dSys   = sys  &- lastCPUTicks.sys
        let dIdle  = idle &- lastCPUTicks.idle
        let dNice  = nice &- lastCPUTicks.nice
        let dTotal = dUser + dSys + dIdle + dNice

        lastCPUTicks = (user, sys, idle, nice)
        guard dTotal > 0 else { return stats.cpuUsage }
        return Double(dUser + dSys + dNice) / Double(dTotal)
    }

    // MARK: - 内存

    private func readMemory(into s: inout SystemStats) {
        s.memTotal = ProcessInfo.processInfo.physicalMemory

        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let page       = UInt64(vm_page_size)
        let wired      = UInt64(vmStats.wire_count)            * page
        let active     = UInt64(vmStats.active_count)          * page
        let compressed = UInt64(vmStats.compressor_page_count) * page
        s.memUsed = wired + active + compressed
    }

    // MARK: - 网络速率

    private func readNetwork(into s: inout SystemStats) {
        let (up, down) = rawNetworkBytes()
        let now = Date()
        let elapsed = now.timeIntervalSince(lastNetSampleTime)

        if elapsed > 0.1 && (lastNetUp > 0 || lastNetDown > 0) {
            let dUp   = up   >= lastNetUp   ? up   - lastNetUp   : 0
            let dDown = down >= lastNetDown ? down - lastNetDown : 0
            s.netUpBytesPerSec   = Double(dUp)   / elapsed
            s.netDownBytesPerSec = Double(dDown) / elapsed
        }

        lastNetUp         = up
        lastNetDown       = down
        lastNetSampleTime = now
    }

    private func rawNetworkBytes() -> (up: UInt64, down: UInt64) {
        var up: UInt64 = 0
        var down: UInt64 = 0
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&ifaddrPtr) == 0, let base = ifaddrPtr else { return (0, 0) }
        defer { freeifaddrs(base) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = base
        while let ifa = cursor {
            defer { cursor = ifa.pointee.ifa_next }
            guard ifa.pointee.ifa_addr.pointee.sa_family == UInt8(AF_LINK) else { continue }
            let name = String(cString: ifa.pointee.ifa_name)
            // 跳过回环和虚拟接口，只统计物理网卡
            let skip = name.hasPrefix("lo") || name.hasPrefix("utun") ||
                       name.hasPrefix("ipsec") || name.hasPrefix("gif") ||
                       name.hasPrefix("stf") || name.hasPrefix("XHC") ||
                       name.hasPrefix("bridge") || name.hasPrefix("p2p")
            guard !skip else { continue }

            if let dataPtr = ifa.pointee.ifa_data {
                let ifData = dataPtr.load(as: if_data.self)
                up   &+= UInt64(ifData.ifi_obytes)
                down &+= UInt64(ifData.ifi_ibytes)
            }
        }
        return (up, down)
    }

    // MARK: - GPU 使用率（IOAccelerator，沙盒可用）

    private func readGPUUsage() -> Double? {
        let matchDict = IOServiceMatching("IOAccelerator") as NSMutableDictionary
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matchDict, &iter) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iter) }

        var maxUsage: Double? = nil
        var service = IOIteratorNext(iter)
        while service != IO_OBJECT_NULL {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iter)
            }
            var props: Unmanaged<CFMutableDictionary>? = nil
            guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any] else { continue }

            // Apple Silicon / AMD: PerformanceStatistics 字典内含 GPU Core Utilization
            if let perfStats = dict["PerformanceStatistics"] as? [String: Any] {
                // Apple Silicon
                if let util = perfStats["GPU Core Utilization"] as? Double {
                    let pct = util / 1_000_000.0   // 单位是 millipercent (1e-6)
                    maxUsage = max(maxUsage ?? 0, min(1.0, pct))
                } else if let util = perfStats["Device Utilization %"] as? Double {
                    maxUsage = max(maxUsage ?? 0, min(1.0, util / 100.0))
                } else if let util = perfStats["Accelerator Utilization"] as? Int {
                    maxUsage = max(maxUsage ?? 0, min(1.0, Double(util) / 100.0))
                }
            }
        }
        return maxUsage
    }

    // MARK: - SMC 温度（沙盒降级：读不到时返回 nil）
    //
    // Apple Silicon 上 SMC 键名：
    //   CPU 温度: "Tp09"（效能核）或 "Tp05"（性能核）
    //   GPU 温度: "Tg05"
    // 以上键名在不同 M 系列型号上可能不同，以实际可读到的为准。

    private func readSMCTemperatures(into s: inout SystemStats) {
        // 尝试打开 AppleSMC 服务
        let smcService = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSMC")
        )
        guard smcService != IO_OBJECT_NULL else {
            // 沙盒下无法访问 SMC，正常降级
            s.cpuTemperature = nil
            s.gpuTemperature = nil
            return
        }
        defer { IOObjectRelease(smcService) }

        // Apple Silicon CPU 温度候选键（按优先级排列）
        let cpuKeys = ["Tp09", "Tp05", "Tp01", "TC0P", "TC0D"]
        // Apple Silicon GPU 温度候选键
        let gpuKeys = ["Tg05", "Tg0D", "TGDD"]

        s.cpuTemperature = readSMCKey(from: smcService, candidates: cpuKeys)
        s.gpuTemperature = readSMCKey(from: smcService, candidates: gpuKeys)
    }

    /// 依次尝试候选键名，返回第一个成功读取的温度值（摄氏度）
    private func readSMCKey(from service: io_object_t, candidates: [String]) -> Double? {
        for key in candidates {
            if let temp = smcReadTemperature(service: service, key: key), temp > 0 {
                return temp
            }
        }
        return nil
    }

    /// 通过 IOConnectCallStructMethod 读取单个 SMC 键值
    private func smcReadTemperature(service: io_object_t, key: String) -> Double? {
        var conn: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &conn) == KERN_SUCCESS else { return nil }
        defer { IOServiceClose(conn) }

        // SMCKeyData 结构体（64 字节，与 AppleSMC kext 匹配）
        var inputStruct  = SMCKeyData()
        var outputStruct = SMCKeyData()
        var inputSize    = MemoryLayout<SMCKeyData>.size
        var outputSize   = MemoryLayout<SMCKeyData>.size

        // 先查询键信息（selector 9 = kSMCGetKeyInfo）
        inputStruct.key = fourCharCode(key)
        inputStruct.data8 = UInt8(kSMCGetKeyInfo)
        let infoResult = IOConnectCallStructMethod(
            conn, UInt32(kSMCHandleYPCEvent),
            &inputStruct, inputSize,
            &outputStruct, &outputSize
        )
        guard infoResult == KERN_SUCCESS, outputStruct.result == 0 else { return nil }

        let dataType = outputStruct.keyInfo.dataType
        let dataSize = Int(outputStruct.keyInfo.dataSize)

        // 读取键值（selector 5 = kSMCReadKey）
        inputStruct = SMCKeyData()
        inputStruct.key = fourCharCode(key)
        inputStruct.keyInfo.dataSize = outputStruct.keyInfo.dataSize
        inputStruct.data8 = UInt8(kSMCReadKey)
        var readOutput = SMCKeyData()

        let readResult = IOConnectCallStructMethod(
            conn, UInt32(kSMCHandleYPCEvent),
            &inputStruct, inputSize,
            &readOutput, &outputSize
        )
        guard readResult == KERN_SUCCESS, readOutput.result == 0 else { return nil }

        // 解析温度值（sp78 格式：Apple 定点数，1/256 摄氏度）
        let sp78Type = fourCharCode("sp78")
        let flt_Type = fourCharCode("flt ")
        let ui8_Type = fourCharCode("ui8 ")

        if dataType == sp78Type, dataSize >= 2 {
            let raw = (Int16(readOutput.bytes.0) << 8) | Int16(readOutput.bytes.1)
            return Double(raw) / 256.0
        } else if dataType == flt_Type, dataSize >= 4 {
            var raw: UInt32 = 0
            raw |= UInt32(readOutput.bytes.0) << 24
            raw |= UInt32(readOutput.bytes.1) << 16
            raw |= UInt32(readOutput.bytes.2) << 8
            raw |= UInt32(readOutput.bytes.3)
            return Double(Float(bitPattern: raw))
        } else if dataType == ui8_Type, dataSize >= 1 {
            return Double(readOutput.bytes.0)
        }
        return nil
    }

    private func fourCharCode(_ s: String) -> UInt32 {
        var result: UInt32 = 0
        for (i, c) in s.utf8.prefix(4).enumerated() {
            result |= UInt32(c) << (24 - i * 8)
        }
        return result
    }
}

// MARK: - 格式化工具

extension SystemStats {
    /// CPU 百分比字符串，如 "12%"
    var cpuUsageString: String {
        String(format: "%d%%", Int((cpuUsage * 100).rounded()))
    }

    /// GPU 百分比字符串，如 "34%"，读不到时返回 "–"
    var gpuUsageString: String {
        guard let g = gpuUsage else { return "–" }
        return String(format: "%d%%", Int((g * 100).rounded()))
    }

    /// 已用内存字符串，如 "6.8 GB"
    var memUsedString: String { formatBytes(memUsed, style: .memory) }

    /// 总内存字符串，如 "16 GB"
    var memTotalString: String { formatBytes(memTotal, style: .memory) }

    /// 网络上行速率，如 "2.1 MB/s"
    var netUpString: String { formatBytes(UInt64(netUpBytesPerSec), style: .speed) }

    /// 网络下行速率，如 "850 KB/s"
    var netDownString: String { formatBytes(UInt64(netDownBytesPerSec), style: .speed) }

    /// CPU 温度字符串，如 "52°C"，读不到时返回 nil
    var cpuTempString: String? {
        guard let t = cpuTemperature else { return nil }
        return String(format: "%.0f°C", t)
    }

    /// GPU 温度字符串，如 "61°C"，读不到时返回 nil
    var gpuTempString: String? {
        guard let t = gpuTemperature else { return nil }
        return String(format: "%.0f°C", t)
    }

    private enum FormatStyle { case memory, speed }

    private func formatBytes(_ bytes: UInt64, style: FormatStyle) -> String {
        let suffix = style == .speed ? "/s" : ""
        let kb = Double(bytes) / 1024
        let mb = kb / 1024
        let gb = mb / 1024
        if gb >= 1 { return String(format: "%.1f GB", gb) + suffix }
        if mb >= 1 { return String(format: "%.1f MB", mb) + suffix }
        if kb >= 1 { return String(format: "%.0f KB", kb) + suffix }
        return "\(bytes) B" + suffix
    }
}

// MARK: - SMC 数据结构
// 与 AppleSMC kext 内部 C 结构体对应，必须保持 64 字节对齐

private let kSMCHandleYPCEvent = 2
private let kSMCReadKey        = 5
private let kSMCGetKeyInfo     = 9

private struct SMCKeyInfo {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

private struct SMCKeyData {
    var key: UInt32 = 0
    var vers: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0, 0, 0)
    var pLimitData: UInt16 = 0
    var keyInfo: SMCKeyInfo = SMCKeyInfo()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    // 32 字节数据区，覆盖所有 SMC 数据类型（sp78/flt/ui8 等）
    var bytes: (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    ) = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )
} 
