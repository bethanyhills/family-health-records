import SwiftData
import SwiftUI

/// Makes a password-protected file with some family members, to send to another phone
/// (a parent, or a teenager who now goes to appointments on their own).
struct ShareProfilesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Person.sortOrder), SortDescriptor(\Person.name)]) private var people: [Person]

    @State private var selection: Set<UUID> = []
    @State private var password = ""
    @State private var confirmation = ""
    @State private var fileURL: URL?
    @State private var error: String?
    @State private var isWorking = false
    @State private var didLoad = false

    var body: some View {
        Form {
            if let fileURL {
                Section {
                    ShareLink(item: fileURL) {
                        Label("Send the file", systemImage: "square.and.arrow.up")
                    }
                } footer: {
                    Text("Send it by AirDrop, Messages or email. On their iPhone, they save it to Files, then open Family Health Binder and go to Settings › Import shared family members. Tell them the password in person or by phone, not in the same message as the file.")
                }
            } else {
                Section {
                    PeopleToggles(people: people, selection: $selection)
                } header: {
                    Text("Who to share")
                } footer: {
                    Text("The file includes their records and the providers, insurance, pharmacies, emergency contacts and school they use. No one else's records are included.")
                }
                Section {
                    SecureField("Password", text: $password)
                        .textContentType(.newPassword)
                    SecureField("Confirm password", text: $confirmation)
                        .textContentType(.newPassword)
                } footer: {
                    Text("At least \(BackupCrypto.minimumPasswordLength) characters. They'll need it to open the file.")
                }
                if let error {
                    Text(error).foregroundStyle(Theme.danger)
                }
            }
        }
        .brandedBackground()
        .navigationTitle("Share family members")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(fileURL == nil ? "Cancel" : "Done") { dismiss() }
            }
            if fileURL == nil {
                ToolbarItem(placement: .confirmationAction) {
                    if isWorking {
                        ProgressView()
                    } else {
                        Button("Create file", action: createFile).disabled(!canCreate)
                    }
                }
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            if people.count == 1 { selection = [people[0].id] }
        }
        .onDisappear {
            // The file only needs to live long enough to be sent.
            if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        }
    }

    private var canCreate: Bool {
        !selection.isEmpty && password.count >= BackupCrypto.minimumPasswordLength && password == confirmation
    }

    private func createFile() {
        isWorking = true
        Task { @MainActor in
            // Let the spinner draw before the key derivation runs.
            try? await Task.sleep(for: .milliseconds(50))
            do {
                let archive = try BackupArchive(context: modelContext, onlyPeople: selection)
                let data = try BackupCrypto.encrypt(archive, password: password)
                let names = people.filter { selection.contains($0.id) }.map(\.displayName)
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent(ShareProfilesView.fileName(for: names))
                try data.write(to: url, options: [.atomic, .completeFileProtection])
                fileURL = url
            } catch {
                self.error = error.localizedDescription
            }
            isWorking = false
        }
    }

    /// e.g. "Health Binder - Emma and Leo.json"
    static func fileName(for names: [String]) -> String {
        let who: String
        switch names.count {
        case 0: who = "Family"
        case 1: who = names[0]
        case 2: who = "\(names[0]) and \(names[1])"
        default: who = "\(names[0]) and \(names.count - 1) others"
        }
        let safe = who.components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|")).joined()
        return "Health Binder - \(safe).json"
    }
}
