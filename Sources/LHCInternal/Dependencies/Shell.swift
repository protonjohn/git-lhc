//
//  Shell.swift
//  
//
//  Created by John Biggs on 16.12.23.
//

import Foundation
import LHCInternalC
import System
import SwiftGit2

public protocol Shellish {
    func run(
        shebang: String,
        command: String,
        environment: [String: String],
        ttyEnvironmentVariable: String?,
        extraFileDescriptors: [Int32: FileHandle]
    ) throws -> AsyncStream<Result<Shell.Event, Error>>

    mutating func print(_ item: String, error: Bool)
}

public extension Shellish {
    func run(
        shebang: String? = nil,
        command: String,
        environment: [String: String] = Internal.processInfo.environment,
        ttyEnvironmentVariable: String? = nil,
        extraFileDescriptors: [Int32: FileHandle] = [:]
    ) throws -> AsyncStream<Result<Shell.Event, Error>> {
        return try run(
            shebang: shebang ?? Internal.processInfo.environment["SHELL"] ?? "/bin/sh -e",
            command: command,
            environment: environment,
            ttyEnvironmentVariable: ttyEnvironmentVariable,
            extraFileDescriptors: extraFileDescriptors
        )
    }
}

fileprivate func posix(_ result: @autoclosure () -> Int32, caller: StaticString = #function, line: Int = #line) throws {
    let result = result()
    guard result == 0 else {
        throw POSIXError(
            .init(rawValue: result) ?? .ELAST,
            userInfo: [NSDebugDescriptionErrorKey: "In \(caller) on line \(line)."]
        )
    }
}

@discardableResult
fileprivate func posixCheckErrnoIfNegative(
    _ result: @autoclosure () -> Int32,
    caller: StaticString = #function,
    line: Int = #line
) throws -> Int32 {
    let result = result()
    guard result >= 0 else {
        try posix(errno, caller: caller, line: line)
        return result
    }

    return result
}

@discardableResult
fileprivate func posixCheckErrnoIfNil<T>(
    _ result: @autoclosure () -> UnsafeMutablePointer<T>?,
    caller: StaticString = #function,
    line: Int = #line
) throws -> UnsafeMutablePointer<T>? {
    guard let result = result() else {
        try posix(errno, caller: caller, line: line)
        return nil
    }

    return result
}

/// A shell wrapper which spawns processes in their own PTY, forwarding data between our terminal and the PTY using
/// kevent and launching the process using posix_spawn.
public struct Shell: Shellish {
    /// Nil data represents EOF.
    public enum Event {
        case pid(Int32)
        case stdin(Data?)
        case stderr(Data?)
        case stdout(Data?)
        case termio(termios?)
        case exit(Int32)
    }

    public struct Exit: Error, RawRepresentable {
        public let rawValue: Int32

        public init(rawValue: Int32) {
            self.rawValue = rawValue
        }
    }

    struct PTY: Sendable {
        struct Mode: OptionSet, RawRepresentable {
            let rawValue: UInt

            static let echo: Self = .init(rawValue: UInt(ECHO))
            static let empty: Self = .init(rawValue: 0)
        }

        let main: FileHandle

        let secondaryPath: String
        let secondary: FileHandle

