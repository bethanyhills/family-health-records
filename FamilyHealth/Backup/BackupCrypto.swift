import CommonCrypto
import CryptoKit
import Foundation
import Security

/// Password-protected backup file: PBKDF2-SHA256 derives a key from the
/// password, and AES-256-GCM encrypts the archive. Without the password the
/// file can't be read, so it is safe to keep in Files, email or a USB drive.
enum BackupCrypto {
    static let format = "family-health-binder-backup"
    static let defaultIterations = 310_000
    static let minimumPasswordLength = 8

    enum Failure: LocalizedError, Equatable {
        case notABackup
        case newerVersion
        case wrongPassword
        case passwordTooShort

        var errorDescription: String? {
            switch self {
            case .notABackup: "This file isn't a Family Health Binder backup."
            case .newerVersion: "This backup was made by a newer version of the app. Update the app and try again."
            case .wrongPassword: "That password doesn't match this backup."
            case .passwordTooShort: "Use a password of at least \(BackupCrypto.minimumPasswordLength) characters."
            }
        }
    }

    private struct Envelope: Codable {
        var format: String
        var version: Int
        var kdf: String
        var iterations: Int
        var salt: Data
        var sealed: Data
    }

    static func encrypt(_ archive: BackupArchive, password: String, iterations: Int = defaultIterations) throws -> Data {
        guard password.count >= minimumPasswordLength else { throw Failure.passwordTooShort }
        let plaintext = try JSONEncoder().encode(archive)

        var salt = Data(count: 16)
        let status = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard status == errSecSuccess else { throw CocoaError(.fileWriteUnknown) }

        let key = try deriveKey(password: password, salt: salt, iterations: iterations)
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else { throw CocoaError(.fileWriteUnknown) }

        let envelope = Envelope(format: format, version: 1, kdf: "PBKDF2-SHA256", iterations: iterations, salt: salt, sealed: combined)
        let output = JSONEncoder()
        output.outputFormatting = [.sortedKeys]
        return try output.encode(envelope)
    }

    static func decrypt(_ data: Data, password: String) throws -> BackupArchive {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.format == format,
              envelope.kdf == "PBKDF2-SHA256",
              envelope.iterations > 0
        else { throw Failure.notABackup }
        guard envelope.version <= 1 else { throw Failure.newerVersion }

        let key = try deriveKey(password: password, salt: envelope.salt, iterations: envelope.iterations)
        let plaintext: Data
        do {
            plaintext = try AES.GCM.open(AES.GCM.SealedBox(combined: envelope.sealed), using: key)
        } catch {
            throw Failure.wrongPassword
        }

        let archive: BackupArchive
        do {
            archive = try JSONDecoder().decode(BackupArchive.self, from: plaintext)
        } catch {
            throw Failure.notABackup
        }
        guard archive.version <= BackupArchive.currentVersion else { throw Failure.newerVersion }
        return archive
    }

    static func deriveKey(password: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        let passwordBytes = Array(password.utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        let status = salt.withUnsafeBytes { saltBuffer in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                passwordBytes.map { Int8(bitPattern: $0) }, passwordBytes.count,
                saltBuffer.bindMemory(to: UInt8.self).baseAddress, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                UInt32(iterations),
                &derived, derived.count
            )
        }
        guard status == Int32(kCCSuccess) else { throw CocoaError(.fileReadUnknown) }
        return SymmetricKey(data: derived)
    }
}
