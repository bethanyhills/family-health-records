import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppLock.settingKey) private var requireAuthentication = true
    @State private var backup = BackupFlow()
    @Environment(Purchases.self) private var purchases
    @State private var isShowingUnlock = false
    @AppStorage(FamilyTitle.key) private var familyTitle = ""

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(FamilyTitle.standard, text: $familyTitle)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                } header: {
                    Text("Family name")
                } footer: {
                    Text("The title of your family list, like \"Hills Family\". Leave it empty for \"My Family\".")
                }

                Section {
                    Toggle("Require \(AppLock.biometryName)", isOn: $requireAuthentication)
                } header: {
                    Text("Security")
                } footer: {
                    Text("Asks for \(AppLock.biometryName) or your passcode every time Family Health Binder opens.")
                }

                PurchaseSection { isShowingUnlock = true }

                BackupSection(flow: backup)

                Section("Privacy") {
                    Label("Your records are stored only on this iPhone.", systemImage: "iphone")
                    Label("Nothing is sent to a server, and there's no account, tracking or advertising.", systemImage: "hand.raised.fill")
                    Label("Records are encrypted whenever your iPhone is locked.", systemImage: "lock.fill")
                }

                Section {
                    Text("Family Health Binder is a place to keep your own records. It doesn't give medical advice. Always check with your doctor or pharmacist before making medical decisions.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("About")
                }

                Section {
                    LabeledContent("Version", value: version)
                }
            }
            .navigationTitle("Settings")
            .backupPresentations(backup)
            .sheet(isPresented: $isShowingUnlock) {
                UnlockView()
            }
            .purchaseAlert(purchases, when: !isShowingUnlock)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
