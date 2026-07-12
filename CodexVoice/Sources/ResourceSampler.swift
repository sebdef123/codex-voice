import Darwin
import MachO

struct AppResourceSnapshot {
    let residentBytes: UInt64
    let cpuSeconds: Double

    static func capture() -> AppResourceSnapshot {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)

        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        _ = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
        let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
        return AppResourceSnapshot(residentBytes: UInt64(info.resident_size), cpuSeconds: user + system)
    }
}
