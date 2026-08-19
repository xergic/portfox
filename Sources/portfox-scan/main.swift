import Foundation
import PortFoxKit

/// Development driver for the exact pipeline the app runs. Lets detection be
/// built and verified without launching a GUI.
struct CLI {
    enum Mode {
        case raw
        case services
        case json
        case diagnose
    }

    static func run() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let showAll = arguments.contains("--all")

        if arguments.contains("--help") || arguments.contains("-h") {
            printUsage()
            return
        }

        let mode: Mode
        if arguments.contains("--raw") {
            mode = .raw
        } else if arguments.contains("--json") {
            mode = .json
        } else if arguments.contains("--diagnose") {
            mode = .diagnose
        } else {
            mode = .services
        }

        do {
            switch mode {
            case .raw:
                try printRaw()
            case .diagnose:
                try printDiagnosis()
            case .services, .json:
                let repository = ServiceRepository()
                let result = try await repository.refresh(
                    options: ScanOptions(showAllListeners: showAll)
                )
                if mode == .json {
                    printJSON(result)
                } else {
                    printServices(result)
                }
            }
        } catch {
            FileHandle.standardError.write(Data("portfox-scan failed: \(error)\n".utf8))
            exit(1)
        }
    }

    static func printUsage() {
        print("""
        portfox-scan — resolve local development services

        Usage: portfox-scan [options]

          (no options)  grouped service list, the same view the popover shows
          --raw         every listener with pid, port, executable, argv and cwd
          --json        machine readable service list
          --all         include listeners classified as system noise
          --diagnose    explain how each listener was resolved and classified
        """)
    }

    static func printRaw() throws {
        let sockets = try ListenerScanner().scan()
        let inspector = ProcessInspector()
        var seen: Set<pid_t> = []

        print("\(sockets.count) listeners\n")
        for socket in sockets.sorted(by: { $0.port < $1.port }) {
            let snapshot = inspector.snapshot(pid: socket.pid)
            let marker = seen.insert(socket.pid).inserted ? " " : "+"
            print("\(marker) :\(socket.port)\t\(socket.host)\tpid \(socket.pid)\tppid \(snapshot?.parentPID ?? 0)")
            print("\texe  \(snapshot?.executablePath ?? "-")")
            print("\tcwd  \(snapshot?.workingDirectory ?? "-")")
            print("\targv \(snapshot?.command ?? "-")")
        }
    }

    static func printDiagnosis() throws {
        let sockets = try ListenerScanner().scan()
        let inspector = ProcessInspector()
        let snapshots = inspector.processSkeleton()
        let lightweightTree = ProcessTree(processes: snapshots)
        let listenerPIDs = Set(sockets.map(\.pid))

        print("sockets            \(sockets.count)")
        print("listener pids      \(listenerPIDs.count)")
        print("pids on machine    \(snapshots.count)")
        print("listeners missing  \(listenerPIDs.filter { lightweightTree.process($0) == nil }.count)")

        var byRepresentative: [pid_t: [Int]] = [:]
        for socket in sockets {
            let representative = ServiceRepository.representative(
                for: socket.pid, listenerPIDs: listenerPIDs, tree: lightweightTree
            )
            byRepresentative[representative, default: []].append(socket.port)
        }
        print("representatives    \(byRepresentative.count)\n")

        for (representative, ports) in byRepresentative.sorted(by: { $0.value.min()! < $1.value.min()! }) {
            let snapshot = inspector.snapshot(pid: representative)
            let name = snapshot?.executableName ?? "?"
            print("pid \(representative)\t\(name)\tports \(ports.sorted().map(String.init).joined(separator: ", "))")
        }
    }

    static func printServices(_ result: ScanResult) {
        print("\(result.services.count) services from \(result.allSockets.count) listeners")
        if !result.hidden.isEmpty { print("\(result.hidden.count) hidden as system noise") }
        print("")

        for group in result.groups {
            print("▸ \(group.project.name)  \(group.project.displayPath)")
            for service in group.services { printService(service, indent: "    ") }
            print("")
        }

        if !result.standalone.isEmpty {
            print("▸ INFRASTRUCTURE & DAEMONS")
            for service in result.standalone { printService(service, indent: "    ") }
            print("")
        }

        let ungrouped = result.services.filter { service in
            !result.groups.contains { $0.services.contains(where: { $0.id == service.id }) }
                && !result.standalone.contains(where: { $0.id == service.id })
        }
        if !ungrouped.isEmpty {
            print("▸ UNGROUPED")
            for service in ungrouped { printService(service, indent: "    ") }
        }
    }

    static func printService(_ service: RunningService, indent: String) {
        let confidence = Int((service.detection.confidence * 100).rounded())
        let subtitle = service.subtitle.map { " · \($0)" } ?? ""
        let extra = service.secondaryPorts.isEmpty ? "" : "  (+\(service.secondaryPorts.map(String.init).joined(separator: ", ")))"
        print("\(indent):\(service.port)\t\(service.displayName) \(confidence)%\(subtitle)\(extra)")
        print("\(indent)\tpid \(service.listenerProcess.pid) · stop \(service.rootProcess.pid) · \(service.classification.rawValue)")
    }

    static func printJSON(_ result: ScanResult) {
        let payload = result.services.map { service in
            [
                "port": String(service.port),
                "type": service.type.rawValue,
                "name": service.displayName,
                "confidence": String(format: "%.2f", service.detection.confidence),
                "pid": String(service.listenerProcess.pid),
                "stopPID": String(service.rootProcess.pid),
                "project": service.project?.name ?? "",
                "projectRoot": service.project?.root.path ?? "",
                "subpath": service.subtitle ?? "",
                "class": service.classification.rawValue,
                "cwd": service.listenerProcess.workingDirectory ?? "",
                "command": service.listenerProcess.command
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }
        print(String(decoding: data, as: UTF8.self))
    }
}

await CLI.run()
