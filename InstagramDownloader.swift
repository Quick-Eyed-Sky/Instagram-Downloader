import SwiftUI
import Foundation
import CryptoKit

typealias ViewState<Value> = SwiftUI.State<Value>

struct ContentView: View {
    @AppStorage("loginUsername") private var loginUsername = ""
    @AppStorage("targetUsername") private var targetUsername = ""
    @AppStorage("maximumPosts") private var maximumPosts = "100"
    @AppStorage("destination") private var destination = "~/Desktop/Instagram_Downloads"
    @AppStorage("imagesOnly") private var imagesOnly = false
    @AppStorage("removeDuplicates") private var removeDuplicates = true

    @ViewState<Double> private var progress = 0.0
    @ViewState<Int> private var processedPosts = 0
    @ViewState<Int> private var totalPosts = 0
    @ViewState<Int> private var downloadedFiles = 0
    @ViewState<String> private var log = "Ready.\n"
    @ViewState<Bool> private var running = false
    @ViewState<Bool> private var downloading = false
    @ViewState<Bool> private var stopping = false
    @ViewState<Bool> private var stopRequested = false
    @ViewState<Process?> private var activeProcess = nil

    private var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Instagram Downloader", isDirectory: true)
    }

    private var sessionDirectory: URL { supportDirectory.appendingPathComponent("sessions", isDirectory: true) }
    private var environmentDirectory: URL { supportDirectory.appendingPathComponent("python", isDirectory: true) }
    private var virtualPython: URL { environmentDirectory.appendingPathComponent("bin/python3") }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "camera.fill")
                    .font(.title2)
                    .foregroundStyle(.pink)
                Text("Instagram Downloader").font(.title2).bold()
            }
            Text("Save photos and videos from an Instagram profile using your Chrome session.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("Your Instagram username").frame(width: 175, alignment: .leading)
                    TextField("", text: $loginUsername).textFieldStyle(.roundedBorder)
                }
                HStack(spacing: 10) {
                    Text("Profile to download").frame(width: 175, alignment: .leading)
                    TextField("", text: $targetUsername).textFieldStyle(.roundedBorder)
                }
                HStack(spacing: 10) {
                    Text("Maximum posts").frame(width: 175, alignment: .leading)
                    TextField("100", text: $maximumPosts)
                        .frame(width: 150)
                        .textFieldStyle(.roundedBorder)
                    Spacer(minLength: 0)
                }
                Toggle("Images only", isOn: $imagesOnly)
                Toggle("Remove exact duplicates automatically", isOn: $removeDuplicates)
                HStack(spacing: 10) {
                    Text("Destination").frame(width: 175, alignment: .leading)
                    TextField("", text: $destination).textFieldStyle(.roundedBorder)
                    Button("Choose…") { chooseFolder() }
                }
            }
            .padding(.vertical, 4)
            .disabled(running)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    ProgressView(value: progress, total: 1.0)
                    Text("\(Int(progress * 100))%")
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }
                Text(progressLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Install / Update Dependencies") { installDependencies() }
                    .disabled(running)
                Button("Import Chrome Session") { importSession() }
                    .disabled(running || normalized(loginUsername).isEmpty)
                Button(running ? "Working…" : "↓ Download") { startDownload() }
                    .fontWeight(.semibold)
                    .buttonStyle(.borderedProminent)
                    .disabled(running || normalized(loginUsername).isEmpty || normalized(targetUsername).isEmpty)
            }
            .controlSize(.small)

            HStack {
                Button(stopping ? "Stopping…" : "■ STOP") { stopProcess() }
                    .fontWeight(.semibold)
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(!running || stopping || activeProcess?.isRunning != true)
                Button("Open folder") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: NSString(string: destination).expandingTildeInPath))
                }
            }
            .controlSize(.regular)

            Text("A 3–8 second pause separates posts. Instagram rate limits trigger longer waits; repeated limits stop the run safely.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Activity").font(.headline)
            ScrollView {
                Text(log)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
            .padding(8)
            .background(.quaternary.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(20)
        .frame(minWidth: 700, idealWidth: 700, minHeight: 690, idealHeight: 690)
    }

    private var progressLabel: String {
        if processedPosts > 0 || totalPosts > 0 {
            return "\(processedPosts) of \(totalPosts) post(s) processed · \(downloadedFiles) new file(s)"
        }
        return running ? "Preparing…" : "Waiting to start…"
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url { destination = url.path }
    }

    func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
    }

    func username(_ value: String, allowDots: Bool) -> String? {
        let value = normalized(value)
        let pattern = allowDots ? "^[A-Za-z0-9._]{1,30}$" : "^[A-Za-z0-9_]{1,30}$"
        return value.range(of: pattern, options: .regularExpression) == nil ? nil : value
    }

    func installDependencies() {
        guard let basePython = findPython() else {
            append("❌ Python 3 was not found. Install Python 3 from python.org or Homebrew, then try again.")
            return
        }
        running = true
        stopping = false
        stopRequested = false
        append("Preparing a private Python environment…")
        do { try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true) }
        catch { append("❌ \(error.localizedDescription)"); running = false; return }

        runProcess(executable: basePython, arguments: ["-m", "venv", environmentDirectory.path]) { status in
            if stopRequested {
                append("⏹ Operation stopped. No further setup steps were started.")
                finishOperation()
                return
            }
            guard status == 0 else {
                append("❌ Could not create the private Python environment.")
                running = false
                return
            }
            append("Installing Instaloader and browser-cookie3…")
            runProcess(executable: virtualPython, arguments: ["-m", "pip", "install", "--upgrade", "pip", "instaloader", "browser-cookie3"]) { installStatus in
                if stopRequested {
                    append("⏹ Dependency installation stopped.")
                } else {
                    append(installStatus == 0 ? "✓ Dependencies are ready." : "❌ Dependency installation failed. Check the activity log and network connection.")
                }
                finishOperation()
            }
        }
    }

    func importSession() {
        guard let login = username(loginUsername, allowDots: false) else {
            append("Enter a valid Instagram username first.")
            return
        }
        guard FileManager.default.isExecutableFile(atPath: virtualPython.path) else {
            append("Install dependencies first, then import your Chrome session.")
            return
        }
        do { try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true) }
        catch { append("❌ \(error.localizedDescription)"); return }
        running = true
        stopping = false
        stopRequested = false
        append("Importing the active Instagram session from Chrome…")
        runWorker(arguments: ["import-session", "--username", login, "--session-dir", sessionDirectory.path]) { status in
            if stopRequested {
                append("⏹ Session import stopped.")
            } else {
                append(status == 0 ? "✓ Session import finished." : "❌ Session import failed.")
            }
            finishOperation()
        }
    }

    func startDownload() {
        guard let login = username(loginUsername, allowDots: false),
              let target = username(targetUsername, allowDots: true),
              let limit = Int(maximumPosts), limit > 0 else {
            append("Enter valid usernames and a positive maximum post count.")
            return
        }
        guard FileManager.default.isExecutableFile(atPath: virtualPython.path) else {
            append("Install dependencies first.")
            return
        }
        let output = URL(fileURLWithPath: NSString(string: destination).expandingTildeInPath)
            .appendingPathComponent(target, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        } catch { append("❌ \(error.localizedDescription)"); return }

        running = true
        downloading = true
        stopping = false
        stopRequested = false
        progress = 0
        processedPosts = 0
        totalPosts = limit
        downloadedFiles = 0
        log = "Preparing download for @\(target)…\n"
        append("Maximum: \(limit) post(s)")
        append("Mode: \(imagesOnly ? "IMAGES ONLY" : "IMAGES + VIDEOS / REELS")")
        append("Duplicates: \(removeDuplicates ? "REMOVE EXACT COPIES" : "KEEP")")
        append("Authentication: SAVED CHROME SESSION")
        append("")

        var arguments = ["download", "--username", login, "--target", target,
                         "--limit", String(limit), "--session-dir", sessionDirectory.path,
                         "--output", output.deletingLastPathComponent().path,
                         "--delay-min", "3", "--delay-max", "8"]
        if imagesOnly { arguments.append("--images-only") }
        runWorker(arguments: arguments) { status in
            if stopRequested {
                append("\n⏹ Stopped by you. Files already downloaded were kept.")
            } else if status == 0 {
                if removeDuplicates {
                    append("\n🔎 Checking for exact duplicates…")
                    let duplicatesOK = removeExactDuplicates(in: output)
                    if duplicatesOK { append("✓ Duplicate check complete.") }
                    else { append("⚠️ Some files could not be checked for duplicates.") }
                }
                progress = 1.0
                append("\n✅ Finished.")
            } else {
                append("\n⚠️ Download stopped before completion. Files already downloaded were kept.")
            }
            downloading = false
            finishOperation()
        }
    }

    func runWorker(arguments: [String], completion: @escaping (Int32) -> Void) {
        guard let worker = Bundle.main.resourceURL?.appendingPathComponent("InstagramWorker.py"),
              FileManager.default.fileExists(atPath: worker.path) else {
            append("❌ InstagramWorker.py is missing from the application bundle.")
            completion(1)
            return
        }
        runProcess(executable: virtualPython, arguments: [worker.path] + arguments, completion: completion)
    }

    func runProcess(executable: URL, arguments: [String], completion: @escaping (Int32) -> Void) {
        let task = Process()
        activeProcess = task
        ActiveChildProcess.current = task
        task.executableURL = executable
        task.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        task.environment = environment
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do { try task.run() }
        catch {
            append("❌ Could not start the helper: \(error.localizedDescription)")
            activeProcess = nil
            ActiveChildProcess.current = nil
            completion(1)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let reader = pipe.fileHandleForReading
            var pending = Data()
            while true {
                let chunk = reader.availableData
                if chunk.isEmpty { break }
                pending.append(chunk)
                while let newline = pending.firstIndex(of: 10) {
                    let line = String(decoding: pending[..<newline], as: UTF8.self)
                    pending.removeSubrange(...newline)
                    DispatchQueue.main.async { handleOutput(line) }
                }
            }
            if !pending.isEmpty {
                let line = String(decoding: pending, as: UTF8.self)
                DispatchQueue.main.async { handleOutput(line) }
            }
            task.waitUntilExit()
            DispatchQueue.main.async {
                activeProcess = nil
                ActiveChildProcess.current = nil
                completion(task.terminationStatus)
            }
        }
    }

    func handleOutput(_ line: String) {
        let prefix = "INSTAGRAM_DOWNLOADER_EVENT:"
        guard line.hasPrefix(prefix),
              let data = String(line.dropFirst(prefix.count)).data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let kind = event["event"] as? String else {
            append(line)
            return
        }
        switch kind {
        case "status", "error", "stopped", "done":
            append(event["message"] as? String ?? kind.capitalized)
        case "total":
            totalPosts = (event["count"] as? Int) ?? totalPosts
            append("Profile: @\(event["profile"] as? String ?? "unknown") · \(totalPosts) post(s) in the timeline")
        case "post":
            processedPosts = (event["current"] as? Int) ?? processedPosts
            totalPosts = (event["total"] as? Int) ?? totalPosts
            downloadedFiles += (event["media_count"] as? Int) ?? 0
            progress = totalPosts > 0 ? min(Double(processedPosts) / Double(totalPosts), 0.99) : 0
            append("✓ [\(processedPosts)/\(totalPosts)] \(event["kind"] as? String ?? "post") · \(event["shortcode"] as? String ?? "")")
        case "file":
            if let path = event["path"] as? String { append("📷 \((path as NSString).lastPathComponent)") }
        default:
            append(line)
        }
    }

    func stopProcess() {
        guard let activeProcess, activeProcess.isRunning, !stopping else { return }
        stopRequested = true
        stopping = true
        append("Stopping the current operation… Completed downloads will be kept.")
        activeProcess.terminate()
    }

    func finishOperation() {
        running = false
        stopping = false
        stopRequested = false
    }

    func findPython() -> URL? {
        ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]
            .map(URL.init(fileURLWithPath:))
            .first(where: { FileManager.default.isExecutableFile(atPath: $0.path) })
    }

    func append(_ text: String) {
        guard !text.isEmpty else { return }
        log += text + (text.hasSuffix("\n") ? "" : "\n")
        if log.count > 30000 { log = String(log.suffix(30000)) }
    }

    func hash(_ url: URL) -> String? {
        guard let stream = InputStream(url: url) else { return nil }
        stream.open()
        guard stream.streamStatus != .error else { return nil }
        defer { stream.close() }
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 1024 * 1024)
        while stream.hasBytesAvailable {
            let size = stream.read(&buffer, maxLength: buffer.count)
            if size < 0 { return nil }
            if size == 0 { break }
            hasher.update(data: Data(buffer[0..<size]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    func removeExactDuplicates(in folder: URL) -> Bool {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else {
            append("⚠️ Could not read the destination folder for duplicate checking.")
            return false
        }
        var seen: [String: URL] = [:]
        var count = 0
        var failed = false
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  let digest = hash(url) else { continue }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let key = "\(size)-\(digest)"
            if let original = seen[key] {
                do {
                    try fm.removeItem(at: url)
                    count += 1
                    append("🗑 Duplicate: \(url.lastPathComponent) (same as \(original.lastPathComponent))")
                } catch {
                    append("⚠️ Could not remove duplicate \(url.lastPathComponent): \(error.localizedDescription)")
                    failed = true
                }
            } else {
                seen[key] = url
            }
        }
        append("✓ \(count) exact duplicate(s) removed.")
        return !failed
    }
}

@main
struct InstagramDownloaderApp: App {
    @NSApplicationDelegateAdaptor(AppTerminationHandler.self) private var appTerminationHandler

    var body: some Scene {
        WindowGroup { ContentView() }
            .windowResizability(.contentSize)
    }
}

private enum ActiveChildProcess {
    static var current: Process?
}

private final class AppTerminationHandler: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        guard let process = ActiveChildProcess.current, process.isRunning else { return }
        process.terminate()
    }
}
