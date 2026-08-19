import Darwin
import Foundation

/// Reads process metadata through libproc and sysctl. No subprocesses.
///
/// Every lookup can fail. Hardened-runtime and Apple-signed processes refuse
/// `proc_pidinfo` from a non-root caller, so each accessor returns an optional and
/// the caller degrades rather than dropping the service.
public struct ProcessInspector: Sendable {
    public init() {}

    /// Skeleton of every process on the machine: pid, parent, owner and start
    /// time, in one syscall.
    ///
    /// `proc_listallpids` is not used because it under-reports badly. On this
    /// machine it returned 159 of 641 processes, which silently orphaned most
    /// listeners. `sysctl(KERN_PROC_ALL)` is what `ps` itself uses.
    ///
    /// Executable path, argv and cwd are deliberately absent. They cost three
    /// syscalls each and are only needed for listeners and their ancestors.
    public func processSkeleton() -> [ProcessSnapshot] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }

        let stride = MemoryLayout<kinfo_proc>.stride
        // Processes can be created between sizing and reading, so ask for headroom.
        var entries = [kinfo_proc](repeating: kinfo_proc(), count: size / stride + 64)
        var readSize = entries.count * stride
        let status = entries.withUnsafeMutableBytes { pointer in
            sysctl(&mib, 4, pointer.baseAddress, &readSize, nil, 0)
        }
        guard status == 0 else { return [] }

        return entries.prefix(readSize / stride).compactMap { entry in
            let pid = entry.kp_proc.p_pid
            guard pid > 0 else { return nil }
            let started = entry.kp_proc.p_un.__p_starttime
            return ProcessSnapshot(
                pid: pid,
                parentPID: entry.kp_eproc.e_ppid,
                uid: entry.kp_eproc.e_ucred.cr_uid,
                startTime: Date(timeIntervalSince1970: TimeInterval(started.tv_sec))
            )
        }
    }

    public func snapshot(pid: pid_t) -> ProcessSnapshot? {
        guard let bsd = bsdInfo(pid: pid) else { return nil }
        return ProcessSnapshot(
            pid: pid,
            parentPID: pid_t(bsd.pbi_ppid),
            uid: bsd.pbi_uid,
            startTime: Date(timeIntervalSince1970: TimeInterval(bsd.pbi_start_tvsec)),
            executablePath: executablePath(pid: pid),
            arguments: arguments(pid: pid),
            workingDirectory: workingDirectory(pid: pid)
        )
    }

    public func isAlive(pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    // MARK: - Individual lookups

    func bsdInfo(pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let written = withUnsafeMutablePointer(to: &info) {
            proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, $0, size)
        }
        return written == size ? info : nil
    }

    public func executablePath(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return Self.string(fromNulTerminated: buffer)
    }

    /// Working directory. Fails for hardened-runtime processes, which is expected.
    public func workingDirectory(pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        let written = withUnsafeMutablePointer(to: &info) {
            proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, $0, size)
        }
        guard written == size else { return nil }
        return withUnsafePointer(to: &info.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
    }

    /// Full argv, read the same way `ps` reads it.
    public func arguments(pid: pid_t) -> [String] {
        guard let raw = procArgs(pid: pid) else { return [] }
        return Self.parseProcArgs(raw)
    }

    private func procArgs(pid: pid_t) -> [UInt8]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }

        var buffer = [UInt8](repeating: 0, count: size)
        let status = buffer.withUnsafeMutableBytes { pointer -> Int32 in
            sysctl(&mib, 3, pointer.baseAddress, &size, nil, 0)
        }
        guard status == 0 else { return nil }
        return Array(buffer.prefix(size))
    }

    /// Decodes a C buffer up to its first NUL.
    static func string(fromNulTerminated buffer: [CChar]) -> String? {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        guard !bytes.isEmpty else { return nil }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// `KERN_PROCARGS2` layout: `Int32 argc`, the executable path, alignment NULs,
    /// then `argc` NUL-terminated arguments, then the environment.
    static func parseProcArgs(_ buffer: [UInt8]) -> [String] {
        let headerSize = MemoryLayout<Int32>.size
        guard buffer.count > headerSize else { return [] }

        let argc = buffer.prefix(headerSize).withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard argc > 0 else { return [] }

        var index = headerSize
        // Skip the executable path.
        while index < buffer.count, buffer[index] != 0 { index += 1 }
        // Skip the alignment NULs that follow it.
        while index < buffer.count, buffer[index] == 0 { index += 1 }

        var arguments: [String] = []
        var current: [UInt8] = []
        while index < buffer.count, arguments.count < Int(argc) {
            let byte = buffer[index]
            if byte == 0 {
                arguments.append(String(decoding: current, as: UTF8.self))
                current.removeAll(keepingCapacity: true)
            } else {
                current.append(byte)
            }
            index += 1
        }
        if arguments.count < Int(argc), !current.isEmpty {
            arguments.append(String(decoding: current, as: UTF8.self))
        }
        return arguments
    }
}
