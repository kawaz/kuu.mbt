import Foundation

/// kuu WASM bridge via bun subprocess.
/// Sends JSON schema+args to kuu_parse, receives parsed result.
struct KuuBridge {
    let bridgePath: String

    init() {
        let execDir = URL(fileURLWithPath: CommandLine.arguments[0])
            .deletingLastPathComponent().path
        let candidates = [
            "\(execDir)/../wasm/bridge.mjs",
            "\(execDir)/../../wasm/bridge.mjs",
            "wasm/bridge.mjs",
        ]
        bridgePath = candidates.first { FileManager.default.fileExists(atPath: $0) }
            ?? "wasm/bridge.mjs"
    }

    func parse(schema: [String: Any], args: [String]) throws -> ParseResult {
        var input = schema
        input["args"] = args
        let jsonData = try JSONSerialization.data(withJSONObject: input)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["bun", "run", bridgePath]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        // Write stdin asynchronously to avoid deadlock when schema exceeds pipe buffer
        DispatchQueue.global().async {
            stdinPipe.fileHandleForWriting.write(jsonString.data(using: .utf8)!)
            stdinPipe.fileHandleForWriting.closeFile()
        }

        // Read stdout/stderr BEFORE waitUntilExit() to avoid deadlock
        let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        process.waitUntilExit()

        let output = String(data: outputData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            let errOutput = String(data: errData, encoding: .utf8) ?? ""
            throw KuuError.bridgeFailed(status: process.terminationStatus, stderr: errOutput)
        }

        guard let resultData = output.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: resultData) as? [String: Any] else {
            throw KuuError.invalidJSON(output)
        }

        return ParseResult(json: json)
    }
}

enum KuuError: Error, CustomStringConvertible {
    case bridgeFailed(status: Int32, stderr: String)
    case invalidJSON(String)

    var description: String {
        switch self {
        case .bridgeFailed(let status, let stderr):
            "kuu bridge failed (exit \(status)): \(stderr)"
        case .invalidJSON(let raw):
            "invalid JSON from kuu bridge: \(raw)"
        }
    }
}

/// Parsed result from kuu.
struct ParseResult {
    let ok: Bool
    let values: [String: Any]
    let command: CommandResult?
    let error: String?
    let help: String?
    let helpRequested: Bool

    init(json: [String: Any]) {
        self.ok = json["ok"] as? Bool ?? false
        self.values = json["values"] as? [String: Any] ?? [:]
        self.error = json["error"] as? String
        self.help = json["help"] as? String
        self.helpRequested = json["help_requested"] as? Bool ?? false
        if let cmd = json["command"] as? [String: Any] {
            self.command = CommandResult(json: cmd)
        } else {
            self.command = nil
        }
    }

    func string(_ key: String) -> String? { values[key] as? String }
    func bool(_ key: String) -> Bool { values[key] as? Bool ?? false }
    func int(_ key: String) -> Int? { values[key] as? Int }
    func strings(_ key: String) -> [String] { values[key] as? [String] ?? [] }
}

/// Subcommand result (class due to recursive structure).
/// @unchecked Sendable rationale: all properties are `let` and values
/// originate from JSONSerialization (only value-semantic Foundation types).
final class CommandResult: @unchecked Sendable {
    let name: String
    let values: [String: Any]
    let command: CommandResult?

    init(json: [String: Any]) {
        self.name = json["name"] as? String ?? ""
        self.values = json["values"] as? [String: Any] ?? [:]
        if let sub = json["command"] as? [String: Any] {
            self.command = CommandResult(json: sub)
        } else {
            self.command = nil
        }
    }

    func string(_ key: String) -> String? { values[key] as? String }
    func bool(_ key: String) -> Bool { values[key] as? Bool ?? false }
    func int(_ key: String) -> Int? { values[key] as? Int }
    func strings(_ key: String) -> [String] { values[key] as? [String] ?? [] }
}
