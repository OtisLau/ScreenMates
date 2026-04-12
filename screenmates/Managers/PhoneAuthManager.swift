import Foundation
import Combine
import CryptoKit

/// Manages phone verification state and local identity storage.
/// The source of truth for whether the user has completed phone auth
/// and contacts discovery.
class PhoneAuthManager: ObservableObject {
    static let shared = PhoneAuthManager()

    @Published private(set) var isPhoneVerified: Bool
    @Published private(set) var contactsHandled: Bool
    @Published private(set) var phoneNumberE164: String
    @Published private(set) var phoneHash: String
    @Published private(set) var authProviderUserID: String

    private let defaults = UserDefaults.standard

    private init() {
        isPhoneVerified    = defaults.bool(forKey: AppConstants.Keys.isPhoneVerified)
        contactsHandled    = defaults.bool(forKey: AppConstants.Keys.contactsHandled)
        phoneNumberE164    = defaults.string(forKey: AppConstants.Keys.phoneNumberE164) ?? ""
        phoneHash          = defaults.string(forKey: AppConstants.Keys.phoneHash) ?? ""
        authProviderUserID = defaults.string(forKey: AppConstants.Keys.authProviderUserID) ?? ""
    }

    /// Call this once OTP verification succeeds. Persists identity locally
    /// and writes phone_hash to CloudKit via CloudKitManager.updateMyProfile.
    func markPhoneVerified(e164: String, providerUserID: String, syncProfile: Bool = true) {
        let hash = Self.sha256(e164)
        phoneNumberE164    = e164
        phoneHash          = hash
        authProviderUserID = providerUserID
        isPhoneVerified    = true

        defaults.set(e164,           forKey: AppConstants.Keys.phoneNumberE164)
        defaults.set(hash,           forKey: AppConstants.Keys.phoneHash)
        defaults.set(providerUserID, forKey: AppConstants.Keys.authProviderUserID)
        defaults.set(true,           forKey: AppConstants.Keys.isPhoneVerified)

        // Push phone_hash to the user's CloudKit UserProfile so friends can discover them.
        // CloudKitManager.saveProfileToCloud reads PhoneAuthManager.shared.phoneHash directly.
        if syncProfile {
            CloudKitManager.shared.updateMyProfile(completion: nil)
        }
    }

    /// Call after contacts permission is handled (granted or explicitly skipped).
    func markContactsHandled() {
        contactsHandled = true
        defaults.set(true, forKey: AppConstants.Keys.contactsHandled)
    }

    func resetAuthState() {
        isPhoneVerified    = false
        contactsHandled    = false
        phoneNumberE164    = ""
        phoneHash          = ""
        authProviderUserID = ""

        defaults.removeObject(forKey: AppConstants.Keys.phoneNumberE164)
        defaults.removeObject(forKey: AppConstants.Keys.phoneHash)
        defaults.removeObject(forKey: AppConstants.Keys.authProviderUserID)
        defaults.set(false, forKey: AppConstants.Keys.isPhoneVerified)
        defaults.set(false, forKey: AppConstants.Keys.contactsHandled)
    }

    // MARK: - Helpers

    /// SHA-256 of the input string, returned as lowercase hex.
    static func sha256(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Normalize a raw phone number string to E.164 format.
    /// Handles 10-digit US numbers and 11-digit numbers starting with 1.
    /// Returns nil if the number can't be normalized.
    static func normalizeToE164(_ raw: String, countryCode: String = "+1") -> String? {
        let digits = raw.filter { $0.isNumber }
        if digits.count == 11, digits.hasPrefix("1") { return "+\(digits)" }
        if digits.count == 10 { return "\(countryCode)\(digits)" }
        return nil
    }
}

enum PhoneAuthProxyError: LocalizedError {
    case missingWorkerURL
    case invalidResponse
    case server(String)
    case verificationNotApproved

    var errorDescription: String? {
        switch self {
        case .missingWorkerURL:
            return "Phone verification is not configured yet."
        case .invalidResponse:
            return "The verification server returned an invalid response."
        case .server(let message):
            return message
        case .verificationNotApproved:
            return "That code didn't work. Please try again."
        }
    }
}

struct PhoneAuthProxyClient {
    private struct VerificationRequest: Encodable {
        let to: String
        let code: String?
    }

    private struct VerificationResponse: Decodable {
        let ok: Bool?
        let sid: String?
        let status: String?
        let valid: Bool?
        let error: String?
    }

    private var baseURL: URL {
        get throws {
            guard let url = URL(string: AppConstants.phoneAuthWorkerBaseURL),
                  !AppConstants.phoneAuthWorkerBaseURL.isEmpty
            else { throw PhoneAuthProxyError.missingWorkerURL }
            return url
        }
    }

    func startVerification(to e164: String) async throws {
        _ = try await post("start-verification", body: VerificationRequest(to: e164, code: nil))
    }

    func checkVerification(to e164: String, code: String) async throws -> String {
        let response = try await post("check-verification", body: VerificationRequest(to: e164, code: code))
        guard response.valid == true || response.status == "approved" else {
            throw PhoneAuthProxyError.verificationNotApproved
        }
        return response.sid ?? "twilio-\(PhoneAuthManager.sha256(e164).prefix(12))"
    }

    private func post(_ path: String, body: VerificationRequest) async throws -> VerificationResponse {
        let url = try baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConstants.phoneAuthWorkerSecret, forHTTPHeaderField: "X-App-Secret")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, urlResponse) = try await URLSession.shared.data(for: request)
        guard let httpResponse = urlResponse as? HTTPURLResponse else {
            throw PhoneAuthProxyError.invalidResponse
        }

        let decoded = try? JSONDecoder().decode(VerificationResponse.self, from: data)
        if !(200..<300).contains(httpResponse.statusCode) {
            throw PhoneAuthProxyError.server(decoded?.error ?? "Phone verification failed.")
        }

        guard let decoded else { throw PhoneAuthProxyError.invalidResponse }
        if decoded.ok == false {
            throw PhoneAuthProxyError.server(decoded.error ?? "Phone verification failed.")
        }
        return decoded
    }
}
