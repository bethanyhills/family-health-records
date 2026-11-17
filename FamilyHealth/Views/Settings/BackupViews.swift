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

/// Settings section for making and restoring the password-protected backup file.
struct BackupSection: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.recordAccess) private var access
    @AppStorage(BackupStatus.lastBackupKey) private var lastBackupAt: Double = 0

    @State private var isChoosingPassword = false
    @State private var document: BackupDocument?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var importedData: Data?
    @State private var isSharing = false
    @State private var isImportingShared = false
    @State private var sharedData: Data?
    @State private var message: String?
    @State private var pendingMessage: String?

    var body: some View {
        Section {
            Button {
                isChoosingPassword = true
            } label: {
                Label("Back up now", systemImage: "externaldrive.badge.plus")
            }
            Button {
                isImporting = true
            } label: {
                Label("Restore from a backup", systemImage: "arrow.counterclockwise")
            }
            Button {
                isSharing = true
            } label: {
                Label("Share family members…", systemImage: "person.2.badge.plus")
            }
            Button {
                isImportingShared = true
            } label: {
                Label("Import shared family members", systemImage: "square.and.arrow.down")
            }
            // Adding people needs the trial or the unlock. Restoring your own
            // backup always works, so records are never stuck on an old phone.
            .disabled(!access.canEdit)
        } header: {
            Text("Backup")
        } footer: {
            Text(footer)
        }
        .sheet(isPresented: $isChoosingPassword, onDismiss: {
            // Present the save dialog only after the password sheet is gone.
            if document != nil { isExporting = true }
        }) {
            NavigationStack {
                BackupPasswordView(mode: .create) { password in
                    makeBackup(password: password)
                }
            }
        }
        .sheet(isPresented: Binding(get: { importedData != nil }, set: { if !$0 { importedData = nil } }), onDismiss: {
            message = pendingMessage
            pendingMessage = nil
        }) {
            NavigationStack {
                BackupPasswordView(mode: .restore) { password in
                    restore(password: password)
                }
            }
        }
        .sheet(isPresented: $isSharing) {
            NavigationStack { ShareProfilesView() }
        }
        .sheet(isPresented: Binding(get: { sharedData != nil }, set: { if !$0 { sharedData = nil } }), onDismiss: {
            message = pendingMessage
            pendingMessage = nil
        }) {
            NavigationStack {
                BackupPasswordView(mode: .importShared) { password in
                    importShared(password: password)
                }
            }
        }
        .fileImporter(isPresented: $isImportingShared, allowedContentTypes: [.json, .data]) { result in
            switch result {
            case .success(let url):
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    sharedData = try Data(contentsOf: url)
                } catch {
                    message = error.localizedDescription
                }
            case .failure(let error):
                message = error.localizedDescription
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: document,
            contentType: .json,
            defaultFilename: "Family Health Binder Backup \(Date.now.formatted(.iso8601.year().month().day()))"
        ) { result in
            switch result {
            case .success:
                lastBackupAt = Date.now.timeIntervalSince1970
                message = "Backup saved. Keep the password somewhere safe; without it the backup can't be opened."
            case .failure(let error):
                message = error.localizedDescription
            }
            document = nil
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json, .data]) { result in
            switch result {
            case .success(let url):
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    importedData = try Data(contentsOf: url)
                } catch {
                    message = error.localizedDescription
                }
            case .failure(let error):
                message = error.localizedDescription
            }
        }
        .alert("Backup", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private var footer: String {
        let when = lastBackupAt == 0
            ? "You haven't made a backup yet."
            : "Last backup: \(Date(timeIntervalSince1970: lastBackupAt).formatted(date: .abbreviated, time: .shortened))."
        return "\(when) The backup is a password-protected file you can save to Files or a computer, and use to move your records to a new iPhone. To give someone else a copy of some family members, use Share family members."
    }

    private func makeBackup(password: String) -> String? {
        do {
            let archive = try BackupArchive(context: modelContext)
            document = BackupDocument(data: try BackupCrypto.encrypt(archive, password: password))
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func restore(password: String) -> String? {
        guard let importedData else { return nil }
        do {
            let archive = try BackupCrypto.decrypt(importedData, password: password)
            if archive.isSharedProfiles == true {
                return "This file has only some family members. Use Import shared family members instead, so nothing else is replaced."
            }
            try archive.restore(into: modelContext)
            pendingMessage = "Restored \(archive.people.count) family member\(archive.people.count == 1 ? "" : "s") from the backup made \(archive.exportedAt.formatted(date: .abbreviated, time: .omitted))."
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

extension BackupSection {
    fileprivate func importShared(password: String) -> String? {
        guard let sharedData else { return nil }
        do {
            let archive = try BackupCrypto.decrypt(sharedData, password: password)
            let result = try archive.merge(into: modelContext)
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
                    .foregroundStyle(.red)
            }
        }
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
