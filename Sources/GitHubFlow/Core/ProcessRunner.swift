import Foundation

/// The result of running a child process to completion.
struct CommandResult: Sendable {
    var stdout: String
    var stderr: String
    var exitCode: Int32

    var succeeded: Bool { exitCode == 0 }

    var stdoutTrimmed: String {
        stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var stderrTrimmed: String {
        stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Combined, human readable failure text.
    var failureMessage: String {
        let stderr = stderrTrimmed
        if !stderr.isEmpty { return stderr }
        let stdout = stdoutTrimmed
        return stdout.isEmpty ? "git exited with code \(exitCode)" : stdout
    }
}

enum ProcessRunner {
    /// Runs an executable and collects stdout/stderr without blocking a cooperative thread.
    static func run(
        executable: URL,
        arguments: [String],
        workingDirectory: URL? = nil,
        environment extraEnvironment: [String: String] = [:],
        standardInput: String? = nil
    ) async throws -> CommandResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }

        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_ASKPASS"] = "/usr/bin/true"
        environment["LC_ALL"] = "en_US.UTF-8"
        environment["LANG"] = "en_US.UTF-8"
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        environment["GIT_MERGE_AUTOEDIT"] = "no"
        for (key, value) in extraEnvironment {
            environment[key] = value
        }
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = stdinPipe

        // Set up the termination handler *before* launching so a fast-exiting
        // process can never miss it.
        let exitBox = ExitStatusBox()
        process.terminationHandler = { finished in
            exitBox.finish(finished.terminationStatus)
        }

        do {
            try process.run()
        } catch {
            throw GitError.launchFailed(error.localizedDescription)
        }

        if let standardInput {
            try? stdinPipe.fileHandleForWriting.write(contentsOf: Data(standardInput.utf8))
        }
        try? stdinPipe.fileHandleForWriting.close()

        async let stdoutData = readAll(stdoutPipe.fileHandleForReading)
        async let stderrData = readAll(stderrPipe.fileHandleForReading)

        let status = await exitBox.waitForExit()
        let (outData, errData) = try await (stdoutData, stderrData)

        return CommandResult(
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self),
            exitCode: status
        )
    }

    private static func readAll(_ handle: FileHandle) async throws -> Data {
        let box = UncheckedSendableBox(handle)
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let data = try box.value.readToEnd() ?? Data()
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

/// A tiny `@unchecked Sendable` wrapper used to move non-Sendable
/// reference types (like `FileHandle`) across isolation domains.
final class UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}

/// Bridges `Process`'s termination handler to an `async` continuation while
/// remaining safe if the process finishes before the continuation is installed.
final class ExitStatusBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Int32, Never>?
    private var storedStatus: Int32?

    func finish(_ status: Int32) {
        lock.lock()
        let pending = continuation
        if pending != nil {
            continuation = nil
        } else {
            storedStatus = status
        }
        lock.unlock()

        pending?.resume(returning: status)
    }

    func waitForExit() async -> Int32 {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let status = storedStatus {
                storedStatus = nil
                lock.unlock()
                continuation.resume(returning: status)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }
}