        init(attrs: termios? = nil) throws {
            let mainDescriptor = try posixCheckErrnoIfNegative(posix_openpt(O_RDWR))

            // Create a secondary ("replica") device and get its permissions set up.
            try posixCheckErrnoIfNegative(grantpt(mainDescriptor))
            try posixCheckErrnoIfNegative(unlockpt(mainDescriptor))

            let main = FileHandle(fileDescriptor: mainDescriptor)

            self.secondaryPath = try Self.secondaryPath(for: main)
            guard let secondary = FileHandle(forUpdatingAtPath: secondaryPath) else {
                throw POSIXError(.EINVAL)
            }

            // Set these descriptors to close if an exec occurs in the child process.
            try posixCheckErrnoIfNegative(fcntl(main.fileDescriptor, F_SETFD, FD_CLOEXEC))
            try posixCheckErrnoIfNegative(fcntl(secondary.fileDescriptor, F_SETFD, FD_CLOEXEC))

            // Get the window size of the current terminal we're in - if we're in one - and set the same in the PTY.
            do {
                var window = winsize()
                try posixCheckErrnoIfNegative(ioctl(FileHandle.standardInput.fileDescriptor, TIOCGWINSZ, &window))
                try posixCheckErrnoIfNegative(ioctl(main.fileDescriptor, TIOCSWINSZ, &window))
            } catch let error as POSIXError where error.code == .ENOTTY {
                // Ignore if not in a TTY
            }

            // Duplicate attributes from the main terminal
            _ = try Self.setAttrs(fileHandle: secondary, term: attrs)

            self.main = main
            self.secondary = secondary
        }

        static func secondaryPath(for fileHandle: FileHandle) throws -> String {
            let buflen = 4096
            var buf = Data(repeating: 0, count: buflen)

            _ = try buf.withUnsafeMutableBytes {
                try posixCheckErrnoIfNegative(ptsname_r(fileHandle.fileDescriptor, $0.baseAddress, buflen))
            }

            return String(data: buf, encoding: .utf8)!
        }

        static func getAttrs(fileHandle: FileHandle = .standardInput) throws -> termios {
            var term = termios()
            let descriptor = fileHandle.fileDescriptor
            try posixCheckErrnoIfNegative(tcgetattr(descriptor, &term))
            return term
        }

        static func setAttrs(
            fileHandle: FileHandle = .standardInput,
            set: Mode = .empty,
            unset: Mode = .empty,
            raw: Bool = false,
            term: termios? = nil
        ) throws -> termios? {
            do {
                var term = try term ?? getAttrs(fileHandle: fileHandle)

                if raw {
                    cfmakeraw(&term)
                }

                var flags = term.localModes
                flags.insert(set)
                flags.remove(unset)
                term.c_lflag = flags.rawValue

                try posixCheckErrnoIfNegative(tcsetattr(fileHandle.fileDescriptor, TCSAFLUSH, &term))

                return term
            } catch let error as POSIXError where error.code == .ENOTTY {
                return nil
            }
        }
    }

    struct Process: Sendable {
        var pid: pid_t = -1

        let executableURL: URL
        let arguments: [String]
        let environment: [String: String]

        let standardInput: FileHandle?
        let standardOutput: FileHandle?
        let standardError: FileHandle?
        let extraFileDescriptors: [Int32: FileHandle]

        init(
            executableURL: URL,
            arguments: [String],
            environment: [String: String] = Internal.processInfo.environment,
            standardInput: FileHandle? = nil,
            standardOutput: FileHandle? = nil,
            standardError: FileHandle? = nil,
            extraFileDescriptors: [Int32: FileHandle] = [:]
        ) {
            self.executableURL = executableURL
            self.arguments = arguments
            self.environment = environment
            self.standardInput = standardInput
            self.standardOutput = standardOutput
            self.standardError = standardError
            self.extraFileDescriptors = extraFileDescriptors
        }

        mutating func run() throws {
            self.pid = try Self.spawn(
                url: executableURL,
                arguments: arguments,
                environment: environment,
                stdin: standardInput,
                stdout: standardOutput,
                stderr: standardError,
                extraFileDescriptors: extraFileDescriptors
            )
        }

