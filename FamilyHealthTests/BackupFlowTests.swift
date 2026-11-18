import SwiftData
import XCTest
@testable import FamilyHealth

@MainActor
final class BackupFlowTests: XCTestCase {
    func testBackupMadeInSettingsRestoresAndSharedFilesAreTurnedAway() throws {
        let source = ModelContext(ModelStore.makeContainer(inMemory: true))
        source.insert(Person(name: "Pat Example"))
        try source.save()

        let flow = BackupFlow()
        XCTAssertNil(flow.makeBackup(password: "correct horse", in: source))
        let file = try XCTUnwrap(flow.document?.data)

        let target = ModelContext(ModelStore.makeContainer(inMemory: true))
        flow.importedData = file
        XCTAssertNil(flow.restore(password: "correct horse", in: target))
        XCTAssertEqual(try target.fetch(FetchDescriptor<Person>()).map(\.name), ["Pat Example"])
        flow.showPendingMessage()
        XCTAssertEqual(flow.message?.hasPrefix("Restored 1 family member"), true)
        XCTAssertNotNil(flow.restore(password: "wrong", in: target))

        let shared = try BackupCrypto.encrypt(BackupArchive(context: source, onlyPeople: []), password: "shared-pass", iterations: 1_000)
        flow.importedData = shared
        XCTAssertEqual(flow.restore(password: "shared-pass", in: target)?.hasPrefix("This file has only some family members"), true)
    }
}
