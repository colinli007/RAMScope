import AppKit
import Darwin

struct ProcessMemory: Identifiable, Codable, Sendable {
    let id: Int32
    let name: String
    let bytes: UInt64
}

struct AppMemoryGroup: Identifiable, Codable, Sendable {
    let id: String
    let name: String
    /// nil when no app owns the process tree; the group is then named after the tree's root command.
    let bundlePath: String?
    let bytes: UInt64
    let processes: [ProcessMemory]
}

struct MemorySnapshot: Codable, Sendable {
    let groups: [AppMemoryGroup]
    /// Activity Monitor's "Memory Used": app memory + wired + compressed.
    let usedBytes: UInt64
    let totalBytes: UInt64
    let timestamp: Date
}

struct RunningApp: Sendable {
    let pid: pid_t
    let path: String
    let name: String

    @MainActor
    static func current() -> [Self] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard !app.isTerminated, let url = app.bundleURL,
                  let path = enclosingApp(in: url.standardizedFileURL.path) else { return nil }
            let name = path == url.standardizedFileURL.path
                ? app.localizedName ?? appName(at: path)
                : appName(at: path)
            return Self(pid: app.processIdentifier, path: path, name: name)
        }
    }
}

private func enclosingApp(in path: String) -> String? {
    // The outer bundle owns nested Helper.app executables, including helpers
    // started directly by launchd rather than by the main process.
    guard let range = path.range(of: ".app/", options: .caseInsensitive) else {
        return path.lowercased().hasSuffix(".app") ? path : nil
    }
    return String(path[..<path.index(before: range.upperBound)])
}

private func appName(at path: String) -> String {
    let bundle = Bundle(path: path)
    return bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
}

enum MemorySampler {
    /// Memory belongs to whoever started the process: the nearest app on the parent chain,
    /// or, when the chain never reaches an app, the root of its process tree.
    private enum Owner: Hashable {
        case app(path: String)
        case command(name: String)
    }

    private struct Process {
        let pid: pid_t
        let parent: pid_t
        let uid: uid_t
        let started: UInt64
        let executable: String?
        let name: String
    }

    static func sample(apps: [RunningApp]) -> MemorySnapshot {
        let uid = getuid()
        // The ownership chain spans every user: terminals start shells through the
        // setuid-root /usr/bin/login, so only the memory totals are limited to this user.
        let processes = processTable()
        let byPID = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })
        var names = [String: String]()
        var owners = [pid_t: String]()
        for app in apps {
            names[app.path] = app.name
            owners[app.pid] = app.path
        }

        // Some bundled background apps do not appear in NSWorkspace.
        var bundledPaths = [pid_t: String]()
        for process in processes {
            guard let executable = process.executable, let path = enclosingApp(in: executable) else { continue }
            bundledPaths[process.pid] = path
            if names[path] == nil, Bundle(path: path)?.executableURL?.path == executable {
                names[path] = appName(at: path)
            }
        }
        for (pid, path) in bundledPaths where names[path] != nil {
            owners[pid] = path
        }

        var members = [Owner: [ProcessMemory]]()
        for process in processes where process.uid == uid {
            guard let bytes = footprint(of: process.pid) else { continue }
            let owner = owner(of: process, direct: owners, processes: byPID)
            members[owner, default: []].append(ProcessMemory(id: process.pid, name: process.name, bytes: bytes))
        }

        var groups: [AppMemoryGroup] = members.map { owner, items in
            let sortedItems = items.sorted { first, second in
                first.bytes == second.bytes ? first.id < second.id : first.bytes > second.bytes
            }
            let total = items.reduce(UInt64(0)) { $0 + $1.bytes }
            switch owner {
            case .app(let path):
                return AppMemoryGroup(
                    id: path,
                    name: names[path] ?? appName(at: path),
                    bundlePath: path,
                    bytes: total,
                    processes: sortedItems
                )
            case .command(let name):
                // Bundle paths are absolute, so a bare command name never collides with an app id.
                return AppMemoryGroup(id: name, name: name, bundlePath: nil, bytes: total, processes: sortedItems)
            }
        }
        groups.sort { first, second in
            if first.bytes != second.bytes { return first.bytes > second.bytes }
            let order = first.name.localizedStandardCompare(second.name)
            return order == .orderedSame ? first.id < second.id : order == .orderedAscending
        }
        return MemorySnapshot(
            groups: groups,
            usedBytes: systemUsedBytes(),
            totalBytes: ProcessInfo.processInfo.physicalMemory,
            timestamp: Date()
        )
    }

    private static func systemUsedBytes() -> UInt64 {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }

        let appPages = UInt64(stats.internal_page_count) - UInt64(stats.purgeable_count)
        let pages = appPages + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        return pages * UInt64(getpagesize())
    }

    private static func owner(
        of process: Process,
        direct: [pid_t: String],
        processes: [pid_t: Process]
    ) -> Owner {
        var current = process
        while true {
            if let path = direct[current.pid] { return .app(path: path) }
            guard let parent = processes[current.parent],
                  parent.pid != current.pid, parent.started < current.started else {
                return .command(name: current.name)
            }
            current = parent
        }
    }

    /// Unlike PROC_PIDTBSDINFO, the kernel process table also exposes other users' processes.
    private static func processTable() -> [Process] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
        let stride = MemoryLayout<kinfo_proc>.stride
        // Retry when processes started between sizing the buffer and filling it.
        for _ in 0..<3 {
            var size = 0
            guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0 else { return [] }
            var entries = [kinfo_proc](repeating: kinfo_proc(), count: size / stride + 64)
            size = entries.count * stride
            if sysctl(&mib, u_int(mib.count), &entries, &size, nil, 0) == 0 {
                return entries.prefix(size / stride).compactMap(readProcess)
            }
            guard errno == ENOMEM else { return [] }
        }
        return []
    }

    private static func readProcess(_ entry: kinfo_proc) -> Process? {
        let pid = entry.kp_proc.p_pid
        guard pid > 1 else { return nil }
        // PROC_PIDPATHINFO_MAXSIZE is defined as 4 * MAXPATHLEN in the SDK.
        var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = buffer.withUnsafeMutableBytes {
            proc_pidpath(pid, $0.baseAddress, UInt32($0.count))
        }
        let path = length > 0
            ? String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
            : nil
        let name = path.map { URL(fileURLWithPath: $0).lastPathComponent }
            ?? withUnsafeBytes(of: entry.kp_proc.p_comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        let start = entry.kp_proc.p_starttime
        return Process(
            pid: pid,
            parent: entry.kp_eproc.e_ppid,
            uid: entry.kp_eproc.e_ucred.cr_uid,
            started: UInt64(start.tv_sec) * 1_000_000 + UInt64(start.tv_usec),
            executable: path,
            name: name.isEmpty ? "PID \(pid)" : name
        )
    }

    private static func footprint(of pid: pid_t) -> UInt64? {
        var usage = rusage_info_v0()
        let result = withUnsafeMutablePointer(to: &usage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V0, $0)
            }
        }
        return result == 0 ? usage.ri_phys_footprint : nil
    }
}
