import Foundation
import Hummingbird
import Darwin

/// GET /api/metrics — Real-time memory, CPU, and GPU utilization for this node.
/// Apple Silicon uses unified memory, so GPU VRAM is estimated from running model sizes.
struct MetricsHandler {

    static func handle(_ request: Request, _ context: some RequestContext) async throws -> Response {
        let metrics = await collectMetrics()
        let data = try JSONSerialization.data(withJSONObject: metrics)
        return Response(status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(data: data)))
    }

    static func collectMetrics() async -> [String: Any] {
        let totalRAM = ProcessInfo.processInfo.physicalMemory
        let usedRAM = getUsedMemoryBytes()
        let cpuPct = getCPUUsage()
        let gpuEstGB = await estimateGPUUsedGB()
        let totalGB = Double(totalRAM) / 1_073_741_824
        let usedGB = Double(usedRAM) / 1_073_741_824
        let usedPct = totalRAM > 0 ? Int(Double(usedRAM) / Double(totalRAM) * 100) : 0

        return [
            "ram_total_gb":  totalGB,
            "ram_used_gb":   usedGB,
            "ram_used_pct":  usedPct,
            "ram_free_gb":   totalGB - usedGB,
            "cpu_pct":       cpuPct,
            "gpu_est_gb":    gpuEstGB,
            "gpu_total_gb":  totalGB,   // Apple Silicon: unified memory, GPU can use all of it
            "timestamp":     Int(Date().timeIntervalSince1970)
        ]
    }

    // MARK: - Memory (via vm_statistics64)

    private static func getUsedMemoryBytes() -> UInt64 {
        var info = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let kern: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kern == KERN_SUCCESS else { return 0 }
        // active + wired pages = memory in use (inactive is file cache, available)
        let pageSize = UInt64(vm_kernel_page_size)
        return (UInt64(info.active_count) + UInt64(info.wire_count)) * pageSize
    }

    // MARK: - CPU (via host_cpu_load_info)

    private static var prevCPUTicks: (UInt32, UInt32, UInt32, UInt32) = (0, 0, 0, 0)

    private static func getCPUUsage() -> Double {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let kern: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kern == KERN_SUCCESS else { return 0 }

        let cur = info.cpu_ticks
        let prev = prevCPUTicks
        prevCPUTicks = cur

        let dUser   = Double(cur.0) - Double(prev.0)
        let dSystem = Double(cur.1) - Double(prev.1)
        let dIdle   = Double(cur.2) - Double(prev.2)
        let dTotal  = dUser + dSystem + dIdle
        guard dTotal > 0 else { return 0 }
        return (dUser + dSystem) / dTotal * 100
    }

    // MARK: - GPU estimation

    /// On Apple Silicon, GPU uses system RAM. Estimate based on which models are running.
    private static func estimateGPUUsedGB() async -> Double {
        var total = 0.0
        // Known VRAM footprints per model slot (rough 4-bit quant estimates)
        let modelGBMap: [String: Double] = [
            "main":   60,  // 122B MoE 4bit
            "fast":    8,  // 35B MoE 4bit
            "vision":  5,  // VL 8B 4bit
        ]
        await withTaskGroup(of: (String, Bool).self) { group in
            for (name, _) in modelGBMap {
                group.addTask {
                    let alive = await HealthHandler.isAlive(port: portForSlot(name))
                    return (name, alive)
                }
            }
            for await (name, alive) in group {
                if alive { total += modelGBMap[name] ?? 0 }
            }
        }
        return total
    }

    private static func portForSlot(_ name: String) -> Int {
        switch name {
        case "main":   return 5000
        case "fast":   return 5001
        case "vision": return 5002
        default:       return 5000
        }
    }
}
