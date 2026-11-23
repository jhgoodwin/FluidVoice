import Foundation

@main
enum ProviderVerificationGateTests {
    /// Mirrors ModelRepository.isLocalEndpoint (localhost / private IPv4 hosts).
    static func isLocalEndpoint(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString), let host = url.host else { return false }
        let hostLower = host.lowercased()
        if hostLower == "localhost" || hostLower == "127.0.0.1" { return true }
        if hostLower.hasPrefix("127.") || hostLower.hasPrefix("10.") || hostLower.hasPrefix("192.168.") { return true }
        if hostLower.hasPrefix("172.") {
            let components = hostLower.split(separator: ".")
            if components.count >= 2, let second = Int(components[1]), second >= 16, second <= 31 { return true }
        }
        return false
    }

    static func gate(
        hasName: Bool = true,
        baseURL: String = "https://api.example.com/v1",
        apiKey: String = "secret",
        models: [String] = ["model-a"],
        selectedModel: String = "model-a"
    ) -> ProviderVerificationEligibility {
        ProviderVerificationEligibility(
            hasName: hasName,
            baseURL: baseURL,
            apiKey: apiKey,
            models: models,
            selectedModel: selectedModel,
            isLocalEndpoint: self.isLocalEndpoint
        )
    }

    static func main() {
        // Local endpoint + non-empty baseURL needs no API key.
        let local = gate(baseURL: "http://localhost:11434/v1", apiKey: "")
        precondition(local.isLocal && local.canFetchModels && local.canVerify)
        precondition(gate(baseURL: "http://192.168.1.10:8080/v1", apiKey: "").isLocal)
        precondition(gate(baseURL: "http://10.0.0.5/v1", apiKey: "").isLocal)
        precondition(gate(baseURL: "http://172.16.0.2/v1", apiKey: "").isLocal)
        precondition(!gate(baseURL: "https://172.32.0.2/v1", apiKey: "").isLocal)

        // Remote endpoint requires an API key.
        precondition(!gate(apiKey: "").canFetchModels, "Remote endpoint without a key must not fetch")
        precondition(gate(apiKey: "key").canFetchModels)
        precondition(gate(apiKey: "   ").canFetchModels == false, "Whitespace key counts as missing")

        // A missing provider name blocks everything.
        precondition(!gate(hasName: false).canFetchModels)
        precondition(!gate(hasName: false).canVerify)

        // Empty/whitespace baseURL blocks fetching even for local hosts.
        precondition(!gate(baseURL: "").canFetchModels)
        precondition(!gate(baseURL: "   ").canFetchModels)
        precondition(!gate(baseURL: "   ").isLocal)

        // canVerify needs models, a trimmed non-empty model selection and fetchability.
        precondition(!gate(models: []).canVerify)
        precondition(gate(models: []).canFetchModels, "Model list is not required for fetching")
        precondition(!gate(selectedModel: "").canVerify)
        precondition(!gate(selectedModel: "   ").canVerify)
        precondition(gate(selectedModel: "  model-b  ").canVerify, "Trimmed selection counts")
        precondition(!gate(apiKey: "").canVerify, "No key on a remote endpoint blocks verify too")

        // Per-item evaluation: eligibility must reflect each card's own inputs.
        // A is a remote keyless provider; B is a local provider with URL and model.
        let providerA = gate(
            baseURL: "https://api.remote.com/v1", apiKey: "",
            models: ["m1"], selectedModel: "m1")
        let providerB = gate(
            baseURL: "http://127.0.0.1:1234/v1", apiKey: "",
            models: ["m2"], selectedModel: "m2")
        precondition(!providerA.canVerify && providerB.canVerify,
                     "Provider B's local endpoint must not inherit A's remote requirements")
        precondition(providerA.isLocal != providerB.isLocal)
        precondition(providerB == gate(
            baseURL: "http://127.0.0.1:1234/v1", apiKey: "",
            models: ["m2"], selectedModel: "m2"), "Same per-item inputs must give equal eligibility")

        // A keyless remote provider cannot verify even when it shares the draft's model list.
        let providerC = gate(
            baseURL: "https://api.other.com/v1", apiKey: "",
            models: ["m3"], selectedModel: "m3")
        precondition(!providerC.canFetchModels && !providerC.canVerify)

        print("PASS: local/remote endpoint rules, key/name/URL/model gating, and per-item independence")
    }
}
