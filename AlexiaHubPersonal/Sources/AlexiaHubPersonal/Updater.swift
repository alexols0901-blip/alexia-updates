import SwiftUI
import AppKit
import CryptoKit

private struct ReleaseInfo: Decodable {
    let version: String
    let url: URL
    let sha256: String
}

private enum UpdateFailure: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

@MainActor
final class PersonalUpdater: ObservableObject {
    @Published var feedURL = UserDefaults.standard.string(forKey: "updateFeedURL") ?? ""
    @Published var message = "Choose an update ZIP to install it inside the app."
    @Published var busy = false
    @Published private(set) var availableVersion: String?
    private var release: ReleaseInfo?
    private let currentVersion = "1.1.2"

    func checkAutomatically() async {
        guard !feedURL.isEmpty else { return }
        await check()
    }

    func check() async {
        guard !busy else { return }
        guard let url = URL(string: feedURL), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil else {
            message = "Enter the HTTPS address of your release feed."
            return
        }
        busy = true
        defer { busy = false }
        do {
            UserDefaults.standard.set(feedURL, forKey: "updateFeedURL")
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  http.url?.scheme == "https", http.url?.host == url.host,
                  data.count < 100_000 else { throw UpdateFailure.message("The release feed could not be loaded.") }
            let info = try JSONDecoder().decode(ReleaseInfo.self, from: data)
            guard info.url.scheme == "https", info.url.host == url.host,
                  info.url.user == nil, info.url.password == nil,
                  info.sha256.count == 64, info.sha256.allSatisfy({ $0.isHexDigit }) else {
                throw UpdateFailure.message("Invalid release details. The update must use HTTPS on the same host as the feed and include its SHA-256 hash.")
            }
            if info.version.compare(currentVersion, options: .numeric) == .orderedDescending {
                release = info
                availableVersion = info.version
                message = "Update \(info.version) available."
            } else {
                release = nil
                availableVersion = nil
                message = "You have the latest version (\(currentVersion))."
            }
        } catch { message = error.localizedDescription }
    }

    func downloadUpdate() async {
        guard !busy, let release = release else { return }
        busy = true
        defer { busy = false }
        message = "Downloading update…"
        do {
            let (download, response) = try await URLSession.shared.download(from: release.url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  http.url?.scheme == "https", http.url?.host == release.url.host else {
                throw UpdateFailure.message("Download failed or redirected to another host.")
            }
            let attributes = try FileManager.default.attributesOfItem(atPath: download.path)
            guard ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) < 30_000_000 else {
                throw UpdateFailure.message("The update ZIP is too large.")
            }
            let data = try Data(contentsOf: download)
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard digest == release.sha256.lowercased() else { throw UpdateFailure.message("Update hash mismatch. Installation stopped.") }
            let zip = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
            try data.write(to: zip, options: .atomic)
            defer { try? FileManager.default.removeItem(at: zip) }
            try await buildAndInstall(zip)
        } catch { message = error.localizedDescription }
    }

