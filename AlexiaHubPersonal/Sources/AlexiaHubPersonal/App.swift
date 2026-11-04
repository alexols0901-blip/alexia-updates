import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SavedScript: Codable, Identifiable {
    var id = UUID()
    var name: String
    var code: String
}

final class ScriptLibrary: ObservableObject {
    @Published private(set) var scripts: [SavedScript] = []
    @Published var error: String?
    private let file: URL
    private var canSave = true

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AlexiaHubPersonal", isDirectory: true)
        file = directory.appendingPathComponent("scripts.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) {
                scripts = try JSONDecoder().decode([SavedScript].self, from: Data(contentsOf: file))
            }
        } catch {
            canSave = false
            self.error = "Could not read your script library. Your saved file has been preserved. \(error.localizedDescription)"
        }
    }

    func save(_ script: SavedScript) throws {
        var updated = scripts
        if let index = updated.firstIndex(where: { $0.id == script.id }) {
            updated[index] = script
        } else {
            updated.append(script)
        }
        try persist(updated)
    }

    func delete(_ script: SavedScript) throws {
        try persist(scripts.filter { $0.id != script.id })
    }

    private func persist(_ updated: [SavedScript]) throws {
        guard canSave else {
            throw NSError(domain: "AlexiaHub", code: 1, userInfo: [NSLocalizedDescriptionKey: "Restart after restoring or repairing scripts.json in Application Support/AlexiaHubPersonal."])
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(updated).write(to: file, options: .atomic)
        scripts = updated
    }
}

@main
struct AlexiaPersonalApp: App {
    var body: some Scene {
        WindowGroup("Alexia HUB — Personal") {
            PersonalHub()
                .frame(minWidth: 780, minHeight: 560)
                .preferredColorScheme(.dark)
        }
    }
}

struct PersonalHub: View {
    @StateObject private var library = ScriptLibrary()
    @StateObject private var updater = PersonalUpdater()
    @State private var page = "scripts"
    @State private var search = ""
    @State private var editing: SavedScript?
    @State private var pendingDelete: SavedScript?
    @State private var status = ""
    @State private var appLocations = UserDefaults.standard.dictionary(forKey: "personalAppLocations") as? [String: String] ?? [:]

