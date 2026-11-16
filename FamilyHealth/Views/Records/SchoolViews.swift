import SwiftData
import SwiftUI

/// School details on a child's page: their grade and teacher, plus the shared school.
struct SchoolSection: View {
    let person: Person
    @Environment(\.recordAccess) private var access
    @State private var isEditing = false

    var body: some View {
        Section {
            if person.hasSchoolInfo {
                if let school = person.school {
                    InfoRow("School", school.name)
                }
                InfoRow("Grade", person.schoolGrade)
                InfoRow("Teacher", person.teacherName)
                InfoRow("Teacher email", person.teacherEmail)
                InfoRow("Teacher phone", person.teacherPhone)
                if let school = person.school {
                    InfoRow("School phone", school.phone)
                    InfoRow("School address", school.address)
                    InfoRow("Nurse", school.nurseName)
                    InfoRow("Nurse phone", school.nursePhone)
                    InfoRow("Nurse email", school.nurseEmail)
                }
            }
            if access.canEdit {
                Button {
                    isEditing = true
                } label: {
                    Label(person.hasSchoolInfo ? "Edit school details" : "Add school details", systemImage: "graduationcap")
                }
            }
        } header: {
            Text("School")
        }
        .sheet(isPresented: $isEditing) {
            NavigationStack { SchoolEditView(person: person) }
        }
    }
}

struct SchoolEditView: View {
    let person: Person

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \School.name) private var schools: [School]

    /// nil means "a new school".
    @State private var selectedSchoolID: UUID?
    @State private var noSchool = false
    @State private var schoolName = ""
    @State private var address = ""
    @State private var phone = ""
    @State private var nurseName = ""
    @State private var nursePhone = ""
    @State private var nurseEmail = ""
    @State private var grade = ""
    @State private var teacherName = ""
    @State private var teacherEmail = ""
    @State private var teacherPhone = ""
    @State private var didLoad = false

    var body: some View {
        EditorForm(title: "School", canSave: noSchool || !schoolName.isBlank, onSave: save) {
            if !schools.isEmpty {
                Section {
                    Picker("School", selection: Binding(
                        get: { noSchool ? "none" : (selectedSchoolID?.uuidString ?? "new") },
                        set: { choice in
                            noSchool = choice == "none"
                            selectedSchoolID = UUID(uuidString: choice)
                            load(schools.first { $0.id == selectedSchoolID })
                        }
                    )) {
                        ForEach(schools) { Text($0.name).tag($0.id.uuidString) }
                        Text("A different school…").tag("new")
                        Text("No school").tag("none")
                    }
                } footer: {
                    Text("Siblings at the same school share its office and nurse details.")
                }
            }
            if !noSchool {
                Section("\(person.displayName)'s year") {
                    Picker("Grade", selection: $grade) {
                        Text("Not set").tag("")
                        ForEach(SchoolGrade.options(keeping: grade), id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Teacher's name", text: $teacherName)
                        .textInputAutocapitalization(.words)
                    TextField("Teacher's email", text: $teacherEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    TextField("Teacher's phone", text: $teacherPhone)
                        .keyboardType(.phonePad)
                }
                Section("School") {
                    TextField("School name", text: $schoolName)
                        .textInputAutocapitalization(.words)
                    TextField("Office phone", text: $phone)
                        .keyboardType(.phonePad)
                    TextField("Address", text: $address, axis: .vertical)
                        .textContentType(.fullStreetAddress)
                }
                Section("School nurse") {
                    TextField("Nurse's name", text: $nurseName)
                        .textInputAutocapitalization(.words)
                    TextField("Nurse's phone", text: $nursePhone)
                        .keyboardType(.phonePad)
                    TextField("Nurse's email", text: $nurseEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                }
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            grade = person.schoolGrade
            teacherName = person.teacherName
            teacherEmail = person.teacherEmail
            teacherPhone = person.teacherPhone
            selectedSchoolID = person.school?.id
            load(person.school)
        }
    }

    private func load(_ school: School?) {
        schoolName = school?.name ?? ""
        address = school?.address ?? ""
        phone = school?.phone ?? ""
        nurseName = school?.nurseName ?? ""
        nursePhone = school?.nursePhone ?? ""
        nurseEmail = school?.nurseEmail ?? ""
    }

    private func save() {
        if noSchool {
            person.schools = []
            person.schoolGrade = ""
            person.teacherName = ""
            person.teacherEmail = ""
            person.teacherPhone = ""
            return
        }
        let school = schools.first { $0.id == selectedSchoolID } ?? {
            let new = School(name: schoolName.trimmed)
            modelContext.insert(new)
            return new
        }()
        school.name = schoolName.trimmed
        school.address = address.trimmed
        school.phone = phone.trimmed
        school.nurseName = nurseName.trimmed
        school.nursePhone = nursePhone.trimmed
        school.nurseEmail = nurseEmail.trimmed
        person.schools = [school]
        person.schoolGrade = grade.trimmed
        person.teacherName = teacherName.trimmed
        person.teacherEmail = teacherEmail.trimmed
        person.teacherPhone = teacherPhone.trimmed
    }
}

/// The grades offered in the school editor. Stored as plain text on `Person.schoolGrade`.
enum SchoolGrade {
    static let all: [String] = ["Preschool", "Pre-K", "Kindergarten"]
        + (1...12).map(ordinal).map { "\($0) grade" }
        + ["College", "Not in school"]

    /// The standard list, plus a grade typed by hand in an earlier version so it isn't lost.
    static func options(keeping current: String) -> [String] {
        let current = current.trimmingCharacters(in: .whitespacesAndNewlines)
        return current.isEmpty || all.contains(current) ? all : [current] + all
    }

    private static func ordinal(_ n: Int) -> String {
        let suffix: String
        switch n % 100 {
        case 11, 12, 13: suffix = "th"
        default:
            switch n % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(n)\(suffix)"
    }
}