        /// Spawn a process using posix_spawn, making sure that its signals have been reset and that it's using stdin,
        /// stdout, and stderr based on the pipes we've given.
        private static func spawn(
            url: URL,
            arguments: [String],
            environment: [String: String],
            stdin: FileHandle?,
            stdout: FileHandle?,
            stderr: FileHandle?,
            extraFileDescriptors: [Int32: FileHandle]
        ) throws -> Int32 {
            var actions = posix_spawn_file_actions_t(bitPattern: 0)
            var attrs = posix_spawnattr_t(bitPattern: 0)

            try posix(posix_spawn_file_actions_init(&actions))
            try posix(posix_spawnattr_init(&attrs))

            var set = sigset_t()
            sigemptyset(&set)
            sigaddset(&set, SIGCHLD)
            sigaddset(&set, SIGPIPE)
            sigaddset(&set, SIGINT)

            try posix(posix_spawnattr_setflags(&attrs, Int16(POSIX_SPAWN_SETSIGDEF)))
            try posix(posix_spawnattr_setsigdefault(&attrs, &set))

            let (stdin, stdout, stderr) = (
                stdin?.fileDescriptor,
                stdout?.fileDescriptor,
                stderr?.fileDescriptor
            )

            if let stdin {
                try posix(posix_spawn_file_actions_adddup2(&actions, stdin, STDIN_FILENO))
            }
            if let stdout {
                try posix(posix_spawn_file_actions_adddup2(&actions, stdout, STDOUT_FILENO))
            }
            if let stderr {
                try posix(posix_spawn_file_actions_adddup2(&actions, stderr, STDERR_FILENO))
            }

            // We need to sort the elements, because it's possible that one of the remapped file descriptors is actually
            // open, in which case we don't want to overwrite it with another descriptor.
            let fdMap = extraFileDescriptors.sorted { lhs, rhs in
                lhs.key < rhs.key
            }

            for (descriptor, handle) in fdMap {
                try posix(posix_spawn_file_actions_adddup2(&actions, handle.fileDescriptor, descriptor))
                try posix(posix_spawn_file_actions_addclose(&actions, handle.fileDescriptor))
            }

            let path = url.path(percentEncoded: false)
            var arguments: [UnsafeMutablePointer<CChar>?] = ([path] + arguments).map { argument in
                var argument = argument
                return argument.withUTF8 {
                    $0.withMemoryRebound(to: Int8.self) { bufPtr in
                        let count = bufPtr.count + 1
                        let pointer = UnsafeMutablePointer<Int8>.allocate(capacity: count) // Account for nul character
                        pointer.initialize(from: bufPtr.baseAddress!, count: count)
                        return pointer
                    }
                }
            } + [nil]

            var environment: [UnsafeMutablePointer<CChar>?] = environment.map { keypair in
                let (key, value) = keypair
                var repr = "\(key)=\(value)"
                return repr.withUTF8 {
                    $0.withMemoryRebound(to: Int8.self) { bufPtr in
                        let count = bufPtr.count + 1
                        let pointer = UnsafeMutablePointer<Int8>.allocate(capacity: count)
                        pointer.initialize(from: bufPtr.baseAddress!, count: count)
                        return pointer
                    }
                }
            } + [nil]

            defer {
                posix_spawn_file_actions_destroy(&actions)
                posix_spawnattr_destroy(&attrs)

                for argument in arguments {
                    argument?.deallocate()
                }

                for variable in environment {
                    variable?.deallocate()
                }
            }

            var pid: pid_t = 0
            try posix(posix_spawnp(
                &pid,
                path,
                &actions,
                &attrs,
                &arguments,
                &environment
            ))

            return pid
        }
    }

