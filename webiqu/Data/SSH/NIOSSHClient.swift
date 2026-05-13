import Foundation
#if canImport(NIO) && canImport(NIOSSH)
import NIO
import NIOSSH
#endif

actor NIOSSHClient: SSHClient {
    private var isConnected = false
    private var configuration: SSHConnectionConfiguration?
    private var shellProcess: Process?
    private var shellInputHandle: FileHandle?
    private var bufferedChunks: [TerminalChunk] = []
    private var lastTransportError: String?
    private var streamContinuation: AsyncThrowingStream<TerminalChunk, Error>.Continuation?
    private var fileOperationUser: String?

    #if canImport(NIO) && canImport(NIOSSH)
    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    private var negotiatedAlgorithms = NIOSSHAvailableUserAuthenticationMethods()
    #endif

    init() {}

    func connect(configuration: SSHConnectionConfiguration) async throws {
        AppTrace.log("SSH", "connect() called host=\(configuration.host):\(configuration.port) user=\(configuration.username)")
        guard !isConnected else {
            AppTrace.log("SSH", "connect() aborted: already connected")
            throw SSHClientError.alreadyConnected
        }
        guard !configuration.host.isEmpty else {
            AppTrace.log("SSH", "connect() aborted: empty host")
            throw SSHClientError.invalidHost
        }
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/ssh") else {
            AppTrace.log("SSH", "connect() aborted: /usr/bin/ssh not executable")
            throw SSHClientError.unsupported("/usr/bin/ssh is not available on this system.")
        }

        self.configuration = configuration
        self.lastTransportError = nil

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = try shellArguments(for: configuration)
        AppTrace.log("SSH", "Launching shell process args=\(process.arguments?.joined(separator: " ") ?? "")")

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self else { return }
            Task {
                await self.logDataPreview(data, stream: "stdout")
                await self.emit(data: data, stream: .stdout)
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self else { return }
            Task {
                await self.logDataPreview(data, stream: "stderr")
                await self.emit(data: data, stream: .stderr)
            }
        }

        process.terminationHandler = { [weak self] terminated in
            guard let self else { return }
            Task {
                AppTrace.log("SSH", "shell process terminated status=\(terminated.terminationStatus)")
                await self.handleProcessExit(status: terminated.terminationStatus)
            }
        }

        do {
            try process.run()
            AppTrace.log("SSH", "shell process started pid=\(process.processIdentifier)")
        } catch {
            AppTrace.log("SSH", "shell process start failed: \(error.localizedDescription)")
            throw SSHClientError.unsupported("Failed to start SSH process: \(error.localizedDescription)")
        }

        shellProcess = process
        shellInputHandle = inputPipe.fileHandleForWriting

        #if canImport(NIO) && canImport(NIOSSH)
        eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        _ = negotiatedAlgorithms
        #endif

        isConnected = true
        AppTrace.log("SSH", "connect() finished isConnected=true")
    }

    func disconnect() async {
        AppTrace.log("SSH", "disconnect() called")
        isConnected = false
        shellInputHandle?.closeFile()
        shellInputHandle = nil

        if let process = shellProcess, process.isRunning {
            AppTrace.log("SSH", "disconnect() terminating running shell pid=\(process.processIdentifier)")
            process.terminate()
        }
        shellProcess = nil

        streamContinuation?.yield(TerminalChunk(stream: .stdout, text: "Disconnected.\n"))
        finishStream()
        AppTrace.log("SSH", "disconnect() completed")
        fileOperationUser = nil

        #if canImport(NIO) && canImport(NIOSSH)
        try? eventLoopGroup?.syncShutdownGracefully()
        eventLoopGroup = nil
        #endif
    }

    func setFileOperationUser(_ username: String?) async throws {
        let trimmed = username?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            guard isSafeRemoteUsername(trimmed) else {
                throw SSHClientError.unsupported("Invalid username for file operations.")
            }
            fileOperationUser = trimmed
            AppTrace.log("SSH", "fileOperationUser set to \(trimmed)")
        } else {
            fileOperationUser = nil
            AppTrace.log("SSH", "fileOperationUser reset to session user")
        }
    }

    func startInteractiveShell(columns: Int, rows: Int) async throws {
        guard isConnected else {
            AppTrace.log("SSH", "startInteractiveShell blocked: not connected")
            if let lastTransportError {
                throw SSHClientError.unsupported(lastTransportError)
            }
            throw SSHClientError.notConnected
        }

        AppTrace.log("SSH", "startInteractiveShell columns=\(columns) rows=\(rows)")
        emit(chunk: TerminalChunk(stream: .stdout, text: "SSH session started (\(columns)x\(rows)).\n"))
    }

    func sendToShell(_ input: String) async throws {
        guard isConnected else {
            AppTrace.log("SSH", "sendToShell blocked: not connected")
            if let lastTransportError {
                throw SSHClientError.unsupported(lastTransportError)
            }
            throw SSHClientError.notConnected
        }

        guard let inputHandle = shellInputHandle else {
            AppTrace.log("SSH", "sendToShell blocked: input handle nil")
            if let lastTransportError {
                throw SSHClientError.unsupported(lastTransportError)
            }
            throw SSHClientError.notConnected
        }

        guard let data = input.data(using: .utf8) else {
            throw SSHClientError.unsupported("Unable to encode terminal input.")
        }

        try inputHandle.write(contentsOf: data)
        AppTrace.log("SSH", "sendToShell wrote bytes=\(data.count)")
    }

    func resizeShell(columns: Int, rows: Int) async throws {
        guard isConnected else {
            throw SSHClientError.notConnected
        }

        emit(chunk: TerminalChunk(stream: .stdout, text: "Terminal resize requested: \(columns)x\(rows).\n"))
    }

    func execute(_ command: String) async throws -> String {
        guard isConnected else {
            AppTrace.log("SSH", "execute blocked: not connected command=\(command)")
            if let lastTransportError {
                throw SSHClientError.unsupported(lastTransportError)
            }
            throw SSHClientError.notConnected
        }

        AppTrace.log("SSH", "execute command=\(command)")
        let output = try await runRemoteCommand(command)
        return output.isEmpty ? "Command completed." : output
    }

    func terminalStream() async -> AsyncThrowingStream<TerminalChunk, Error> {
        AsyncThrowingStream { continuation in
            streamContinuation = continuation
            AppTrace.log("SSH", "terminalStream attached bufferedChunks=\(bufferedChunks.count)")
            if !bufferedChunks.isEmpty {
                for chunk in bufferedChunks {
                    continuation.yield(chunk)
                }
                bufferedChunks.removeAll(keepingCapacity: true)
            }

            continuation.yield(TerminalChunk(stream: .stdout, text: "Connected.\n"))
        }
    }

    func listDirectory(at path: String) async throws -> [SFTPFileItem] {
        guard isConnected else {
            AppTrace.log("SSH", "listDirectory blocked: not connected path=\(path)")
            if let lastTransportError {
                throw SSHClientError.unsupported(lastTransportError)
            }
            throw SSHClientError.notConnected
        }

        AppTrace.log("SSH", "listDirectory path=\(path)")
        let safePath = shellEscaped(path)
        let command = wrapFileCommand("LC_ALL=C ls -la \(safePath)")
        let output = try await runRemoteCommand(command)
        let parsed = parseLSOutput(output, basePath: path)
        AppTrace.log("SSH", "listDirectory parsed items=\(parsed.count) path=\(path)")
        return parsed
    }

    func upload(localURL: URL, remotePath: String) async throws {
        guard isConnected else {
            if let lastTransportError {
                throw SSHClientError.unsupported(lastTransportError)
            }
            throw SSHClientError.notConnected
        }

        guard let configuration else {
            throw SSHClientError.notConnected
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: localURL.path, isDirectory: &isDirectory) else {
            throw SSHClientError.unsupported("Local upload path does not exist.")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/scp")
        process.arguments = try scpUploadArguments(
            for: configuration,
            localPath: localURL.path,
            remotePath: remotePath,
            recursive: isDirectory.boolValue
        )
        AppTrace.log("SSH", "upload launch args=\(process.arguments?.joined(separator: " ") ?? "")")

        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw SSHClientError.unsupported("Failed to start scp: \(error.localizedDescription)")
        }

        process.waitUntilExit()
        let terminationStatus = process.terminationStatus
        if terminationStatus != 0 {
            let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let err = String(data: errData, encoding: .utf8) ?? ""
            throw SSHClientError.unsupported(
                "Upload failed: \(err.trimmingCharacters(in: .whitespacesAndNewlines))"
            )
        }

        AppTrace.log("SSH", "upload success local=\(localURL.path) remote=\(remotePath)")
    }

    func renameItem(at path: String, to newPath: String) async throws {
        guard isConnected else {
            if let lastTransportError {
                throw SSHClientError.unsupported(lastTransportError)
            }
            throw SSHClientError.notConnected
        }

        let source = shellEscaped(path)
        let target = shellEscaped(newPath)
        _ = try await runRemoteCommand(wrapFileCommand("mv -- \(source) \(target)"))
        AppTrace.log("SSH", "renameItem success old=\(path) new=\(newPath)")
    }

    func deleteItem(at path: String, isDirectory: Bool) async throws {
        guard isConnected else {
            if let lastTransportError {
                throw SSHClientError.unsupported(lastTransportError)
            }
            throw SSHClientError.notConnected
        }

        let escaped = shellEscaped(path)
        if isDirectory {
            _ = try await runRemoteCommand(wrapFileCommand("rm -rf -- \(escaped)"))
        } else {
            _ = try await runRemoteCommand(wrapFileCommand("rm -f -- \(escaped)"))
        }
        AppTrace.log("SSH", "deleteItem success path=\(path) directory=\(isDirectory)")
    }

    func createDirectory(at path: String) async throws {
        guard isConnected else {
            if let lastTransportError {
                throw SSHClientError.unsupported(lastTransportError)
            }
            throw SSHClientError.notConnected
        }

        let escaped = shellEscaped(path)
        _ = try await runRemoteCommand(wrapFileCommand("mkdir -p -- \(escaped)"))
        AppTrace.log("SSH", "createDirectory success path=\(path)")
    }

    func createFile(at path: String) async throws {
        guard isConnected else {
            if let lastTransportError {
                throw SSHClientError.unsupported(lastTransportError)
            }
            throw SSHClientError.notConnected
        }

        let escaped = shellEscaped(path)
        _ = try await runRemoteCommand(wrapFileCommand(": > \(escaped)"))
        AppTrace.log("SSH", "createFile success path=\(path)")
    }

    func readTextFile(at path: String) async throws -> String {
        guard isConnected else {
            if let lastTransportError {
                throw SSHClientError.unsupported(lastTransportError)
            }
            throw SSHClientError.notConnected
        }

        let escaped = shellEscaped(path)
        let output = try await runRemoteCommand(wrapFileCommand("base64 -- \(escaped)"))
        let normalized = output.replacingOccurrences(of: "\n", with: "")

        guard let data = Data(base64Encoded: normalized, options: .ignoreUnknownCharacters) else {
            throw SSHClientError.unsupported("File could not be decoded as text.")
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw SSHClientError.unsupported("File is not UTF-8 text.")
        }

        AppTrace.log("SSH", "readTextFile success path=\(path) bytes=\(data.count)")
        return text
    }

    func writeTextFile(at path: String, content: String) async throws {
        guard isConnected else {
            if let lastTransportError {
                throw SSHClientError.unsupported(lastTransportError)
            }
            throw SSHClientError.notConnected
        }

        guard let data = content.data(using: .utf8) else {
            throw SSHClientError.unsupported("Unable to encode text content.")
        }

        let base64 = data.base64EncodedString()
        let escapedContent = shellEscaped(base64)
        let escapedPath = shellEscaped(path)
        _ = try await runRemoteCommand(wrapFileCommand("printf %s \(escapedContent) | base64 -d > \(escapedPath)"))
        AppTrace.log("SSH", "writeTextFile success path=\(path) bytes=\(data.count)")
    }

    func download(
        remotePath: String,
        localURL: URL,
        expectedSize: Int64?,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard isConnected else {
            if let lastTransportError {
                throw SSHClientError.unsupported(lastTransportError)
            }
            throw SSHClientError.notConnected
        }

        guard let configuration else {
            throw SSHClientError.notConnected
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/scp")
        process.arguments = try scpDownloadArguments(
            for: configuration,
            remotePath: remotePath,
            localPath: localURL.path
        )
        AppTrace.log("SSH", "download launch args=\(process.arguments?.joined(separator: " ") ?? "")")

        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw SSHClientError.unsupported("Failed to start scp: \(error.localizedDescription)")
        }

        progress(0)

        while process.isRunning {
            if let expectedSize, expectedSize > 0 {
                let downloaded = fileSize(at: localURL)
                let fraction = min(0.99, max(0, Double(downloaded) / Double(expectedSize)))
                progress(fraction)
            }
            try await Task.sleep(nanoseconds: 150_000_000)
        }

        process.waitUntilExit()
        let terminationStatus = process.terminationStatus

        if terminationStatus != 0 {
            let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let err = String(data: errData, encoding: .utf8) ?? ""
            throw SSHClientError.unsupported(
                "Download failed: \(err.trimmingCharacters(in: .whitespacesAndNewlines))"
            )
        }

        progress(1.0)
        AppTrace.log("SSH", "download success remote=\(remotePath) local=\(localURL.path)")
    }

    private func shellArguments(for configuration: SSHConnectionConfiguration) throws -> [String] {
        var arguments: [String] = [
            "-tt",
            "-p", "\(configuration.port)",
            "-o", "ConnectTimeout=10",
            "-o", "ServerAliveInterval=30",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "UserKnownHostsFile=\(try knownHostsFilePath())"
        ]

        switch configuration.authentication {
        case .sshAgent:
            arguments.append(contentsOf: [
                "-o", "IdentityFile=none",
                "-o", "IdentitiesOnly=yes"
            ])
        case .privateKey(let privateKeyPath, _):
            arguments.append(contentsOf: [
                "-i", privateKeyPath,
                "-o", "IdentitiesOnly=yes"
            ])
        }

        arguments.append("\(configuration.username)@\(configuration.host)")
        return arguments
    }

    private func remoteCommandArguments(for configuration: SSHConnectionConfiguration, command: String) throws -> [String] {
        var arguments: [String] = [
            "-p", "\(configuration.port)",
            "-o", "ConnectTimeout=10",
            "-o", "BatchMode=yes",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "UserKnownHostsFile=\(try knownHostsFilePath())"
        ]

        switch configuration.authentication {
        case .sshAgent:
            arguments.append(contentsOf: [
                "-o", "IdentityFile=none",
                "-o", "IdentitiesOnly=yes"
            ])
        case .privateKey(let privateKeyPath, _):
            arguments.append(contentsOf: [
                "-i", privateKeyPath,
                "-o", "IdentitiesOnly=yes"
            ])
        }

        arguments.append(contentsOf: [
            "\(configuration.username)@\(configuration.host)",
            command
        ])
        return arguments
    }

    private func scpDownloadArguments(
        for configuration: SSHConnectionConfiguration,
        remotePath: String,
        localPath: String
    ) throws -> [String] {
        var arguments: [String] = [
            "-P", "\(configuration.port)",
            "-o", "ConnectTimeout=10",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "UserKnownHostsFile=\(try knownHostsFilePath())"
        ]

        switch configuration.authentication {
        case .sshAgent:
            arguments.append(contentsOf: [
                "-o", "IdentityFile=none",
                "-o", "IdentitiesOnly=yes"
            ])
        case .privateKey(let privateKeyPath, _):
            arguments.append(contentsOf: [
                "-i", privateKeyPath,
                "-o", "IdentitiesOnly=yes"
            ])
        }

        arguments.append(contentsOf: [
            "\(configuration.username)@\(configuration.host):\(remotePath)",
            localPath
        ])

        return arguments
    }

    private func scpUploadArguments(
        for configuration: SSHConnectionConfiguration,
        localPath: String,
        remotePath: String,
        recursive: Bool
    ) throws -> [String] {
        var arguments: [String] = [
            "-P", "\(configuration.port)",
            "-o", "ConnectTimeout=10",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "UserKnownHostsFile=\(try knownHostsFilePath())"
        ]

        if recursive {
            arguments.append("-r")
        }

        switch configuration.authentication {
        case .sshAgent:
            arguments.append(contentsOf: [
                "-o", "IdentityFile=none",
                "-o", "IdentitiesOnly=yes"
            ])
        case .privateKey(let privateKeyPath, _):
            arguments.append(contentsOf: [
                "-i", privateKeyPath,
                "-o", "IdentitiesOnly=yes"
            ])
        }

        arguments.append(contentsOf: [
            localPath,
            "\(configuration.username)@\(configuration.host):\(remotePath)"
        ])

        return arguments
    }

    private func runRemoteCommand(_ command: String) async throws -> String {
        guard let configuration else {
            AppTrace.log("SSH", "runRemoteCommand blocked: missing configuration")
            if let lastTransportError {
                throw SSHClientError.unsupported(lastTransportError)
            }
            throw SSHClientError.notConnected
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = try remoteCommandArguments(for: configuration, command: command)
        AppTrace.log("SSH", "runRemoteCommand launch args=\(process.arguments?.joined(separator: " ") ?? "")")

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            AppTrace.log("SSH", "runRemoteCommand started pid=\(process.processIdentifier)")
        } catch {
            AppTrace.log("SSH", "runRemoteCommand start failed: \(error.localizedDescription)")
            throw SSHClientError.unsupported("Failed to execute remote command: \(error.localizedDescription)")
        }

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                let outData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()

                let out = String(data: outData, encoding: .utf8) ?? ""
                let err = String(data: errData, encoding: .utf8) ?? ""
                AppTrace.log("SSH", "runRemoteCommand finished status=\(process.terminationStatus) outBytes=\(outData.count) errBytes=\(errData.count)")

                if process.terminationStatus == 0 {
                    continuation.resume(returning: out.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    let message = err.isEmpty ? out : err
                    AppTrace.log("SSH", "runRemoteCommand failed message=\(message.trimmingCharacters(in: .whitespacesAndNewlines))")
                    continuation.resume(
                        throwing: SSHClientError.unsupported(
                            "Remote command failed: \(message.trimmingCharacters(in: .whitespacesAndNewlines))"
                        )
                    )
                }
            }
        }
    }

    private func emit(data: Data, stream: TerminalChunk.Stream) {
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            return
        }
        emit(chunk: TerminalChunk(stream: stream, text: text))
    }

    private func emit(chunk: TerminalChunk) {
        if let streamContinuation {
            streamContinuation.yield(chunk)
        } else {
            bufferedChunks.append(chunk)
        }
    }

    private func finishStream() {
        AppTrace.log("SSH", "finishStream called")
        streamContinuation?.finish()
        streamContinuation = nil
    }

    private func handleProcessExit(status: Int32) {
        AppTrace.log("SSH", "handleProcessExit status=\(status)")
        isConnected = false
        shellProcess = nil
        shellInputHandle = nil

        if status == 0 {
            emit(chunk: TerminalChunk(stream: .stdout, text: "SSH session ended.\n"))
            lastTransportError = nil
        } else {
            let fromStderr = bufferedChunks.reversed().first(where: { chunk in
                if case .stderr = chunk.stream {
                    return true
                }
                return false
            })?.text
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let reason = (fromStderr?.isEmpty == false) ? fromStderr! : "SSH session closed with status \(status)."
            lastTransportError = reason
            emit(chunk: TerminalChunk(stream: .stderr, text: "SSH session closed with status \(status).\n"))
        }
        finishStream()
    }

    private func logDataPreview(_ data: Data, stream: String) {
        guard let text = String(data: data, encoding: .utf8) else {
            AppTrace.log("SSH", "\(stream) bytes=\(data.count) (non-utf8)")
            return
        }

        let normalized = text.replacingOccurrences(of: "\n", with: "\\n")
        let preview = normalized.count > 200 ? String(normalized.prefix(200)) + "..." : normalized
        AppTrace.log("SSH", "\(stream) bytes=\(data.count) preview=\(preview)")
    }

    private func shellEscaped(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func wrapFileCommand(_ command: String) -> String {
        guard let fileOperationUser, !fileOperationUser.isEmpty else {
            return command
        }

        let escapedUser = shellEscaped(fileOperationUser)
        let escapedCommand = shellEscaped(command)
        return "sudo -n -u \(escapedUser) -- sh -lc \(escapedCommand)"
    }

    private func isSafeRemoteUsername(_ username: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        return !username.isEmpty && username.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private func parseLSOutput(_ output: String, basePath: String) -> [SFTPFileItem] {
        let normalizedBase: String = {
            if basePath.isEmpty { return "/" }
            return basePath
        }()

        let lines = output.split(separator: "\n")
        var items: [SFTPFileItem] = []
        items.reserveCapacity(lines.count)

        for line in lines {
            if line.hasPrefix("total") {
                continue
            }

            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 9 else {
                continue
            }

            let mode = String(parts[0])
            let isDirectory = mode.first == "d"
            let size = Int64(parts[4]) ?? 0
            let modifiedAt = parseLSModifiedDate(month: String(parts[5]), day: String(parts[6]), timeOrYear: String(parts[7]))
            let name = parts[8...].joined(separator: " ")

            if name == "." || name == ".." {
                continue
            }

            let path = joinedRemotePath(base: normalizedBase, child: name)

            items.append(
                SFTPFileItem(
                    name: name,
                    path: path,
                    isDirectory: isDirectory,
                    size: size,
                    modifiedAt: modifiedAt
                )
            )
        }

        return items
    }

    private func joinedRemotePath(base: String, child: String) -> String {
        if base == "/" {
            return "/\(child)"
        }

        let sanitizedBase = base.hasSuffix("/") ? String(base.dropLast()) : base
        return "\(sanitizedBase)/\(child)"
    }

    private func parseLSModifiedDate(month: String, day: String, timeOrYear: String) -> Date? {
        let locale = Locale(identifier: "en_US_POSIX")

        if timeOrYear.contains(":") {
            let year = Calendar.current.component(.year, from: Date())
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.dateFormat = "MMM d yyyy HH:mm"
            return formatter.date(from: "\(month) \(day) \(year) \(timeOrYear)")
        }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "MMM d yyyy"
        return formatter.date(from: "\(month) \(day) \(timeOrYear)")
    }

    private func knownHostsFilePath() throws -> String {
        let fileManager = FileManager.default
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let sshDirectory = appSupport
            .appendingPathComponent("webiqu", isDirectory: true)
            .appendingPathComponent("ssh", isDirectory: true)

        try fileManager.createDirectory(at: sshDirectory, withIntermediateDirectories: true)
        let knownHostsURL = sshDirectory.appendingPathComponent("known_hosts", isDirectory: false)

        if !fileManager.fileExists(atPath: knownHostsURL.path) {
            fileManager.createFile(atPath: knownHostsURL.path, contents: Data())
        }

        return knownHostsURL.path
    }

    private func fileSize(at url: URL) -> Int64 {
        guard
            let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
            let size = values.fileSize
        else {
            return 0
        }
        return Int64(size)
    }
}
