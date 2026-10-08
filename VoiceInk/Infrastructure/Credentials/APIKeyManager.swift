import Foundation
import os

/// Manages API keys using secure Keychain storage.
final class APIKeyManager {
    static let shared = APIKeyManager()

    private let logger = Logger(subsystem: "com.qaws81877.sulsul", category: "APIKeyManager")
    private let keychain = KeychainService.shared

    /// Provider to Keychain identifier mapping. Keys stay on this Mac and are not iCloud-synced.
    private static let providerToKeychainKey: [String: String] = [
        "groq": "groqAPIKey",
        "deepgram": "deepgramAPIKey",
        "cerebras": "cerebrasAPIKey",
        "gemini": "geminiAPIKey",
        "mistral": "mistralAPIKey",
        "elevenlabs": "elevenLabsAPIKey",
        "soniox": "sonioxAPIKey",
        "speechmatics": "speechmaticsAPIKey",
        "assemblyai": "assemblyAIAPIKey",
        "xai": "xaiAPIKey",
        "cartesia": "cartesiaAPIKey",
        "openai": "openAIAPIKey",
        "anthropic": "anthropicAPIKey",
        "openrouter": "openRouterAPIKey",
    ]

    private init() {}

    // MARK: - Standard Provider API Keys

    /// Saves an API key for a provider.
    @discardableResult
    func saveAPIKey(_ key: String, forProvider provider: String) -> Bool {
        let keyIdentifier = keychainIdentifier(forProvider: provider)
        let success = saveLocal(key, forKey: keyIdentifier)
        if success {
            logger.info(
                "Saved API key for provider: \(provider, privacy: .public) with key: \(keyIdentifier, privacy: .public)"
            )
        }
        return success
    }

    /// Retrieves an API key for a provider.
    func getAPIKey(forProvider provider: String) -> String? {
        let keyIdentifier = keychainIdentifier(forProvider: provider)
        return readLocal(forKey: keyIdentifier)
    }

    /// Deletes an API key for a provider.
    @discardableResult
    func deleteAPIKey(forProvider provider: String) -> Bool {
        let keyIdentifier = keychainIdentifier(forProvider: provider)
        let success = deleteLocal(forKey: keyIdentifier)
        if success {
            logger.info("Deleted API key for provider: \(provider, privacy: .public)")
        }
        return success
    }

    /// Checks if an API key exists for a provider.
    func hasAPIKey(forProvider provider: String) -> Bool {
        let keyIdentifier = keychainIdentifier(forProvider: provider)
        return existsLocal(forKey: keyIdentifier)
    }

    // MARK: - Custom Model API Keys

    /// Saves an API key for a custom model.
    @discardableResult
    func saveCustomModelAPIKey(_ key: String, forModelId modelId: UUID) -> Bool {
        let keyIdentifier = customModelKeyIdentifier(for: modelId)
        let success = saveLocal(key, forKey: keyIdentifier)
        if success {
            logger.info("Saved API key for custom model: \(modelId.uuidString, privacy: .public)")
        }
        return success
    }

    /// Retrieves an API key for a custom model.
    func getCustomModelAPIKey(forModelId modelId: UUID) -> String? {
        let keyIdentifier = customModelKeyIdentifier(for: modelId)
        return readLocal(forKey: keyIdentifier)
    }

    /// Deletes an API key for a custom model.
    @discardableResult
    func deleteCustomModelAPIKey(forModelId modelId: UUID) -> Bool {
        let keyIdentifier = customModelKeyIdentifier(for: modelId)
        let success = deleteLocal(forKey: keyIdentifier)
        if success {
            logger.info("Deleted API key for custom model: \(modelId.uuidString, privacy: .public)")
        }
        return success
    }

    // MARK: - Custom AI Provider API Keys

    @discardableResult
    func saveCustomAIProviderAPIKey(_ key: String, forProviderId providerId: UUID) -> Bool {
        let keyIdentifier = customAIProviderKeyIdentifier(for: providerId)
        let success = saveLocal(key, forKey: keyIdentifier)
        if success {
            logger.info("Saved API key for custom AI provider: \(providerId.uuidString, privacy: .public)")
        }
        return success
    }

    func getCustomAIProviderAPIKey(forProviderId providerId: UUID) -> String? {
        let keyIdentifier = customAIProviderKeyIdentifier(for: providerId)
        return readLocal(forKey: keyIdentifier)
    }

    @discardableResult
    func deleteCustomAIProviderAPIKey(forProviderId providerId: UUID) -> Bool {
        let keyIdentifier = customAIProviderKeyIdentifier(for: providerId)
        let success = deleteLocal(forKey: keyIdentifier)
        if success {
            logger.info("Deleted API key for custom AI provider: \(providerId.uuidString, privacy: .public)")
        }
        return success
    }

    // MARK: - Key Identifier Helpers

    /// Returns Keychain identifier for a provider (case-insensitive).
    private func keychainIdentifier(forProvider provider: String) -> String {
        let lowercased = provider.lowercased()
        if let mapped = Self.providerToKeychainKey[lowercased] {
            return mapped
        }
        return "\(lowercased)APIKey"
    }

    /// Generates Keychain identifier for custom model API key.
    private func customModelKeyIdentifier(for modelId: UUID) -> String {
        "customModel_\(modelId.uuidString)_APIKey"
    }

    private func customAIProviderKeyIdentifier(for providerId: UUID) -> String {
        "customAIProvider_\(providerId.uuidString)_APIKey"
    }

    /// This-device Keychain only. `kSecAttrSynchronizable` is left unset so the item is not synced.
    @discardableResult
    private func saveLocal(_ value: String, forKey key: String) -> Bool {
        keychain.save(
            value,
            forKey: key,
            syncable: false,
            accessibility: .afterFirstUnlockThisDeviceOnly
        )
    }

    private func readLocal(forKey key: String) -> String? {
        if let value = keychain.getString(forKey: key, syncable: false) {
            return value
        }

        #if LOCAL_BUILD
            return nil
        #else
            guard let legacy = keychain.getString(forKey: key, syncable: true) else {
                return nil
            }
            _ = saveLocal(legacy, forKey: key)
            _ = keychain.delete(forKey: key, syncable: true)
            return legacy
        #endif
    }

    private func existsLocal(forKey key: String) -> Bool {
        if keychain.exists(forKey: key, syncable: false) {
            return true
        }
        #if LOCAL_BUILD
            return false
        #else
            return readLocal(forKey: key) != nil
        #endif
    }

    @discardableResult
    private func deleteLocal(forKey key: String) -> Bool {
        let removed = keychain.delete(forKey: key, syncable: false)
        #if LOCAL_BUILD
            return removed
        #else
            let removedLegacy = keychain.delete(forKey: key, syncable: true)
            return removed && removedLegacy
        #endif
    }
}