    /**
     Create an event stream for a process based on its three optional i/o file descriptors and any SIGCHLD signals that
     we receive during the loop's execution.
     */
    private static func eventLoop(
        standardInput: FileHandle?,
        standardOutput: FileHandle?,
        standardError: FileHandle?,
        readyCallback: @escaping (() -> ())
    ) throws -> AsyncStream<Result<Event, Error>> {
        let kernelQueue = try FileHandle.forNewKernelQueue()
        let queueDescriptor = kernelQueue.fileDescriptor
        let oldHandler = signal(SIGCHLD, SIG_DFL)

        return AsyncStream { continuation in
            continuation.onTermination = { _ in
                try? kernelQueue.close()
            }

            Task {
                var fileHandles: [Int32: FileHandle] = [:]
                for fileHandle in [standardInput, standardOutput, standardError] where fileHandle != nil {
                    fileHandles[fileHandle!.fileDescriptor] = fileHandle
                }

                // Add 1 for the SIGCHLD handler.
                let total = fileHandles.count + 1
                var update: ContiguousArray<kevent64_s>? = .init(repeating: kevent64_s(), count: total)
                var events = update!

                // Set up the initial events array.
                for (index, descriptor) in fileHandles.keys.enumerated() {
                    update![index] = kevent64_s(
                        ident: UInt64(descriptor),
                        filter: Int16(EVFILT_READ),
                        flags: UInt16(EV_ADD),
                        fflags: 0,
                        data: 0,
                        udata: 0,
                        ext: (0, 0)
                    )
                }
                update![total - 1] = kevent64_s(
                    ident: UInt64(SIGCHLD),
                    filter: Int16(EVFILT_SIGNAL),
                    flags: UInt16(EV_ADD),
                    fflags: 0,
                    data: 0,
                    udata: 0,
                    ext: (0, 0)
                )

                let addUpdate = { (descriptor: Int32, filter: Int32, flags: Int32) in
                    let element = kevent64_s(
                        ident: UInt64(descriptor),
                        filter: Int16(filter),
                        flags: UInt16(flags),
                        fflags: 0,
                        data: 0,
                        udata: 0,
                        ext: (0, 0)
                    )

                    if update == nil {
                        update = [element]
                    } else {
                        update?.append(element)
                    }
                }

                let kevent: (
                    UnsafeMutableBufferPointer<kevent64_s>?,
                    Int,
                    UnsafeMutableBufferPointer<kevent64_s>?,
                    Int,
                    Bool
                ) -> Int32 = { (updates, updateCount, events, eventCount, poll) in
                    kevent64(
                        queueDescriptor,
                        updates?.baseAddress, Int32(updateCount),
                        events?.baseAddress, Int32(eventCount),
                        /* flags */ poll ? UInt32(KEVENT_FLAG_IMMEDIATE) : 0,
                        /* timeout */ nil
                    )
                }

                var exitCode: Int32?
                var first = true
                eventLoop: while true {
                    let result: Int32
                    let eventsCount = events.count
                    let updateCount = update?.count ?? 0
                    result = await withCheckedContinuation { continuation in
                        events.withUnsafeMutableBufferPointer { eventsPtr in
                            // kqueue saves what events we want to monitor, so we clear it to add updates to our event filters
                            // further down if we receive any errors on them.
                            if var update {
                                update.withUnsafeMutableBufferPointer { updatePtr in
                                    // Poll for the first time, so that we can add the events to monitor to the kqueue
                                    // and invoke the ready callback afterwards to let the listener know when they can
                                    // launch their process.
                                    continuation.resume(
                                        returning: kevent(
                                            updatePtr,
                                            updateCount,
                                            eventsPtr,
                                            eventsCount,
                                            /* poll */ first
                                        )
                                    )
                                }
                            } else {
                                continuation.resume(returning: kevent(nil, 0, eventsPtr, eventsCount, first))
                            }
                        }
                    }

                    guard result >= 0 else {
                        let error = POSIXError.global
                        guard error.code != .EINTR else { // try again
                            continue eventLoop
                        }

                        continuation.yield(.failure(error))
                        break eventLoop
                    }

                    update = nil

                    guard !first else {
                        // The initial poll should have returned immediately - it was just to establish monitoring of
                        // the events we're interested in. Invoke the ready callback now that we're ready to start
                        // processing the events.
                        readyCallback()
                        first = false
                        continue
                    }

                    for index in 0..<Int(result) {
                        let event = events[index]
                        switch Int32(event.filter) {
                        case EVFILT_READ:
                            let fileDescriptor = Int32(event.ident)
                            guard let fileHandle = fileHandles[fileDescriptor] else {
                                fatalError("Missing fileHandle for descriptor \(fileDescriptor)")
                            }

                            guard (event.flags & UInt16(EV_ERROR)) == 0 else {
                                let errorCode = POSIXErrorCode(rawValue: Int32(event.data)) ?? .ELAST
                                addUpdate(fileDescriptor, EVFILT_READ, EV_DELETE)
                                fileHandles.removeValue(forKey: fileDescriptor)
                                continuation.yield(.failure(POSIXError(errorCode)))
                                break eventLoop
                            }

                            do {
                                let data: Data?
                                if (event.flags & UInt16(EV_EOF)) != 0 {
                                    // We've reached EOF. Stop tracking events for this descriptor in the queue in the
                                    // next iteration, and remove the handle from the dictionary.
                                    addUpdate(fileDescriptor, EVFILT_READ, EV_DELETE)
                                    fileHandles.removeValue(forKey: fileDescriptor)
                                    data = try await fileHandle.read(upToCount: Int.max)
                                } else {
                                    data = try await fileHandle.read(upToCount: Int(event.data))
                                }

                                let output: ((Data?) -> Event)
                                let (ourInput, itsOutput, itsErrors) = (
                                    standardInput,
                                    standardOutput,
                                    standardError
                                )
                                switch fileHandle {
                                case ourInput:
                                    output = Event.stdin
                                case itsOutput:
                                    output = Event.stdout
                                case itsErrors:
                                    output = Event.stderr
                                default:
                                    fatalError("Unrecognized file descriptor \(fileHandle.fileDescriptor)")
                                }

                                continuation.yield(.success(output(data)))
                            } catch {
                                continuation.yield(.failure(error))
                                break eventLoop
                            }

                        case EVFILT_SIGNAL:
                            assert(event.ident == SIGCHLD)
                            guard (event.flags & UInt16(EV_ERROR)) == 0 else {
                                let errorCode = POSIXErrorCode(rawValue: Int32(event.data)) ?? .ELAST
                                continuation.yield(.failure(POSIXError(errorCode)))
                                return
                            }

                            while true {
                                var status: Int32 = 0
                                // We can't call waitpid from Foundation code apparently because it's racing with
                                // another loop somewhere. Does this remain true if we go back to using posix_spawn?
                                let result = waitpid(-1, &status, WNOHANG)
                                if result == 0 {
                                    break
                                } else if result < 0 {
                                    let error = POSIXError.global
                                    guard error.code != .EINTR else {
                                        continue
                                    }
                                    continuation.yield(.failure(error))
                                    break eventLoop
                                } else {
                                    if child_exited(status) {
                                        exitCode = child_exit_status(status)
                                        addUpdate(SIGCHLD, EVFILT_SIGNAL, EV_DELETE)
                                        continuation.yield(.success(.exit(status)))
                                        break
                                    }
                                }
                            }
                        default:
                            fatalError("Unexpected event.")
                        }
                    }

                    // If the process has exited and both stdout and stderr are closed, stop the loop.
                    if exitCode != nil {
                        if let standardInput, fileHandles.count == 1, fileHandles[standardInput.fileDescriptor] != nil {
                            break eventLoop
                        } else if fileHandles.isEmpty {
                            break eventLoop
                        }
                    }
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                try? kernelQueue.close()
                signal(SIGCHLD, oldHandler)
            }
        }
    }

    public func print(_ item: String, error: Bool) {
        dispatchPrecondition(condition: .notOnQueue(Self.queue))
        Self.queue.sync {
            printNoSync(item, error: error)
        }
    }

    private func printNoSync(_ item: String, error: Bool) {
        dispatchPrecondition(condition: .onQueue(Self.queue))
        let handle = error ? FileHandle.standardError : FileHandle.standardOutput

        var output: TextOutputStream = handle
        Swift.print(item, separator: "", terminator: "", to: &output)
    }

    static let queue = DispatchQueue(label: "shell i/o")

    public func run(
        shebang: String,
        command: String,
        environment: [String: String],
        ttyEnvironmentVariable: String?,
        extraFileDescriptors: [Int32: FileHandle]
    ) throws -> AsyncStream<Result<Event, Error>> {
        var environment = environment

        let term = try PTY.getAttrs()
        // Create a copy of the termios for the parent terminal, so we can clone it for the PTY we're about to create.
        let pty = try PTY(attrs: term)
        if let ttyEnvironmentVariable {
            environment[ttyEnvironmentVariable] = pty.secondaryPath
        }

        let stderrPipe = Pipe()
        let scriptPath = try Internal.fileManager.tempFile(contents: "\(command)\n".data(using: .utf8)).path(percentEncoded: false)

        let components = shebang.split(separator: " ")
        let executableURL = URL(filePath: String(components.first!))
        let arguments = components[1...].map(String.init)

        let launchGroup = DispatchGroup()
        launchGroup.enter()

        let eventLoop = try Self.eventLoop(
            standardInput: FileHandle.standardInput,
            standardOutput: pty.main,
            standardError: stderrPipe.fileHandleForReading,
            readyCallback: { launchGroup.leave() }
        )

        // Finally, disable echo for stdin, since we're already echoing on the PTY we've created.
        // We do this last because it's quite disruptive to leave on accidentally should any of the above things fail.
        _ = try PTY.setAttrs(unset: .echo, term: term)

        return AsyncStream { continuation in
            launchGroup.notify(queue: Shell.queue) {
                do {
                    var process = Process(
                        executableURL: executableURL,
                        arguments: arguments + [scriptPath],
                        environment: environment,
                        standardInput: pty.secondary,
                        standardOutput: pty.secondary,
                        standardError: stderrPipe.fileHandleForWriting,
                        extraFileDescriptors: extraFileDescriptors
                    )

                    try process.run()
                    continuation.yield(.success(.pid(process.pid)))

                    // We don't care about writing to these pipes in the parent process, so close it after the child is
                    // done spawning - ensuring it gets a copy of the file descriptor.
                    try stderrPipe.fileHandleForWriting.close()
                } catch {
                    continuation.yield(.failure(error))
                    continuation.finish()
                }
            }

            let loop = Task.detached { [pty, term] in
                // The result of this task returns whether the terminal is still in line buffer mode.
                var linebuf = true

                do {
                    var ptyAttrs: termios? = term
                    for await event in eventLoop {
                        // Pass through any program I/O and/or terminal settings between our terminal and the
                        // pseudo-terminal we've allocated
                        if case let .success(event) = event {
                            switch event {
                            case .stdin(let data):
                                guard let data else { break }
                                try await pty.main.write(contentsOf: data)
                            case .stdout(let data):
                                guard let data else { break }
                                // A couple of things to make sure that interactive programs are handled properly. If
                                // we notice any changes to the secondary PTY's settings, we need to configure stdin
                                // (assuming it's a TTY) to reflect the same changes, minus the echo setting, to avoid
                                // input getting displayed twice.
                                if let currAttrs = try? PTY.getAttrs(fileHandle: pty.secondary) {
                                    let currModes = currAttrs.localModes.subtracting(.echo)
                                    let ptyModes = ptyAttrs?.localModes.subtracting(.echo)
                                    if currModes != ptyModes ||
                                        currAttrs.c_cflag != ptyAttrs?.c_cflag ||
                                        currAttrs.c_iflag != ptyAttrs?.c_iflag ||
                                        currAttrs.c_oflag != ptyAttrs?.c_oflag {
                                        // Standard input may not be a tty, just ignore any errors when setting the
                                        // same attributes that got set on the PTY.
                                        ptyAttrs = try? PTY.setAttrs(term: currAttrs)

                                        // Disable line buffering if settings change, so that we can forward keystrokes
                                        // one at a time.
                                        if linebuf {
                                            setvbuf(stdin, nil, _IONBF, 0)
                                            setvbuf(stdout, nil, _IONBF, 0)
                                            linebuf = false
                                        }

                                        // Send the change of settings as an event.
                                        continuation.yield(.success(.termio(ptyAttrs)))
                                    }
                                }

                                try await FileHandle.standardOutput.write(contentsOf: data)
                            case .stderr(let data):
                                guard let data else { break }

                                // Always echo stderr, regardless of whether or not we're interactive.
                                try await FileHandle.standardError.write(contentsOf: data)
                            case .exit:
                                // allow event loop to finish and clean up -- we'll get a bunch of nil completions in
                                // the cases above when this happens.
                                try pty.secondary.close()
                            default:
                                break
                            }
                        }
                        continuation.yield(event)
                        try Task.checkCancellation()
                    }
                } catch is CancellationError {
                    return linebuf // Continuation has already been finished if we've been cancelled
                } catch {
                    continuation.yield(.failure(error))
                }

                continuation.finish()
                return linebuf
            }

            continuation.onTermination = { [term] _ in
                loop.cancel()

                // We already closed the secondary pty when the process exited.
                try? pty.main.close()
                try? stderrPipe.fileHandleForReading.close()

                // Restore the previous terminal settings, if we're hooked up to one.
                _ = try? PTY.setAttrs(term: term)

                Task {
                    if let linebuf = try? await loop.result.get(), !linebuf {
                        // Restore normal line buffering to the terminal.
                        setlinebuf(stdin)
                        setlinebuf(stdout)
                    }
                }
            }
        }
    }
}

/// An SSH transport for Git that execs ssh, and routes the information over the tunnel. This is useful because it lets
/// users customize the ssh command, and it allows for ssh to parse the user's host configuration.
class SSHTransport: Transport {
    /// This can be modified according to values in the environment and git config, see `GIT_SSH_COMMAND`
    /// and `core.sshCommand` in the official Git documentation.
    static var sshCommand = "ssh"

