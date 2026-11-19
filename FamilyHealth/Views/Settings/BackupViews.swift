import Observation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum BackupStatus {
    static let lastBackupKey = "lastBackupAt"
    static let reminderInterval: TimeInterval = 30 * 24 * 60 * 60

    static func isDue(lastBackupAt: Double, now: Date = .now) -> Bool {
        lastBackupAt == 0 || now.timeIntervalSince1970 - lastBackupAt > reminderInterval
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// What the backup screens are doing: which sheet or file dialog is open, and the files
/// in hand. Owned by the Settings page, so the sheets can hang off the page itself: a sheet
/// attached to a list section is dismissed as soon as the list redraws that section.
@MainActor
@Observable
final class BackupFlow {
    var isChoosingPassword = false
    var document: BackupDocument?
    var isExporting = false
    /// One file dialog serves both kinds of import: SwiftUI shows only one `fileImporter` per view.
    enum ImportKind { case restore, shared }
    var isPickingFile = false
    var importKind = ImportKind.restore
    var importedData: Data?
    var isSharing = false
    var sharedData: Data?
    var message: String?
    var pendingMessage: String?

    func makeBackup(password: String, in context: ModelContext) -> String? {
        do {
            let archive = try BackupArchive(context: context)
            document = BackupDocument(data: try BackupCrypto.encrypt(archive, password: password))
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func restore(password: String, in context: ModelContext) -> String? {
        guard let importedData else { return nil }
        do {
            let archive = try BackupCrypto.decrypt(importedData, password: password)
            if archive.isSharedProfiles == true {
                return "This file has only some family members. Use Import shared family members instead, so nothing else is replaced."
            }
            try archive.restore(into: context)
            pendingMessage = "Restored \(archive.people.count) family member\(archive.people.count == 1 ? "" : "s") from the backup made \(archive.exportedAt.formatted(date: .abbreviated, time: .omitted))."
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func importShared(password: String, in context: ModelContext) -> String? {
        guard let sharedData else { return nil }
        do {
            let archive = try BackupCrypto.decrypt(sharedData, password: password)
            let result = try archive.merge(into: context)
            let names = archive.people.map(\.name).joined(separator: ", ")
            pendingMessage = switch (result.added, result.updated) {
            case (_, 0): "Added \(names)."
            case (0, _): "Updated \(names)."
            default: "Added or updated \(names)."
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Reads a file chosen in Files, or keeps the error to show.
    func read(_ result: Result<URL, Error>) -> Data? {
        switch result {
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                return try Data(contentsOf: url)
            } catch {
                message = error.localizedDescription
            }
        case .failure(let error):
            message = error.localizedDescription
        }
        return nil
    }

    func pickFile(for kind: ImportKind) {
        importKind = kind
        isPickingFile = true
    }

    func showPendingMessage() {
        message = pendingMessage
        pendingMessage = nil
    }
}

/// Settings section for making and restoring the password-protected backup file.
/// Its sheets and file dialogs are attached to the page with `backupPresentations(_:)`.
struct BackupSection: View {
    let flow: BackupFlow
    @Environment(\.recordAccess) private var access
    @AppStorage(BackupStatus.lastBackupKey) private var lastBackupAt: Double = 0

    var body: some View {
        Section {
            Button {
                flow.isChoosingPassword = true
            } label: {
                Label("Back up now", systemImage: "externaldrive.badge.plus")
            }
            Button {
                flow.pickFile(for: .restore)
            } label: {
                Label("Restore from a backup", systemImage: "arrow.counterclockwise")
            }
            Button {
                flow.isSharing = true
            } label: {
                Label("Share family members…", systemImage: "person.2.badge.plus")
            }
            Button {
                flow.pickFile(for: .shared)
            } label: {
                Label("Import shared family members", systemImage: "square.and.arrow.down")
            }
            // Importing people needs a plan (or its free trial). Restoring your
            // own backup always works, so records are never stuck on an old phone.
            .disabled(!access.canImportPeople)
        } header: {
            Text("Backup")
        } footer: {
            Text(footer)
        }
    }

    private var footer: String {
        let when = lastBackupAt == 0
            ? "You haven't made a backup yet."
            : "Last backup: \(Date(timeIntervalSince1970: lastBackupAt).formatted(date: .abbreviated, time: .shortened))."
        return "\(when) The backup is a password-protected file you can save to Files or a computer, and use to move your records to a new iPhone. To give someone else a copy of some family members, use Share family members."
    }
}

/// The backup sheets, file dialogs and messages, attached to the Settings page.
private struct BackupPresentations: ViewModifier {
    @Bindable var flow: BackupFlow
    @Environment(\.modelContext) private var modelContext
    @AppStorage(BackupStatus.lastBackupKey) private var lastBackupAt: Double = 0

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $flow.isChoosingPassword, onDismiss: {
                // Present the save dialog only after the password sheet is gone.
                if flow.document != nil { flow.isExporting = true }
            }) {
                NavigationStack {
                    BackupPasswordView(mode: .create) { password in
                        flow.makeBackup(password: password, in: modelContext)
                    }
                }
            }
            .sheet(isPresented: Binding(get: { flow.importedData != nil }, set: { if !$0 { flow.importedData = nil } }),
                   onDismiss: flow.showPendingMessage) {
                NavigationStack {
                    BackupPasswordView(mode: .restore) { password in
                        flow.restore(password: password, in: modelContext)
                    }
                }
            }
            .sheet(isPresented: $flow.isSharing) {
                NavigationStack { ShareProfilesView() }
            }
            .sheet(isPresented: Binding(get: { flow.sharedData != nil }, set: { if !$0 { flow.sharedData = nil } }),
                   onDismiss: flow.showPendingMessage) {
                NavigationStack {
                    BackupPasswordView(mode: .importShared) { password in
                        flow.importShared(password: password, in: modelContext)
                    }
                }
            }
            .fileExporter(
                isPresented: $flow.isExporting,
                document: flow.document,
                contentType: .json,
                defaultFilename: "Family Health Binder Backup \(Date.now.formatted(.iso8601.year().month().day()))"
            ) { result in
                switch result {
                case .success:
                    lastBackupAt = Date.now.timeIntervalSince1970
                    flow.message = "Backup saved. Keep the password somewhere safe; without it the backup can't be opened."
                case .failure(let error):
                    flow.message = error.localizedDescription
                }
                flow.document = nil
            }
            .fileImporter(isPresented: $flow.isPickingFile, allowedContentTypes: [.json, .data]) { result in
                let data = flow.read(result)
                switch flow.importKind {
                case .restore: flow.importedData = data
                case .shared: flow.sharedData = data
                }
            }
            .alert("Backup", isPresented: Binding(get: { flow.message != nil }, set: { if !$0 { flow.message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(flow.message ?? "")
            }
    }
}

extension View {
    func backupPresentations(_ flow: BackupFlow) -> some View {
        modifier(BackupPresentations(flow: flow))
    }
}

/// Asks for the backup password. `onSubmit` returns an error message to show, or nil when done.
struct BackupPasswordView: View {
    enum Mode { case create, restore, importShared }

    let mode: Mode
    let onSubmit: (String) -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirmation = ""
    @State private var error: String?
    @State private var isConfirmingReplace = false
    @State private var isWorking = false

    var body: some View {
        Form {
            Section {
                SecureField("Password", text: $password)
                    .textContentType(mode == .create ? .newPassword : .password)
                if mode == .create {
                    SecureField("Confirm password", text: $confirmation)
                        .textContentType(.newPassword)
                }
            } footer: {
                Text(mode == .create
                     ? "Choose a password of at least \(BackupCrypto.minimumPasswordLength) characters. You'll need it to restore. If it's lost, the backup can't be opened."
                     : mode == .restore
                        ? "Enter the password you chose when you made this backup."
                        : "Enter the password from the person who shared this file. Anyone already on this iPhone is updated; everyone else stays as they are.")
            }
            if let error {
                Text(error)
                    .foregroundStyle(Theme.danger)
            }
        }
        .brandedBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                if isWorking {
                    ProgressView()
                } else {
                    Button(buttonTitle) {
                        if mode == .restore {
                            isConfirmingReplace = true
                        } else {
                            submit()
                        }
                    }
                    .disabled(!canSubmit)
                }
            }
        }
        .confirmationDialog("Replace everything on this iPhone?", isPresented: $isConfirmingReplace, titleVisibility: .visible) {
            Button("Replace with backup", role: .destructive) { submit() }
        } message: {
            Text("All family members and records currently in the app will be replaced by the ones in the backup.")
        }
    }

    private var canSubmit: Bool {
        switch mode {
        case .create: password.count >= BackupCrypto.minimumPasswordLength && password == confirmation
        case .restore, .importShared: !password.isEmpty
        }
    }

    private var title: String {
        switch mode {
        case .create: "Back up"
        case .restore: "Restore"
        case .importShared: "Import"
        }
    }

    private var buttonTitle: String {
        switch mode {
        case .create: "Create"
        case .restore: "Restore"
        case .importShared: "Import"
        }
    }

    private func submit() {
        isWorking = true
        // Let the spinner draw before the key derivation runs.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            if let failure = onSubmit(password) {
                error = failure
                isWorking = false
            } else {
                dismiss()
            }
        }
    }
}
