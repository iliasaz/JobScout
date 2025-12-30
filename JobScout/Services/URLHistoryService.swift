//
//  URLHistoryService.swift
//  JobScout
//
//  Created by Ilia Sazonov on 12/29/25.
//

import Foundation

/// Service for managing URL history persistence using the database
actor URLHistoryService {
    static let shared = URLHistoryService()

    private let repository: JobRepository

    private init(repository: JobRepository = JobRepository()) {
        self.repository = repository
    }

    /// Get all saved URLs, most recent first
    func getHistory() async -> [String] {
        do {
            let sources = try await repository.getSourcesByRecentUsage(limit: 20)
            return sources.map { $0.url }
        } catch {
            // Return empty array on error
            return []
        }
    }

    /// Get all saved sources with metadata, most recent first
    func getSources() async -> [JobSource] {
        do {
            return try await repository.getSourcesByRecentUsage(limit: 20)
        } catch {
            return []
        }
    }

    /// Add a URL to history (creates or updates the source, moving it to top)
    func addURL(_ url: String) async {
        do {
            _ = try await repository.touchSource(url: url)
        } catch {
            // Silently ignore errors
        }
    }

    /// Remove a URL from history (deletes the source and its jobs)
    func removeURL(_ url: String) async {
        do {
            try await repository.deleteSource(url: url)
        } catch {
            // Silently ignore errors
        }
    }

    /// Clear all history (deletes all sources - use with caution!)
    func clearHistory() async {
        do {
            try await repository.deleteAllData()
        } catch {
            // Silently ignore errors
        }
    }
}