    override func connect(_ urlString: String, action: Action) -> Result<Stream, GitError> {
        let stream: SSHTransportStream
        let remoteCommand = action == .uploadPackLs ? "git-upload-pack" : "git-receive-pack"
        do {
            stream = try SSHTransportStream(transport: self, urlString: urlString, remoteCommand: remoteCommand)
        } catch let error as GitError {
            return .failure(error)
        } catch {
            return .failure(.init(
                code: .error,
                detail: .operatingSystem,
                description: "Error creating stream",
                userInfo: [
                    NSUnderlyingErrorKey: error
                ]
            ))
        }

        return .success(stream)
    }

    override func close() -> Result<(), GitError> {
        do {
            // smart transport will call close() as its first action to reset the stream.
            guard let stream = stream as? SSHTransportStream else { return .success(()) }

            try stream.input.fileHandleForWriting.close()
            try stream.output.fileHandleForReading.close()

            return .success(())
        } catch {
            return .failure(.init(
                code: .error,
                detail: .operatingSystem,
                description: "Error closing streams",
                userInfo: [
                    NSUnderlyingErrorKey: error
                ]
            ))
        }
    }
}

class SSHTransportStream: Transport.Stream {
    let urlString: String
    
    let input: Pipe
    let output: Pipe

    var error: Error?

