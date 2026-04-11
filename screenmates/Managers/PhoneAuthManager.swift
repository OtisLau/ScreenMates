import Foundation
import CryptoKit

/// Manages phone verification state and local identity storage.
/// The source of truth for whether the user has completed phone auth
/// and contacts discovery.
@MainActor
final class PhoneAuthManager: ObservableObject {
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
    func markPhoneVerified(e164: String, providerUserID: String) {
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
        CloudKitManager.shared.phoneHash = hash
        CloudKitManager.shared.updateMyProfile(completion: nil)
    }

    /// Call after contacts permission is handled (granted or explicitly skipped).
    func markContactsHandled() {
        contactsHandled = true
        defaults.set(true, forKey: AppConstants.Keys.contactsHandled)
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
