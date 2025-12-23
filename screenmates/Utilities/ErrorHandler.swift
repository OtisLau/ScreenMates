import Foundation

/// Centralized app error types (used for CloudKit + user-facing error messaging).
enum ErrorHandler {
    enum AppError: Error, Equatable, Identifiable, LocalizedError {
        case networkError
        case groupNotFound
        case cloudKitError(String)
        case unknown

        var id: String { localizedDescription }

        var errorDescription: String? {
            switch self {
            case .networkError:
                return "Network error. Please check your connection and try again."
            case .groupNotFound:
                return "Group not found. Double-check the code and try again."
            case .cloudKitError(let message):
                return message
            case .unknown:
                return "Something went wrong. Please try again."
            }
        }
    }
}