    init(transport: SSHTransport, urlString: String, remoteCommand: String) throws {
        self.urlString = urlString
        self.input = Pipe()
        self.output = Pipe()

        try posix(fcntl(output.fileHandleForReading.fileDescriptor, F_SETFL))

        super.init(transport: transport)

        let urlComponents = urlString.split(separator: ":", maxSplits: 1)
        guard let host = urlComponents.first, let path = urlComponents.second else {
            throw GitError(code: .invalid, detail: .ssh, description: "URL \(urlString) is malformed")
        }

        let command = "\(SSHTransport.sshCommand) \(host) '\(remoteCommand)' '\(path)' <&4 >&5"

        let process = try Internal.shell.run(
            command: command,
            extraFileDescriptors: [
                4: input.fileHandleForReading,
                5: output.fileHandleForWriting
            ]
        )

        Task.detached { [process, input, output] in
            loop: for await result in process {
                switch result {
                case .success(let event):
                    switch event {
                    case .exit(let code):
                        Shell.queue.async { [weak self] in
                            if code != 0 {
                                self?.error = Shell.Exit(rawValue: code)
                            }
                        }
                        break loop
                    default:
                        continue
                    }
                case .failure(let error):
                    Shell.queue.async { [weak self] in
                        self?.error = error
                    }
                    break loop
                }
            }

            do {
                // The symmetric ends of these pipes are closed by the transport in the `close` function.
                try input.fileHandleForReading.close()
                try output.fileHandleForWriting.close()
            } catch {
                Shell.queue.async { [weak self] in
                    if self?.error == nil {
                        self?.error = error
                    }
                }
            }
        }
    }

