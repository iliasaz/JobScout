//
//  ScrapingDogModels.swift
//  JobScout
//
//  Created by Claude on 1/25/26.
//

import Foundation

// MARK: - Search Parameters

/// Parameters for ScrapingDog job search API
struct ScrapingDogSearchParams: Sendable {
    var field: String  // Job title/company to search
    var geoid: String?  // Location geoid (optional)
    var page: Int = 1  // Page number (1-indexed)
    var sortBy: SortBy = .relevant  // Sort order
    var jobType: JobType?  // Filter by job type
    var experienceLevel: ExperienceLevel?  // Filter by experience
    var workType: WorkType?  // Filter by work type (remote/onsite)

    /// Sort options for job search
    enum SortBy: String, CaseIterable, Sendable {
        case relevant = "relevant"
        case day = "day"      // Past 24 hours
        case week = "week"    // Past week
        case month = "month"  // Past month

        var displayName: String {
            switch self {
            case .relevant: return "Most Relevant"
            case .day: return "Past 24 Hours"
            case .week: return "Past Week"
            case .month: return "Past Month"
            }
        }
    }

    /// Job type filter
    enum JobType: String, CaseIterable, Sendable {
        case fullTime = "full_time"
        case partTime = "part_time"
        case contract = "contract"
        case temporary = "temporary"
        case volunteer = "volunteer"

        var displayName: String {
            switch self {
            case .fullTime: return "Full-time"
            case .partTime: return "Part-time"
            case .contract: return "Contract"
            case .temporary: return "Temporary"
            case .volunteer: return "Volunteer"
            }
        }
    }

    /// Experience level filter
    enum ExperienceLevel: String, CaseIterable, Sendable {
        case internship = "internship"
        case entryLevel = "entry_level"
        case associate = "associate"
        case midSeniorLevel = "mid_senior_level"
        case director = "director"

        var displayName: String {
            switch self {
            case .internship: return "Internship"
            case .entryLevel: return "Entry Level"
            case .associate: return "Associate"
            case .midSeniorLevel: return "Mid-Senior Level"
            case .director: return "Director"
            }
        }
    }

    /// Work type filter (remote, hybrid, on-site)
    enum WorkType: String, CaseIterable, Sendable {
        case onSite = "at_work"
        case remote = "remote"
        case hybrid = "hybrid"

        var displayName: String {
            switch self {
            case .onSite: return "On-site"
            case .remote: return "Remote"
            case .hybrid: return "Hybrid"
            }
        }
    }

    /// Build URL query parameters for the API request
    func buildQueryItems(apiKey: String) -> [URLQueryItem] {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "field", value: field),
            URLQueryItem(name: "page", value: String(page))
        ]

        if let geoid = geoid, !geoid.isEmpty {
            items.append(URLQueryItem(name: "geoid", value: geoid))
        }

        if sortBy != .relevant {
            items.append(URLQueryItem(name: "sort_by", value: sortBy.rawValue))
        }

        if let jobType = jobType {
            items.append(URLQueryItem(name: "job_type", value: jobType.rawValue))
        }

        if let experienceLevel = experienceLevel {
            items.append(URLQueryItem(name: "exp_level", value: experienceLevel.rawValue))
        }

        if let workType = workType {
            items.append(URLQueryItem(name: "work_type", value: workType.rawValue))
        }

        return items
    }
    
    /// Build a LinkedIn-style URL that encodes all search parameters for persistence
    func toSourceURL() -> String {
        var components = URLComponents(string: "https://www.linkedin.com/jobs/search/")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "keywords", value: field)
        ]
        
        if sortBy != .relevant {
            queryItems.append(URLQueryItem(name: "f_TPR", value: sortBy.rawValue))
        }
        if let geoid = geoid, !geoid.isEmpty {
            queryItems.append(URLQueryItem(name: "geoId", value: geoid))
        }
        if let jobType = jobType {
            queryItems.append(URLQueryItem(name: "f_JT", value: jobType.rawValue))
        }
        if let experienceLevel = experienceLevel {
            queryItems.append(URLQueryItem(name: "f_E", value: experienceLevel.rawValue))
        }
        if let workType = workType {
            queryItems.append(URLQueryItem(name: "f_WT", value: workType.rawValue))
        }
        
        components.queryItems = queryItems
        return components.url?.absoluteString ?? "https://www.linkedin.com/jobs/search/?keywords=\(field)"
    }
    
    /// Create a display name for the search
    func toDisplayName() -> String {
        var parts: [String] = [field]
        
        if let experienceLevel = experienceLevel {
            parts.append(experienceLevel.displayName)
        }
        if let workType = workType {
            parts.append(workType.displayName)
        }
        if let jobType = jobType {
            parts.append(jobType.displayName)
        }
        
        return parts.joined(separator: " • ")
    }
    
    /// Parse search parameters from a persisted URL
    static func fromSourceURL(_ urlString: String) -> ScrapingDogSearchParams? {
        guard let components = URLComponents(string: urlString),
              let queryItems = components.queryItems else {
            return nil
        }
        
        var params = [String: String]()
        for item in queryItems {
            if let value = item.value {
                params[item.name] = value
            }
        }
        
        guard let field = params["keywords"], !field.isEmpty else {
            return nil
        }
        
        return ScrapingDogSearchParams(
            field: field,
            geoid: params["geoId"],
            page: 1,
            sortBy: params["f_TPR"].flatMap { SortBy(rawValue: $0) } ?? .relevant,
            jobType: params["f_JT"].flatMap { JobType(rawValue: $0) },
            experienceLevel: params["f_E"].flatMap { ExperienceLevel(rawValue: $0) },
            workType: params["f_WT"].flatMap { WorkType(rawValue: $0) }
        )
    }
}

