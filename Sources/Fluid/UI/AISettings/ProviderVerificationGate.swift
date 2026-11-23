import Foundation

/// Whether a provider card may fetch its model list and run model verification.
/// All inputs are resolved per provider item, not from the selected-provider draft.
struct ProviderVerificationEligibility: Sendable, Equatable {
    let isLocal: Bool
    let canFetchModels: Bool
    let canVerify: Bool

    init(
        hasName: Bool,
        baseURL: String,
        apiKey: String,
        models: [String],
        selectedModel: String,
        isLocalEndpoint: (String) -> Bool
    ) {
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasAPIKey = !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasModels = !models.isEmpty
        let hasModel = !selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        self.isLocal = isLocalEndpoint(trimmedURL)
        self.canFetchModels = hasName && (self.isLocal ? !trimmedURL.isEmpty : (hasAPIKey && !trimmedURL.isEmpty))
        self.canVerify = hasModels && hasModel && self.canFetchModels
    }
}