    override func read(length: Int) -> Result<Data, GitError> {
        if let error {
            return .failure(.init(
                code: .error,
                detail: .ssh,
                description: "Couldn't connect to remote",
                userInfo: [
                    NSUnderlyingErrorKey: error
                ]
            ))
        }

        do {
            // Figure out how much available data is in the file descriptor.
            var bytesAvailable: Int32 = 0
            try posix(ioctl(
                output.fileHandleForReading.fileDescriptor,
                UInt(ioctl_fionread),
                &bytesAvailable
            ))

            if bytesAvailable == 0 {
                bytesAvailable = 1 // Try to read at least one character if no data available
            }

            let readLength = min(Int(bytesAvailable), length)
            let data = try output.fileHandleForReading.read(upToCount: readLength) ?? Data()

            return .success(data)
        } catch {
            return .failure(.init(
                code: .error,
                detail: .operatingSystem,
                description: "Couldn't read from remote",
                userInfo: [
                    NSUnderlyingErrorKey: error
                ]
            ))
        }
    }

    override func write(data: Data) -> Result<(), GitError> {
        if let error {
            return .failure(.init(
                code: .error,
                detail: .ssh,
                description: "Couldn't connect to remote",
                userInfo: [
                    NSUnderlyingErrorKey: error
                ]
            ))
        }

        do {
            try input.fileHandleForWriting.write(contentsOf: data)
            return .success(())
        } catch {
            return .failure(.init(
                code: .error,
                detail: .operatingSystem,
                description: "Couldn't write to remote",
                userInfo: [
                    NSUnderlyingErrorKey: error
                ]
            ))
        }
    }
}

private extension FileHandle {
    static func forNewKernelQueue() throws -> Self {
        return Self(fileDescriptor: try posixCheckErrnoIfNegative(kqueue()))
    }

