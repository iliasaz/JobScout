//
//  ScrapingDogService.swift
//  JobScout
//
//  Created by Claude on 1/25/26.
//

import Foundation

/// Errors that can occur during ScrapingDog API operations
enum ScrapingDogError: Error, LocalizedError {
    case noAPIKey
    case invalidResponse
    case apiError(String)
    case networkError(Error)
    case rateLimited
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "ScrapingDog API key not configured. Please add your API key in Settings."
        case .invalidResponse:
            return "Invalid response from ScrapingDog API."
        case .apiError(let message):
            return "ScrapingDog API error: \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .rateLimited:
            return "Rate limited. Please wait before making another request."
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        }
    }
}

/// Actor-based service for ScrapingDog LinkedIn job search API
actor ScrapingDogService {
    static let shared = ScrapingDogService()

    private let baseURL = "https://api.scrapingdog.com/jobs/"
    private let keychainService = KeychainService.shared
    private var lastRequestTime: Date?
    private let minimumRequestInterval: TimeInterval = 1.0  // Rate limiting: 1 second between requests

    private init() {}

    // MARK: - Public API

    /// Search for jobs using the ScrapingDog LinkedIn API
    /// - Parameter params: Search parameters
    /// - Returns: Array of ScrapingDogJob results
    func searchJobs(params: ScrapingDogSearchParams) async throws -> [ScrapingDogJob] {
        try await enforceRateLimit()

        guard let apiKey = try await keychainService.getScrapingDogAPIKey(), !apiKey.isEmpty else {
            throw ScrapingDogError.noAPIKey
        }

        var components = URLComponents(string: baseURL)
        components?.queryItems = params.buildQueryItems(apiKey: apiKey)

        guard let url = components?.url else {
            throw ScrapingDogError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ScrapingDogError.invalidResponse
            }

            if httpResponse.statusCode == 429 {
                throw ScrapingDogError.rateLimited
            }

            if httpResponse.statusCode != 200 {
                // Try to extract error message from response
                if let errorResponse = try? JSONDecoder().decode(ScrapingDogSearchResponse.self, from: data),
                   let errorMessage = errorResponse.error ?? errorResponse.message {
                    throw ScrapingDogError.apiError(errorMessage)
                }
                throw ScrapingDogError.apiError("HTTP \(httpResponse.statusCode)")
            }

            // Try to decode as array first (direct jobs array response)
            if let jobs = try? JSONDecoder().decode([ScrapingDogJob].self, from: data) {
                return jobs
            }

            // Otherwise try the wrapped response format
            let searchResponse = try JSONDecoder().decode(ScrapingDogSearchResponse.self, from: data)

            if let error = searchResponse.error ?? searchResponse.message {
                throw ScrapingDogError.apiError(error)
            }

            return searchResponse.jobs ?? []
        } catch let error as ScrapingDogError {
            throw error
        } catch let error as DecodingError {
            throw ScrapingDogError.decodingError(error)
        } catch {
            throw ScrapingDogError.networkError(error)
        }
    }

    /// Fetch detailed job information by job ID
    /// - Parameters:
    ///   - jobId: The LinkedIn job ID
    ///   - existingJob: Optional existing JobPosting to enrich
    /// - Returns: Enriched JobPosting with description and apply link
    func fetchJobDetails(jobId: String, enriching existingJob: JobPosting? = nil) async throws -> JobPosting {
        try await enforceRateLimit()

        guard let apiKey = try await keychainService.getScrapingDogAPIKey(), !apiKey.isEmpty else {
            throw ScrapingDogError.noAPIKey
        }

        var components = URLComponents(string: baseURL)
        components?.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "job_id", value: jobId)
        ]

        guard let url = components?.url else {
            throw ScrapingDogError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ScrapingDogError.invalidResponse
            }

            if httpResponse.statusCode == 429 {
                throw ScrapingDogError.rateLimited
            }

            if httpResponse.statusCode != 200 {
                if let errorResponse = try? JSONDecoder().decode(ScrapingDogDetailsResponse.self, from: data),
                   let errorMessage = errorResponse.error ?? errorResponse.message {
                    throw ScrapingDogError.apiError(errorMessage)
                }
                throw ScrapingDogError.apiError("HTTP \(httpResponse.statusCode)")
            }

            // Try to decode as array first (direct details array response)
            if let details = try? JSONDecoder().decode([ScrapingDogJobDetails].self, from: data),
               let firstDetail = details.first {
                if let existingJob = existingJob {
                    return firstDetail.enrichJobPosting(existingJob)
                } else {
                    // Create a basic JobPosting from details
                    return JobPosting(
                        company: firstDetail.company_name ?? "Unknown Company",
                        role: firstDetail.job_position ?? "Unknown Position",
                        location: firstDetail.job_location ?? "Not specified",
                        companyWebsite: firstDetail.company_profile,
                        companyLink: firstDetail.job_apply_link,
                        aggregatorLink: firstDetail.job_link,
                        aggregatorName: "LinkedIn",
                        datePosted: firstDetail.job_posting_date,
                        descriptionText: firstDetail.job_description
                    )
                }
            }

            // Try wrapped response format
            let detailsResponse = try JSONDecoder().decode(ScrapingDogDetailsResponse.self, from: data)

            if let error = detailsResponse.error ?? detailsResponse.message {
                throw ScrapingDogError.apiError(error)
            }

            guard let details = detailsResponse.job_details?.first else {
                throw ScrapingDogError.invalidResponse
            }

            if let existingJob = existingJob {
                return details.enrichJobPosting(existingJob)
            } else {
                return JobPosting(
                    company: details.company_name ?? "Unknown Company",
                    role: details.job_position ?? "Unknown Position",
                    location: details.job_location ?? "Not specified",
                    companyWebsite: details.company_profile,
                    companyLink: details.job_apply_link,
                    aggregatorLink: details.job_link,
                    aggregatorName: "LinkedIn",
                    datePosted: details.job_posting_date,
                    descriptionText: details.job_description
                )
            }
        } catch let error as ScrapingDogError {
            throw error
        } catch let error as DecodingError {
            throw ScrapingDogError.decodingError(error)
        } catch {
            throw ScrapingDogError.networkError(error)
        }
    }

    /// Check if the API key is configured
    func hasAPIKey() async -> Bool {
        await keychainService.hasScrapingDogAPIKey()
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
