import SwiftData
import SwiftUI

struct PersonDetailView: View {
    @Bindable var person: Person
    @Environment(\.modelContext) private var modelContext
    @Environment(\.recordAccess) private var access
    @Environment(Purchases.self) private var purchases

    @State private var isEditing = false
    @State private var isEditingSchool = false
    @State private var message: String?
    @State private var isShowingUnlock = false
    @State private var addingPlanKind: DocumentKind?
    @State private var scanningPlan = false

    var body: some View {
        List {
            if purchases.status == .ended {
                Section {
                    TrialBanner(status: .ended) { isShowingUnlock = true }
                }
            }

            header

            Section {
                NavigationLink {
                    IntakeSummaryView(person: person)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Intake summary")
                                .font(.headline)
                            Text("Everything a new doctor's form asks, ready to copy or share as a PDF")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "list.clipboard.fill")
                            .foregroundStyle(.tint)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Health records") {
                RecordLink("Medications", systemImage: "pills.fill", color: .blue, count: person.medications.filter(\.isActive).count) {
                    MedicationsView(person: person)
                }
                RecordLink("Allergies", systemImage: "allergens.fill", color: .red, count: person.allergies.count) {
                    AllergiesView(person: person)
                }
                RecordLink("Conditions", systemImage: "stethoscope", color: .purple, count: person.conditions.filter { $0.status != .resolved }.count) {
                    ConditionsView(person: person)
                }
                RecordLink("Therapies", systemImage: "figure.play", color: .pink, count: person.therapies.filter(\.isActive).count) {
                    TherapiesView(person: person)
                }
                RecordLink("Surgeries & procedures", systemImage: "cross.case.fill", color: .orange, count: person.procedures.count) {
                    ProceduresView(person: person)
                }
                RecordLink("Immunizations", systemImage: "syringe.fill", color: .teal, count: person.immunizations.count) {
                    ImmunizationsView(person: person)
                }
                RecordLink("Family history", systemImage: "person.3.fill", color: .brown, count: person.familyHistory.count) {
                    FamilyHistoryView(person: person)
                }
            }

            Section("Visits and documents") {
                RecordLink("Visit notes", systemImage: "note.text", color: .cyan, count: person.visits.count) {
                    VisitsView(person: person)
                }
                RecordLink("Documents", systemImage: "doc.text.fill", color: .gray, count: person.documents.count) {
                    DocumentsView(person: person)
                }
            }

            Section("Care team") {
                RecordLink("Providers", systemImage: "person.badge.shield.checkmark.fill", color: .green, count: person.providers.count) {
                    ProvidersView(person: person)
                }
                RecordLink("Pharmacies", systemImage: "cross.vial.fill", color: .mint, count: person.pharmacies.count) {
                    PharmaciesView(person: person)
                }
                RecordLink("Insurance", systemImage: "creditcard.fill", color: .indigo, count: person.insurancePolicies.count) {
                    InsuranceView(person: person)
                }
                RecordLink("Emergency contacts", systemImage: "phone.fill", color: .pink, count: person.contacts.count) {
                    EmergencyContactsView(person: person)
                }
            }

            SchoolSection(
                person: person,
                onEdit: { isEditingSchool = true },
                onAddPlanDocument: { scanningPlan = false; addingPlanKind = $0 },
                onScanPlanDocument: { scanningPlan = true; addingPlanKind = $0 }
            )

            Section("Basics") {
                InfoRow("Date of birth", person.dateOfBirth?.formDate ?? "")
                SocialSecurityRow(digits: person.socialSecurityNumber)
                InfoRow("Sex", person.sex == .unspecified ? "" : person.sex.label)
                InfoRow("Blood type", person.bloodType == .unknown ? "" : person.bloodType.label)
                InfoRow("Height", person.height)
                InfoRow("Weight", person.weight)
                InfoRow("Communication needs", person.communicationNeeds)
                if hasNoBasics {
                    Text("No details yet. Tap Edit to add blood type, height and weight.")
                        .foregroundStyle(.secondary)
                }
            }

            if !person.notes.isBlank {
                Section("Notes") {
                    Text(person.notes)
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle(person.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if access.canEdit {
                Button("Edit") { isEditing = true }
            }
        }
        .sheet(isPresented: $isEditing) {
            NavigationStack { PersonEditView(person: person) }
        }
        .sheet(isPresented: $isEditingSchool) {
            NavigationStack { SchoolEditView(person: person) }
        }
        .sheet(item: $addingPlanKind) { kind in
            NavigationStack { DocumentEditView(person: person, document: nil, initialKind: kind, startsScanning: scanningPlan) { message = $0 } }
        }
        .sheet(isPresented: $isShowingUnlock) {
            UnlockView()
        }
        .successBanner($message)
    }

    private var header: some View {
        Section {
            HStack(spacing: 16) {
                AvatarView(photoData: person.photoData, initials: person.initials, size: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text(person.displayName)
                        .font(.title2.bold())
                    if !person.preferredName.isBlank {
                        Text("Goes by \(person.preferredName)")
                            .foregroundStyle(.secondary)
                    }
                    if let age = person.age {
                        Text("Age \(age)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var hasNoBasics: Bool {
        person.dateOfBirth == nil && person.sex == .unspecified && person.bloodType == .unknown
            && person.height.isBlank && person.weight.isBlank && person.socialSecurityNumber.isEmpty
    }
}

/// A row linking to one kind of record, with a colored icon and a count.
struct RecordLink<Destination: View>: View {
    let title: String
    let systemImage: String
    let color: Color
    let count: Int
    @ViewBuilder let destination: () -> Destination

    init(
        _ title: String,
        systemImage: String,
        color: Color,
        count: Int,
        @ViewBuilder destination: @escaping () -> Destination
    ) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
        self.count = count
        self.destination = destination
    }

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(color.gradient, in: RoundedRectangle(cornerRadius: 7))
                Text(title)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