    func write(string: String) async throws {
        try await write(contentsOf: string.data(using: .utf8) ?? Data())
    }

    func read(upToCount count: Int) async throws -> Data? {
        try await withCheckedThrowingContinuation {
            do {
                try $0.resume(returning: read(upToCount: count))
            } catch {
                $0.resume(throwing: error)
            }
        }
    }

    func write(contentsOf data: any DataProtocol) async throws {
        try await withCheckedThrowingContinuation {
            do {
                try self.write(contentsOf: data)
                $0.resume()
            } catch {
                $0.resume(throwing: error)
            }
        }
    }
}

public enum ShellError: Error, CustomStringConvertible {
    case invalidShell(String)
    case notRunning

    public var description: String {
        switch self {
        case .invalidShell(let path):
            return "\(path)"
        case .notRunning:
            return "Process is not running"
        }
    }
}

extension Internal {
    public static var shell: Shellish = Shell()

    public static func print(_ items: Any..., separator: String = " ", terminator: String = "\n", error: Bool = false) {
        Internal.shell.print(
            items.map { String(describing: $0) }.joined(separator: separator) + terminator,
            error: error
        )
    }

    static var registerTransports = {
        let transport = SSHTransport.self
        try Transport.register(transport, for: "ssh")
        try Transport.register(transport, for: "ssh+git")
        try Transport.register(transport, for: "git+ssh")
    }
}

fileprivate extension termios {
    var localModes: Shell.PTY.Mode {
        return .init(rawValue: c_lflag)
    }
}
