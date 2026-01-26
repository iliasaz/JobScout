//
//  KeychainService.swift
//  JobScout
//
//  Created by Ilia Sazonov on 12/29/25.
//

import Foundation
import Security

/// Error types for Keychain operations
enum KeychainError: Error, LocalizedError {
    case itemNotFound
    case duplicateItem
    case unexpectedData
    case unhandledError(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "The specified item could not be found in the keychain."
        case .duplicateItem:
            return "The item already exists in the keychain."
        case .unexpectedData:
            return "The keychain returned unexpected data."
        case .unhandledError(let status):
            return "An unhandled keychain error occurred: \(status)"
        }
    }
}

/// Service for securely storing and retrieving API keys in the macOS Keychain
actor KeychainService {
    static let shared = KeychainService()

    private let service = "com.jobscout.api"
    private let openRouterAccount = "openrouter-api-key"
    private let scrapingDogAccount = "scrapingdog-api-key"

    private init() {}

    // MARK: - OpenRouter API Key

    /// Save the OpenRouter API key to the keychain
    /// - Parameter apiKey: The API key to save
    func saveOpenRouterAPIKey(_ apiKey: String) throws {
        try save(apiKey: apiKey, account: openRouterAccount)
    }

    /// Retrieve the OpenRouter API key from the keychain
    /// - Returns: The stored API key, or nil if not found
    func getOpenRouterAPIKey() throws -> String? {
        try retrieve(account: openRouterAccount)
    }

    /// Delete the OpenRouter API key from the keychain
    func deleteOpenRouterAPIKey() throws {
        try delete(account: openRouterAccount)
    }

    /// Check if an OpenRouter API key is stored
    /// - Returns: True if an API key is stored
    func hasOpenRouterAPIKey() -> Bool {
        do {
            return try getOpenRouterAPIKey() != nil
        } catch {
            return false
        }
    }

    // MARK: - ScrapingDog API Key

    /// Save the ScrapingDog API key to the keychain
    /// - Parameter apiKey: The API key to save
    func saveScrapingDogAPIKey(_ apiKey: String) throws {
        try save(apiKey: apiKey, account: scrapingDogAccount)
    }

    /// Retrieve the ScrapingDog API key from the keychain
    /// - Returns: The stored API key, or nil if not found
    func getScrapingDogAPIKey() throws -> String? {
        try retrieve(account: scrapingDogAccount)
    }

    /// Delete the ScrapingDog API key from the keychain
    func deleteScrapingDogAPIKey() throws {
        try delete(account: scrapingDogAccount)
    }

    /// Check if a ScrapingDog API key is stored
    /// - Returns: True if an API key is stored
    func hasScrapingDogAPIKey() -> Bool {
        do {
            return try getScrapingDogAPIKey() != nil
        } catch {
            return false
        }
    }

    // MARK: - Generic Keychain Operations

    /// Save a value to the keychain
    private func save(apiKey: String, account: String) throws {
        guard let data = apiKey.data(using: .utf8) else {
            throw KeychainError.unexpectedData
        }

        // First, try to delete any existing item
        try? delete(account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            if status == errSecDuplicateItem {
                throw KeychainError.duplicateItem
            }
            throw KeychainError.unhandledError(status: status)
        }
    }

    /// Retrieve a value from the keychain
    private func retrieve(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status != errSecItemNotFound else {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.unhandledError(status: status)
        }

        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedData
        }

        return value
    }

    /// Delete a value from the keychain
    private func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledError(status: status)
        }
    }
}
