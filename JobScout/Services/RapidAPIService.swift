//
//  RapidAPIService.swift
//  JobScout
//
//  Created by Claude on 1/29/26.
//

import Foundation

/// Errors that can occur during RapidAPI operations
enum RapidAPIError: Error, LocalizedError {
    case noAPIKey
    case invalidResponse
    case apiError(String)
    case networkError(Error)
    case rateLimited
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "RapidAPI key not configured. Please add your API key in Settings."
        case .invalidResponse:
            return "Invalid response from RapidAPI."
        case .apiError(let message):
            return "RapidAPI error: \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .rateLimited:
            return "Rate limited. Please wait before making another request."
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        }
    }
}

/// Actor-based service for RapidAPI Fresh LinkedIn Scraper
actor RapidAPIService {
    static let shared = RapidAPIService()

    private let baseURL = "https://fresh-linkedin-scraper-api.p.rapidapi.com/api/v1/job"
    private let apiHost = "fresh-linkedin-scraper-api.p.rapidapi.com"
    private let keychainService = KeychainService.shared
    private var lastRequestTime: Date?
    private let minimumRequestInterval: TimeInterval = 1.0

    private init() {}

    // MARK: - Public API

    /// Search for jobs using the RapidAPI Fresh LinkedIn Scraper
    func searchJobs(params: RapidAPISearchParams) async throws -> RapidAPISearchResponse {
        try await enforceRateLimit()

        guard let apiKey = try await keychainService.getRapidAPIKey(), !apiKey.isEmpty else {
            throw RapidAPIError.noAPIKey
        }

        var components = URLComponents(string: baseURL + "/search")
        components?.queryItems = params.buildQueryItems()

        guard let url = components?.url else {
            throw RapidAPIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue(apiHost, forHTTPHeaderField: "x-rapidapi-host")
        request.setValue(apiKey, forHTTPHeaderField: "x-rapidapi-key")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw RapidAPIError.invalidResponse
            }

            if httpResponse.statusCode == 429 {
                throw RapidAPIError.rateLimited
            }

            if httpResponse.statusCode != 200 {
                if let errorResponse = try? JSONDecoder().decode(RapidAPISearchResponse.self, from: data),
                   let errorMessage = errorResponse.error ?? errorResponse.message {
                    throw RapidAPIError.apiError(errorMessage)
                }
                throw RapidAPIError.apiError("HTTP \(httpResponse.statusCode)")
            }

            let searchResponse = try JSONDecoder().decode(RapidAPISearchResponse.self, from: data)

            if let error = searchResponse.error ?? searchResponse.message {
                if searchResponse.data != nil {
                    // Has data but also a message — not an error
                    return searchResponse
                }
                throw RapidAPIError.apiError(error)
            }

            return searchResponse
        } catch let error as RapidAPIError {
            throw error
        } catch let error as DecodingError {
            throw RapidAPIError.decodingError(error)
        } catch {
            throw RapidAPIError.networkError(error)
        }
    }

    /// Fetch detailed job information by job ID
    func fetchJobDetails(jobId: String) async throws -> RapidAPIJobDetails {
        try await enforceRateLimit()

        guard let apiKey = try await keychainService.getRapidAPIKey(), !apiKey.isEmpty else {
            throw RapidAPIError.noAPIKey
        }

        var components = URLComponents(string: baseURL + "/details/\(jobId)")

        guard let url = components?.url else {
            throw RapidAPIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue(apiHost, forHTTPHeaderField: "x-rapidapi-host")
        request.setValue(apiKey, forHTTPHeaderField: "x-rapidapi-key")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw RapidAPIError.invalidResponse
            }

            if httpResponse.statusCode == 429 {
                throw RapidAPIError.rateLimited
            }

            if httpResponse.statusCode != 200 {
                if let errorResponse = try? JSONDecoder().decode(RapidAPIJobDetailsResponse.self, from: data),
                   let errorMessage = errorResponse.error ?? errorResponse.message {
                    throw RapidAPIError.apiError(errorMessage)
                }
                throw RapidAPIError.apiError("HTTP \(httpResponse.statusCode)")
            }

            let detailsResponse = try JSONDecoder().decode(RapidAPIJobDetailsResponse.self, from: data)

            if let error = detailsResponse.error ?? detailsResponse.message {
                if detailsResponse.data != nil {
                    return detailsResponse.data!
                }
                throw RapidAPIError.apiError(error)
            }

            guard let details = detailsResponse.data else {
                throw RapidAPIError.invalidResponse
            }

            return details
        } catch let error as RapidAPIError {
            throw error
        } catch let error as DecodingError {
            throw RapidAPIError.decodingError(error)
        } catch {
            throw RapidAPIError.networkError(error)
        }
    }

    /// Check if the API key is configured
    func hasAPIKey() async -> Bool {
        await keychainService.hasRapidAPIKey()
    }

    // MARK: - Private Helpers

    /// Enforce rate limiting between requests
    private func enforceRateLimit() async throws {
        if let lastRequest = lastRequestTime {
            let elapsed = Date().timeIntervalSince(lastRequest)
            if elapsed < minimumRequestInterval {
                let waitTime = minimumRequestInterval - elapsed
                try await Task.sleep(for: .seconds(waitTime))
            }
        }
        lastRequestTime = Date()
    }
}
