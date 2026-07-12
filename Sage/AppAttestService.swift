import Foundation
import CryptoKit

#if canImport(DeviceCheck) && os(iOS)
import DeviceCheck
#endif

// MARK: - App Attest (DeviceCheck)
//
// Produces a hardware-backed deviceId (keyId) the backend can validate with
// Apple's DeviceCheck API before counting a scan against the free-tier limit.
// Simulator and unsupported devices fall back to BackendService.clientTag only.

struct AppAttestPayload: Equatable {
    let deviceId: String
    let assertion: String       // base64
    let clientDataHash: String  // base64
}

enum AppAttestService {

    private static let keyIdDefaultsKey = "sage.appattest.keyId"
    private static let attestedDefaultsKey = "sage.appattest.attested"

    static var isSupported: Bool {
        #if canImport(DeviceCheck) && os(iOS)
        return DCAppAttestService.shared.isSupported
        #else
        return false
        #endif
    }

    /// App Attest keyId — sent as `deviceId` on /lookup once attested.
    static var registeredDeviceId: String? {
        guard isSupported,
              UserDefaults.standard.bool(forKey: attestedDefaultsKey),
              let keyId = UserDefaults.standard.string(forKey: keyIdDefaultsKey),
              !keyId.isEmpty
        else { return nil }
        return keyId
    }

    /// One-time App Attest registration (generateKey → attestKey → /attest/register).
    static func prepareRegistration(backend: BackendService) async {
        guard isSupported else { return }
        try? await ensureRegistered(backend: backend)
    }

    /// Per-request assertion for an encoded lookup body (challenge + body hash).
    static func payload(for encodedBody: Data, backend: BackendService) async -> AppAttestPayload? {
        guard isSupported, let keyId = registeredDeviceId else { return nil }
        do {
            let challenge = try await backend.attestChallenge()
            let hash = clientDataHash(challenge: challenge, body: encodedBody)
            let assertion = try await generateAssertion(keyId: keyId, clientDataHash: hash)
            return AppAttestPayload(
                deviceId: keyId,
                assertion: assertion.base64EncodedString(),
                clientDataHash: hash.base64EncodedString()
            )
        } catch {
            return nil
        }
    }

    // MARK: Registration

    private static func ensureRegistered(backend: BackendService) async throws {
        if registeredDeviceId != nil { return }
        let keyId = try await generateKey()
        UserDefaults.standard.set(keyId, forKey: keyIdDefaultsKey)

        let challenge = try await backend.attestChallenge()
        let hash = clientDataHash(challenge: challenge, body: Data())
        let attestation = try await attestKey(keyId: keyId, clientDataHash: hash)
        try await backend.registerAttestation(
            keyId: keyId,
            attestation: attestation.base64EncodedString(),
            challenge: challenge.base64EncodedString()
        )
        UserDefaults.standard.set(true, forKey: attestedDefaultsKey)
    }

    private static func clientDataHash(challenge: Data, body: Data) -> Data {
        var combined = Data()
        combined.append(challenge)
        combined.append(body)
        return Data(SHA256.hash(data: combined))
    }

    // MARK: DeviceCheck wrappers

    private static func generateKey() async throws -> String {
        #if canImport(DeviceCheck) && os(iOS)
        try await withCheckedThrowingContinuation { cont in
            DCAppAttestService.shared.generateKey { keyId, error in
                if let error { cont.resume(throwing: error); return }
                guard let keyId else {
                    cont.resume(throwing: AppAttestError.missingKeyId)
                    return
                }
                cont.resume(returning: keyId)
            }
        }
        #else
        throw AppAttestError.unsupported
        #endif
    }

    private static func attestKey(keyId: String, clientDataHash: Data) async throws -> Data {
        #if canImport(DeviceCheck) && os(iOS)
        try await withCheckedThrowingContinuation { cont in
            DCAppAttestService.shared.attestKey(keyId, clientDataHash: clientDataHash) { object, error in
                if let error { cont.resume(throwing: error); return }
                guard let object else {
                    cont.resume(throwing: AppAttestError.missingAttestation)
                    return
                }
                cont.resume(returning: object)
            }
        }
        #else
        throw AppAttestError.unsupported
        #endif
    }

    private static func generateAssertion(keyId: String, clientDataHash: Data) async throws -> Data {
        #if canImport(DeviceCheck) && os(iOS)
        try await withCheckedThrowingContinuation { cont in
            DCAppAttestService.shared.generateAssertion(keyId, clientDataHash: clientDataHash) { object, error in
                if let error { cont.resume(throwing: error); return }
                guard let object else {
                    cont.resume(throwing: AppAttestError.missingAssertion)
                    return
                }
                cont.resume(returning: object)
            }
        }
        #else
        throw AppAttestError.unsupported
        #endif
    }
}

private enum AppAttestError: Error {
    case unsupported
    case missingKeyId
    case missingAttestation
    case missingAssertion
}
