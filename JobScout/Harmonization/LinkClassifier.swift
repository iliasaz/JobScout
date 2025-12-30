//
//  LinkClassifier.swift
//  JobScout
//
//  Created by Ilia Sazonov on 12/29/25.
//

import Foundation

/// Classification result for a URL
enum LinkClassification: Sendable {
    case company       // Direct company career page
    case aggregator(name: String)  // Job aggregator site
}

/// Classifies URLs as company or aggregator links
struct LinkClassifier: Sendable {
    /// Known job aggregator domains and their display names
    static let aggregatorDomains: [String: String] = [
        // Major aggregators
        "simplify.jobs": "Simplify",
        "simplify.co": "Simplify",
        "jobright.ai": "Jobright",
        "linkedin.com": "LinkedIn",
        "indeed.com": "Indeed",
        "glassdoor.com": "Glassdoor",
        "ziprecruiter.com": "ZipRecruiter",
        "monster.com": "Monster",
        "dice.com": "Dice",
        "careerbuilder.com": "CareerBuilder",

        // Tech-focused
        "wellfound.com": "Wellfound",
        "angel.co": "Wellfound",
        "builtin.com": "BuiltIn",
        "hired.com": "Hired",
        "otta.com": "Otta",
        "levels.fyi": "Levels.fyi",
        "triplebyte.com": "Triplebyte",
        "turing.com": "Turing",

        // ATS platforms (job applications often go through these)
        "lever.co": "Lever",
        "greenhouse.io": "Greenhouse",
        "workday.com": "Workday",
        "smartrecruiters.com": "SmartRecruiters",
        "icims.com": "iCIMS",
        "jobs.lever.co": "Lever",
        "boards.greenhouse.io": "Greenhouse",
        "myworkday.com": "Workday",
        "myworkdayjobs.com": "Workday",
        "taleo.net": "Taleo",
        "successfactors.com": "SAP SuccessFactors",
        "jobvite.com": "Jobvite",
        "ashbyhq.com": "Ashby",

        // International
        "seek.com.au": "Seek",
        "reed.co.uk": "Reed",
        "totaljobs.com": "TotalJobs",
        "cv-library.co.uk": "CV-Library",
        "xing.com": "Xing",
        "stepstone.de": "StepStone"
    ]

    /// Classify a URL as company or aggregator
    /// - Parameter url: The URL string to classify
    /// - Returns: LinkClassification indicating if it's a company or aggregator link
    static func classify(_ url: String) -> LinkClassification {
        let lowercased = url.lowercased()

        for (domain, name) in aggregatorDomains {
            if lowercased.contains(domain) {
                return .aggregator(name: name)
            }
        }

        return .company
    }

    /// Check if a URL is from an aggregator
    /// - Parameter url: The URL string to check
    /// - Returns: True if the URL is from a known aggregator
    static func isAggregator(_ url: String) -> Bool {
        if case .aggregator = classify(url) {
            return true
        }
        return false
    }

    /// Get the aggregator name for a URL
    /// - Parameter url: The URL string to check
    /// - Returns: The aggregator name if the URL is from an aggregator, nil otherwise
    static func aggregatorName(from url: String) -> String? {
        if case let .aggregator(name) = classify(url) {
            return name
        }
        return nil
    }

    /// Extract a human-readable name from a URL host
    /// - Parameter urlString: The URL string
    /// - Returns: A capitalized domain name (e.g., "apple" from "apple.com")
    static func extractDomainName(from urlString: String) -> String? {
        guard let url = URL(string: urlString), let host = url.host else {
            return nil
        }

        let parts = host.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        // Return the second-to-last part, capitalized
        return String(parts[parts.count - 2]).capitalized
    }

    /// Classify and separate links into company and aggregator
    /// - Parameter links: Array of link strings
    /// - Returns: Tuple of (companyLink, aggregatorLink, aggregatorName)
    static func separateLinks(_ links: [String]) -> (companyLink: String?, aggregatorLink: String?, aggregatorName: String?) {
        var companyLink: String?
        var aggregatorLink: String?
        var aggregatorName: String?

        for link in links {
            guard !link.isEmpty else { continue }

            switch classify(link) {
            case .aggregator(let name):
                if aggregatorLink == nil {
                    aggregatorLink = link
                    aggregatorName = name
                }
            case .company:
                if companyLink == nil {
                    companyLink = link
                }
            }
        }

        return (companyLink, aggregatorLink, aggregatorName)
    }

    // MARK: - Instance methods (convenience wrappers)

    /// Classify a URL as company or aggregator
    func classify(_ url: String) -> LinkClassification {
        Self.classify(url)
    }

    /// Check if a URL is from an aggregator
    func isAggregator(_ url: String) -> Bool {
        Self.isAggregator(url)
    }

    /// Get the aggregator name for a URL
    func aggregatorName(from url: String) -> String? {
        Self.aggregatorName(from: url)
    }

    /// Extract a human-readable name from a URL host
    func extractDomainName(from urlString: String) -> String? {
        Self.extractDomainName(from: urlString)
    }

    /// Classify and separate links into company and aggregator
    func separateLinks(_ links: [String]) -> (companyLink: String?, aggregatorLink: String?, aggregatorName: String?) {
        Self.separateLinks(links)
    }
}