    func chooseUpdate() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose an Alexia HUB Personal update ZIP"
        panel.allowedFileTypes = ["zip"]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let alert = NSAlert()
        alert.messageText = "Install this app update?"
        alert.informativeText = "This compiles and installs the app code from \(url.lastPathComponent). Choose a release you trust. Your script library stays in Application Support."
        alert.addButton(withTitle: "Install update")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        busy = true
        Task {
            defer { busy = false }
            do { try await buildAndInstall(url) }
            catch { message = error.localizedDescription }
        }
    }

    private func buildAndInstall(_ archive: URL) async throws {
        message = "Checking update…"
        let installedApp = Bundle.main.bundleURL
        guard installedApp.pathExtension == "app" else {
            throw UpdateFailure.message("Launch the built .app before using the updater.")
        }
        let targetParent = installedApp.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: targetParent.path) else {
            throw UpdateFailure.message("Move the app into your user Applications folder first. This location is not writable.")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AlexiaUpdate-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var handedOff = false
        defer { if !handedOff { try? FileManager.default.removeItem(at: directory) } }
        let listing = try await Self.run("/usr/bin/unzip", ["-Z1", archive.path], logDirectory: directory)
        let entries = listing.split(separator: "\n").map(String.init)
        guard !entries.isEmpty, entries.count < 1000, entries.allSatisfy({ entry in
            entry.hasPrefix("AlexiaHubPersonal/") && !entry.hasPrefix("/") &&
            !entry.contains("\\") && !entry.split(separator: "/").contains("..")
        }) else { throw UpdateFailure.message("This ZIP does not contain an AlexiaHubPersonal update.") }
        let metadata = try await Self.run("/usr/bin/zipinfo", ["-l", archive.path], logDirectory: directory)
        guard !metadata.split(separator: "\n").contains(where: { $0.hasPrefix("l") }) else {
            throw UpdateFailure.message("Update archives must not contain symbolic links.")
        }
        try await Self.run("/usr/bin/ditto", ["-x", "-k", archive.path, directory.path], logDirectory: directory)
        let project = directory.appendingPathComponent("AlexiaHubPersonal")
        let contents = FileManager.default.enumerator(at: project, includingPropertiesForKeys: [.isSymbolicLinkKey])
        while let item = contents?.nextObject() as? URL {
            if try item.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                throw UpdateFailure.message("Update archives must not contain symbolic links.")
            }
        }
        guard FileManager.default.fileExists(atPath: project.appendingPathComponent("Package.swift").path),
              FileManager.default.fileExists(atPath: project.appendingPathComponent("Sources/AlexiaHubPersonal/App.swift").path) else {
            throw UpdateFailure.message("The update source files are missing.")
        }
        message = "Building update… Keep the app open. This can take a few minutes."
        try await Self.run("/usr/bin/xcrun", ["swift", "build", "--package-path", project.path, "-c", "debug"], logDirectory: directory)
        let binPath = try await Self.run("/usr/bin/xcrun", ["swift", "build", "--package-path", project.path, "-c", "debug", "--show-bin-path"], logDirectory: directory)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let newApp = directory.appendingPathComponent("Alexia HUB Personal.app")
        try FileManager.default.copyItem(at: installedApp, to: newApp)
        let executable = newApp.appendingPathComponent("Contents/MacOS/AlexiaHubPersonal")
        try FileManager.default.removeItem(at: executable)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: binPath).appendingPathComponent("AlexiaHubPersonal"), to: executable)
        let icon = project.appendingPathComponent("Assets/AppIcon.icns")
        if FileManager.default.fileExists(atPath: icon.path) {
            let resources = newApp.appendingPathComponent("Contents/Resources", isDirectory: true)
            try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
            let destination = resources.appendingPathComponent("AppIcon.icns")
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: icon, to: destination)
        }
        let releaseFile = project.appendingPathComponent("release.json")
        let infoPlist = newApp.appendingPathComponent("Contents/Info.plist")
        if let data = try? Data(contentsOf: releaseFile),
           let release = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let version = release["version"] as? String {
            let original = try Data(contentsOf: infoPlist)
            var plist = try PropertyListSerialization.propertyList(from: original, format: nil) as! [String: Any]
            plist["CFBundleShortVersionString"] = version
            plist["CFBundleIconFile"] = "AppIcon"
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: infoPlist, options: .atomic)
        }
        try await Self.run("/usr/bin/codesign", ["--force", "--sign", "-", newApp.path], logDirectory: directory)
        let alert = NSAlert()
        alert.messageText = "Update ready"
        alert.informativeText = "Restart Alexia HUB Personal to install the update. Your saved scripts will be available after restart."
        alert.addButton(withTitle: "Install and restart")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { message = "Installation cancelled."; return }
        let helper = directory.appendingPathComponent("install.sh")
        try Self.installScript.write(to: helper, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [helper.path, String(ProcessInfo.processInfo.processIdentifier), newApp.path, installedApp.path, directory.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        handedOff = true
        NSApplication.shared.terminate(nil)
    }

    @discardableResult
    private nonisolated static func run(_ path: String, _ arguments: [String], logDirectory: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let log = logDirectory.appendingPathComponent(UUID().uuidString + ".log")
            FileManager.default.createFile(atPath: log.path, contents: nil)
            let output = try FileHandle(forWritingTo: log)
            defer { try? output.close(); try? FileManager.default.removeItem(at: log) }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = output
            try process.run()
            process.waitUntilExit()
            let text = String(decoding: try Data(contentsOf: log), as: UTF8.self)
            guard process.terminationStatus == 0 else { throw UpdateFailure.message(String(text.suffix(10_000))) }
            return text
        }.value
    }

    private static let installScript = """
    set -eu
    old_pid="$1"
    new_app="$2"
    target="$3"
    work="$4"
    while kill -0 "$old_pid" 2>/dev/null; do sleep 1; done
    stage="${target}.update-$$"
    backup="${target}.backup-$$"
    if ! /usr/bin/ditto "$new_app" "$stage"; then
        /usr/bin/open "$target"
        exit 1
    fi
    if ! /bin/mv "$target" "$backup"; then
        /bin/rm -rf "$stage"
        /usr/bin/open "$target"
        exit 1
    fi
    if ! /bin/mv "$stage" "$target"; then
        /bin/mv "$backup" "$target"
        /usr/bin/open "$target"
        exit 1
    fi
    if /usr/bin/open "$target"; then
        /bin/rm -rf "$backup" "$work"
    else
        /bin/mv "$target" "$stage"
        /bin/mv "$backup" "$target"
        /usr/bin/open "$target"
    fi
    """
}

struct UpdatesPage: View {
    @ObservedObject var updater: PersonalUpdater
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Updates").font(.largeTitle.bold())
            Text("Version 1.1.2").foregroundStyle(.secondary)
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Install an update ZIP").font(.headline)
                    Text("Download a new Alexia HUB Personal ZIP, then choose it here. The app builds and installs the update for you.")
                    Button("Choose update ZIP…") { updater.chooseUpdate() }.disabled(updater.busy)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Online updates").font(.headline)
                    Text("Connect an HTTPS release feed to enable automatic checks at app launch and every hour.")
                        .font(.callout).foregroundStyle(.secondary)
                    TextField("HTTPS release feed URL", text: $updater.feedURL).textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Save and check") { Task { await updater.check() } }
                        if let version = updater.availableVersion {
                            Button("Install \(version)") { Task { await updater.downloadUpdate() } }
                                .buttonStyle(.borderedProminent)
                        }
                    }.disabled(updater.busy)
                    Text(updater.feedURL.isEmpty ? "Online updates are not connected." : "Only use a release feed you trust.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
            if updater.busy { ProgressView().controlSize(.small) }
            Text(updater.message).textSelection(.enabled).font(.callout)
        }
    }
}