// MARK: - API Response Models

/// Response from ScrapingDog job search API
struct ScrapingDogSearchResponse: Codable, Sendable {
    let jobs: [ScrapingDogJob]?
    let error: String?
    let message: String?

    // Some responses have different structures
    enum CodingKeys: String, CodingKey {
        case jobs
        case error
        case message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jobs = try container.decodeIfPresent([ScrapingDogJob].self, forKey: .jobs)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        message = try container.decodeIfPresent(String.self, forKey: .message)
    }
}

/// Single job from search results
struct ScrapingDogJob: Codable, Sendable, Identifiable {
    let job_position: String?
    let job_link: String?
    let job_id: String?
    let company_name: String?
    let company_profile: String?
    let job_location: String?
    let job_posting_date: String?

    var id: String {
        job_id ?? job_link ?? UUID().uuidString
    }

    /// Convert to JobPosting for display and storage
    func toJobPosting() -> JobPosting? {
        guard let company = company_name, !company.isEmpty,
              let role = job_position, !role.isEmpty else {
            return nil
        }

        return JobPosting(
            company: company,
            role: role,
            location: job_location ?? "Not specified",
            companyWebsite: company_profile,
            companyLink: nil,  // Details API provides job_apply_link
            aggregatorLink: job_link,
            aggregatorName: "LinkedIn",
            datePosted: job_posting_date
        )
    }
}

/// Detailed job information from details API
struct ScrapingDogJobDetails: Codable, Sendable {
    let job_position: String?
    let job_link: String?
    let job_id: String?
    let company_name: String?
    let company_profile: String?
    let job_location: String?
    let job_posting_date: String?
    let job_description: String?
    let job_apply_link: String?
    let Seniority_level: String?
    let Employment_type: String?
    let job_function: String?
    let Industries: String?

    enum CodingKeys: String, CodingKey {
        case job_position
        case job_link
        case job_id
        case company_name
        case company_profile
        case job_location
        case job_posting_date
        case job_description
        case job_apply_link
        case Seniority_level
        case Employment_type
        case job_function
        case Industries
    }

    /// Enrich an existing JobPosting with details
    func enrichJobPosting(_ job: JobPosting) -> JobPosting {
        JobPosting(
            persistedId: job.persistedId,
            company: company_name ?? job.company,
            role: job_position ?? job.role,
            location: job_location ?? job.location,
            country: job.country,
            category: job.category,
            companyWebsite: company_profile ?? job.companyWebsite,
            companyLink: job_apply_link ?? job.companyLink,
            aggregatorLink: job_link ?? job.aggregatorLink,
            aggregatorName: job.aggregatorName ?? "LinkedIn",
            datePosted: job_posting_date ?? job.datePosted,
            notes: job.notes,
            isFAANG: job.isFAANG,
            isInternship: job.isInternship,
            lastViewed: job.lastViewed,
            userStatus: job.userStatus,
            statusChangedAt: job.statusChangedAt,
            descriptionText: job_description ?? job.descriptionText,
            analysisStatus: job.analysisStatus,
            analysisError: job.analysisError,
            salaryDisplay: job.salaryDisplay
        )
    }
}

/// Response from ScrapingDog job details API
struct ScrapingDogDetailsResponse: Codable, Sendable {
    let job_details: [ScrapingDogJobDetails]?
    let error: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case job_details
        case error
        case message
    }
}

// MARK: - Location Search

/// Location suggestion for geoid lookup
struct ScrapingDogLocation: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let name: String

    // Common US locations with their geoids
    static let commonLocations: [ScrapingDogLocation] = [
        ScrapingDogLocation(id: "103644278", name: "United States"),
        ScrapingDogLocation(id: "102095887", name: "California, United States"),
        ScrapingDogLocation(id: "90000070", name: "San Francisco Bay Area"),
        ScrapingDogLocation(id: "102448103", name: "New York, United States"),
        ScrapingDogLocation(id: "104116203", name: "Seattle, Washington"),
        ScrapingDogLocation(id: "100025096", name: "Austin, Texas"),
        ScrapingDogLocation(id: "102571732", name: "Boston, Massachusetts"),
        ScrapingDogLocation(id: "103112676", name: "Denver, Colorado"),
        ScrapingDogLocation(id: "90000084", name: "Los Angeles Area"),
        ScrapingDogLocation(id: "104937023", name: "Chicago, Illinois"),
        ScrapingDogLocation(id: "90000097", name: "Washington DC-Baltimore Area"),
        ScrapingDogLocation(id: "100293800", name: "Atlanta, Georgia"),
    ]
}