    private var filteredScripts: [SavedScript] {
        library.scripts.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(alignment: .leading, spacing: 20) {
                if page == "scripts" { scriptPage }
                else if page == "apps" { appsPage }
                else { UpdatesPage(updater: updater) }
                Spacer(minLength: 0)
                Text(status).font(.callout).foregroundStyle(.secondary)
                    .textSelection(.enabled).accessibilityLabel("Status: \(status)")
            }
            .padding(30)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await updater.checkAutomatically()
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 3_600_000_000_000) }
                catch { return }
                await updater.checkAutomatically()
            }
        }
        .sheet(item: $editing) { script in
            ScriptEditor(script: script) { try library.save($0) }
        }
        .alert("Delete script?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Delete", role: .destructive) {
                guard let script = pendingDelete else { return }
                do {
                    try library.delete(script)
                    status = "Deleted \(script.name)."
                } catch { library.error = error.localizedDescription }
                pendingDelete = nil
            }
        } message: {
            Text("Remove \(pendingDelete?.name ?? "this script") from your saved library?")
        }
        .alert("Unable to complete action", isPresented: Binding(
            get: { library.error != nil },
            set: { if !$0 { library.error = nil } }
        )) {
            Button("OK") { library.error = nil }
        } message: { Text(library.error ?? "") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let image = NSImage(named: "AppIcon") {
                Image(nsImage: image).resizable().scaledToFit().frame(width: 56, height: 56)
            }
            Text("ALEXIA HUB").font(.title2.bold()).foregroundStyle(.cyan)
            Text("PERSONAL").font(.caption).foregroundStyle(.secondary)
            Divider().padding(.vertical, 8)
            Button { page = "scripts" } label: {
                Label("Scripts", systemImage: "chevron.left.forwardslash.chevron.right")
                    .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                    .background(page == "scripts" ? Color.cyan.opacity(0.15) : Color.white.opacity(0.05))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
                    .contentShape(Rectangle())
            }
            Button { page = "apps" } label: {
                Label("Apps", systemImage: "square.grid.2x2")
                    .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                    .background(page == "apps" ? Color.cyan.opacity(0.15) : Color.white.opacity(0.05))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
                    .contentShape(Rectangle())
            }
            Button { page = "updates" } label: {
                Label(updater.availableVersion == nil ? "Updates" : "Update available", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                    .background(page == "updates" ? Color.cyan.opacity(0.15) : Color.white.opacity(0.05))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
                    .contentShape(Rectangle())
            }
            Spacer()
            Text("Saved on this Mac").font(.caption).foregroundStyle(.secondary)
        }
        .buttonStyle(.plain).padding(22).frame(width: 210)
        .frame(maxHeight: .infinity)
    }

    private var scriptPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Script library").font(.largeTitle.bold())
                Spacer()
                Button { editing = SavedScript(name: "", code: "") } label: {
                    Label("Add script", systemImage: "plus")
                }.buttonStyle(.borderedProminent).tint(.cyan)
            }
            TextField("Search scripts", text: $search).textFieldStyle(.roundedBorder)
            ScrollView {
                if library.scripts.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "doc.badge.plus").font(.system(size: 42)).foregroundStyle(.cyan)
                        Text("Your scripts live here").font(.title3.bold())
                        Text("Press Add script, enter a name, and paste your script.").foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 70)
                } else if filteredScripts.isEmpty {
                    Text("No scripts match your search.").padding(30)
                }
                LazyVStack(spacing: 14) {
                    ForEach(filteredScripts) { script in
                        GroupBox {
                            VStack(alignment: .leading, spacing: 18) {
                                Label(script.name, systemImage: "doc.text.fill").font(.headline).foregroundStyle(.cyan)
                                HStack {
                                    Button("Copy script") { copy(script) }
                                    Button("Run script") {
                                        copy(script)
                                        openApp("MacSploit", success: "Script copied. MacSploit opened. Paste the script there to run it.")
                                    }.buttonStyle(.borderedProminent).tint(.cyan)
                                    Spacer()
                                    Button("Edit") { editing = script }
                                    Button("Delete", role: .destructive) { pendingDelete = script }
                                }
                            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            Text("Run script copies your code and opens MacSploit. Paste it there to execute.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var appsPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Apps").font(.largeTitle.bold())
            ScrollView {
                VStack(spacing: 14) {
                    appTile("ChatGPT", subtitle: "Open ChatGPT in your browser", fallback: "globe") {
                        guard let url = URL(string: "https://chatgpt.com/") else { return }
                        if NSWorkspace.shared.open(url) { status = "ChatGPT opened in your browser." }
                        else { library.error = "macOS could not open your web browser." }
                    }
                    appTile("Discord", subtitle: "Open the Discord app", fallback: "bubble.left.and.bubble.right.fill") {
                        openApp("Discord", success: "Discord opened.")
                    }
                    appTile("Roblox", subtitle: "Open the Roblox app", fallback: "gamecontroller.fill") {
                        openApp("Roblox", success: "Roblox opened.")
                    }
                    appTile("MacSploit", subtitle: "Open the MacSploit app", fallback: "terminal.fill") {
                        openApp("MacSploit", success: "MacSploit opened.")
                    }
                }
            }
        }
    }

    private func appTile(_ name: String, subtitle: String, fallback: String, action: @escaping () -> Void) -> some View {
        GroupBox {
            HStack(spacing: 16) {
                if let url = applicationURL(name) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable().interpolation(.high).scaledToFit().frame(width: 48, height: 48)
                } else {
                    Image(systemName: fallback).font(.system(size: 30)).foregroundStyle(.cyan)
                        .frame(width: 48, height: 48)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(name).font(.title3.bold())
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Open " + name, action: action).buttonStyle(.borderedProminent)
            }.padding(16)
        }
    }

    private func applicationURL(_ name: String) -> URL? {
        if let saved = appLocations[name], FileManager.default.fileExists(atPath: saved) {
            return URL(fileURLWithPath: saved)
        }
        let identifiers = ["Discord": "com.hnc.Discord", "Roblox": "com.roblox.RobloxPlayer", "ChatGPT": "com.openai.chat"]
        if let identifier = identifiers[name], let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
            return url
        }
        for directory in ["/Applications", NSHomeDirectory() + "/Applications"] {
            let url = URL(fileURLWithPath: directory).appendingPathComponent(name + ".app")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    private func copy(_ script: SavedScript) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(script.code, forType: .string)
        status = "Copied \(script.name)."
    }

    private func openApp(_ name: String, success: String) {
        if let url = applicationURL(name) {
            launchApp(url, success: success)
            return
        }
        let panel = NSOpenPanel()
        panel.title = "Locate \(name).app"
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        appLocations[name] = url.path
        UserDefaults.standard.set(appLocations, forKey: "personalAppLocations")
        launchApp(url, success: success)
    }

    private func launchApp(_ url: URL, success: String) {
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            DispatchQueue.main.async {
                if let error = error { library.error = error.localizedDescription }
                else { status = success }
            }
        }
    }


}

struct ScriptEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var script: SavedScript
    let onSave: (SavedScript) throws -> Void
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(script.name.isEmpty ? "Add script" : "Edit script").font(.title2.bold())
            TextField("Script name", text: $script.name).textFieldStyle(.roundedBorder)
            Text("Script code").font(.headline)
            TextEditor(text: $script.code).font(.system(.body, design: .monospaced))
                .border(Color.gray.opacity(0.3)).frame(minHeight: 280)
            if let error = error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Button("Import script file…") { importScript() }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save script") {
                    var saved = script
                    saved.name = saved.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    do { try onSave(saved); dismiss() }
                    catch { self.error = error.localizedDescription }
                }
                .buttonStyle(.borderedProminent).keyboardShortcut("s", modifiers: .command)
                .disabled(script.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || script.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 650, height: 510)
    }

    private func importScript() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            script.code = try String(contentsOf: url, encoding: .utf8)
            if script.name.isEmpty { script.name = url.deletingPathExtension().lastPathComponent }
        } catch { self.error = "Could not read this file as UTF-8 text. \(error.localizedDescription)" }
    }
}
