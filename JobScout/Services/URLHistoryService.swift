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

    /// Default job source URLs to populate on first run
    static let defaultURLs = [
        "https://github.com/jobright-ai/2026-Software-Engineer-New-Grad/blob/master/README.md",
        "https://github.com/SimplifyJobs/Summer2026-Internships/blob/dev/README.md",
        "https://github.com/SimplifyJobs/New-Grad-Positions/blob/dev/README.md"
    ]

    private init(repository: JobRepository = JobRepository()) {
        self.repository = repository
    }

    /// Populate default URLs if no sources exist
    func populateDefaultsIfNeeded() async {
        do {
            let sources = try await repository.getSourcesByRecentUsage(limit: 1)
            if sources.isEmpty {
                // No sources exist, populate defaults
                for url in Self.defaultURLs {
                    _ = try await repository.touchSource(url: url)
                }
            }
        } catch {
            // Silently ignore errors
        }
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
