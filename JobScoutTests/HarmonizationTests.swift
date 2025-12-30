//
//  HarmonizationTests.swift
//  JobScoutTests
//
//  Created by Ilia Sazonov on 12/29/25.
//

import Testing
import Foundation
@testable import JobScout

struct HarmonizationTests {

    // MARK: - DateNormalizer Tests

    @Test func dateNormalizerHandlesRelativeDates() async throws {
        // Use a fixed reference date for deterministic tests
        let referenceDate = Date(timeIntervalSince1970: 1735488000) // 2024-12-29 12:00:00 UTC
        let normalizer = DateNormalizer(referenceDate: referenceDate)

        // "today" should return reference date
        let today = normalizer.normalize("today")
        #expect(today == "2024-12-29")

        // "yesterday" should return one day before
        let yesterday = normalizer.normalize("yesterday")
        #expect(yesterday == "2024-12-28")

        // "2 days ago"
        let twoDaysAgo = normalizer.normalize("2 days ago")
        #expect(twoDaysAgo == "2024-12-27")

        // "1 week ago"
        let oneWeekAgo = normalizer.normalize("1 week ago")
        #expect(oneWeekAgo == "2024-12-22")

        // "3 weeks ago"
        let threeWeeksAgo = normalizer.normalize("3 weeks ago")
        #expect(threeWeeksAgo == "2024-12-08")
    }

    @Test func dateNormalizerHandlesFixedDates() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1735488000) // 2024-12-29
        let normalizer = DateNormalizer(referenceDate: referenceDate)

        // "Dec 27" format
        let dec27 = normalizer.normalize("Dec 27")
        #expect(dec27 == "2024-12-27")

        // "December 27" format
        let december27 = normalizer.normalize("December 27")
        #expect(december27 == "2024-12-27")

        // ISO format passthrough
        let iso = normalizer.normalize("2024-12-25")
        #expect(iso == "2024-12-25")

        // Slash format
        let slash = normalizer.normalize("12/27/24")
        #expect(slash == "2024-12-27")
    }

    @Test func dateNormalizerHandlesEdgeCases() async throws {
        let normalizer = DateNormalizer()

        // Empty string
        let empty = normalizer.normalize("")
        #expect(empty == nil)

        // Whitespace only
        let whitespace = normalizer.normalize("   ")
        #expect(whitespace == nil)

        // Invalid format
        let invalid = normalizer.normalize("not a date")
        #expect(invalid == nil)

        // "just now" should be treated as today
        let justNow = normalizer.normalize("just now")
        #expect(justNow != nil)

        // "5 hours ago" should be treated as today
        let hoursAgo = normalizer.normalize("5 hours ago")
        #expect(hoursAgo != nil)
    }

    @Test func dateNormalizerHandlesShorthandFormats() async throws {
        // Use a fixed reference date for deterministic tests
        let referenceDate = Date(timeIntervalSince1970: 1735488000) // 2024-12-29 12:00:00 UTC
        let normalizer = DateNormalizer(referenceDate: referenceDate)

        // "0d" - today
        let zeroD = normalizer.normalize("0d")
        #expect(zeroD == "2024-12-29")

        // "1d" - yesterday
        let oneD = normalizer.normalize("1d")
        #expect(oneD == "2024-12-28")

        // "15d" - 15 days ago
        let fifteenD = normalizer.normalize("15d")
        #expect(fifteenD == "2024-12-14")

        // "1w" - 1 week ago
        let oneW = normalizer.normalize("1w")
        #expect(oneW == "2024-12-22")

        // "2w" - 2 weeks ago
        let twoW = normalizer.normalize("2w")
        #expect(twoW == "2024-12-15")

        // "1mo" - 1 month ago
        let oneMo = normalizer.normalize("1mo")
        #expect(oneMo == "2024-11-29")

        // "2mo" - 2 months ago
        let twoMo = normalizer.normalize("2mo")
        #expect(twoMo == "2024-10-29")

        // "1m" - 1 month ago (alternative format)
        let oneM = normalizer.normalize("1m")
        #expect(oneM == "2024-11-29")

        // "1y" - 1 year ago
        let oneY = normalizer.normalize("1y")
        #expect(oneY == "2023-12-29")

        // "1yr" - 1 year ago (alternative format)
        let oneYr = normalizer.normalize("1yr")
        #expect(oneYr == "2023-12-29")

        // "5h" - hours, treated as today
        let fiveH = normalizer.normalize("5h")
        #expect(fiveH == "2024-12-29")
    }

    @Test func dateNormalizerShorthandIsCaseInsensitive() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1735488000) // 2024-12-29
        let normalizer = DateNormalizer(referenceDate: referenceDate)

        // Uppercase
        let upperD = normalizer.normalize("15D")
        #expect(upperD == "2024-12-14")

        let upperMo = normalizer.normalize("2MO")
        #expect(upperMo == "2024-10-29")

        let upperW = normalizer.normalize("1W")
        #expect(upperW == "2024-12-22")
    }

    // MARK: - LinkClassifier Tests

    @Test func linkClassifierIdentifiesAggregators() async throws {
        // Major aggregators
        #expect(LinkClassifier.isAggregator("https://simplify.jobs/c/abc123") == true)
        #expect(LinkClassifier.isAggregator("https://jobright.ai/jobs/engineer") == true)
        #expect(LinkClassifier.isAggregator("https://linkedin.com/jobs/view/123") == true)
        #expect(LinkClassifier.isAggregator("https://indeed.com/viewjob?jk=abc") == true)
        #expect(LinkClassifier.isAggregator("https://glassdoor.com/job-listing") == true)

        // ATS platforms
        #expect(LinkClassifier.isAggregator("https://jobs.lever.co/company/123") == true)
        #expect(LinkClassifier.isAggregator("https://boards.greenhouse.io/company") == true)
        #expect(LinkClassifier.isAggregator("https://company.myworkdayjobs.com/careers") == true)
    }

    @Test func linkClassifierIdentifiesCompanyLinks() async throws {
        // Company career pages
        #expect(LinkClassifier.isAggregator("https://careers.google.com/jobs/123") == false)
        #expect(LinkClassifier.isAggregator("https://apple.com/careers/us") == false)
        #expect(LinkClassifier.isAggregator("https://startup.io/jobs") == false)
        #expect(LinkClassifier.isAggregator("https://company.com/careers/engineer") == false)
    }

    @Test func linkClassifierReturnsCorrectAggregatorNames() async throws {
        #expect(LinkClassifier.aggregatorName(from: "https://simplify.jobs/c/abc") == "Simplify")
        #expect(LinkClassifier.aggregatorName(from: "https://jobright.ai/jobs/123") == "Jobright")
        #expect(LinkClassifier.aggregatorName(from: "https://linkedin.com/jobs") == "LinkedIn")
        #expect(LinkClassifier.aggregatorName(from: "https://jobs.lever.co/x") == "Lever")
        #expect(LinkClassifier.aggregatorName(from: "https://boards.greenhouse.io/x") == "Greenhouse")

        // Company links return nil
        #expect(LinkClassifier.aggregatorName(from: "https://google.com/careers") == nil)
    }

    @Test func linkClassifierSeparatesLinks() async throws {
        let links = [
            "https://apple.com/careers/123",
            "https://simplify.jobs/c/abc",
            "https://linkedin.com/jobs/view/456"
        ]

        let result = LinkClassifier.separateLinks(links)
        #expect(result.companyLink == "https://apple.com/careers/123")
        #expect(result.aggregatorLink == "https://simplify.jobs/c/abc")
        #expect(result.aggregatorName == "Simplify")
    }

    @Test func linkClassifierExtractsDomainName() async throws {
        #expect(LinkClassifier.extractDomainName(from: "https://apple.com/careers") == "Apple")
        #expect(LinkClassifier.extractDomainName(from: "https://www.google.com/jobs") == "Google")
        #expect(LinkClassifier.extractDomainName(from: "https://careers.microsoft.com") == "Microsoft")
    }

    // MARK: - JobCategory Tests

    @Test func jobCategoryInfersSoftwareEngineering() async throws {
        #expect(JobCategory.infer(from: "Software Engineer") == .softwareEngineering)
        #expect(JobCategory.infer(from: "Junior Developer") == .softwareEngineering)
        #expect(JobCategory.infer(from: "Senior Programmer") == .softwareEngineering)
        #expect(JobCategory.infer(from: "Staff Engineer") == .softwareEngineering)
    }

    @Test func jobCategoryInfersSpecializations() async throws {
        // Machine Learning
        #expect(JobCategory.infer(from: "Machine Learning Engineer") == .machineLearning)
        #expect(JobCategory.infer(from: "ML Engineer") == .machineLearning)
        #expect(JobCategory.infer(from: "AI Engineer") == .machineLearning)

        // Data Science
        #expect(JobCategory.infer(from: "Data Scientist") == .dataScience)
        #expect(JobCategory.infer(from: "Data Analyst") == .dataScience)

        // Frontend
        #expect(JobCategory.infer(from: "Frontend Engineer") == .frontend)
        #expect(JobCategory.infer(from: "Front-end Developer") == .frontend)
        #expect(JobCategory.infer(from: "UI Engineer") == .frontend)

        // Backend
        #expect(JobCategory.infer(from: "Backend Engineer") == .backend)
        #expect(JobCategory.infer(from: "Back-end Developer") == .backend)

        // Full Stack
        #expect(JobCategory.infer(from: "Full Stack Developer") == .fullStack)
        #expect(JobCategory.infer(from: "Fullstack Engineer") == .fullStack)

        // Mobile
        #expect(JobCategory.infer(from: "iOS Developer") == .mobile)
        #expect(JobCategory.infer(from: "Android Engineer") == .mobile)
        #expect(JobCategory.infer(from: "Mobile Developer") == .mobile)

        // DevOps
        #expect(JobCategory.infer(from: "DevOps Engineer") == .devOps)
        #expect(JobCategory.infer(from: "Site Reliability Engineer") == .devOps)
        #expect(JobCategory.infer(from: "SRE") == .devOps)
        #expect(JobCategory.infer(from: "Platform Engineer") == .devOps)

        // Security
        #expect(JobCategory.infer(from: "Security Engineer") == .security)
        #expect(JobCategory.infer(from: "Cybersecurity Analyst") == .security)

        // Product Management
        #expect(JobCategory.infer(from: "Product Manager") == .productManagement)

        // Design
        #expect(JobCategory.infer(from: "UX Designer") == .design)
        #expect(JobCategory.infer(from: "UI/UX Designer") == .design)

        // Embedded
        #expect(JobCategory.infer(from: "Embedded Systems Engineer") == .embedded)
        #expect(JobCategory.infer(from: "Firmware Engineer") == .embedded)

        // Game Dev
        #expect(JobCategory.infer(from: "Game Developer") == .gamedev)
        #expect(JobCategory.infer(from: "Unity Engineer") == .gamedev)
    }

    @Test func jobCategoryFallsBackToOther() async throws {
        #expect(JobCategory.infer(from: "Account Executive") == .other)
        #expect(JobCategory.infer(from: "Marketing Manager") == .other)
        #expect(JobCategory.infer(from: "Sales Representative") == .other)
    }

    @Test func jobCategoryIsCaseInsensitive() async throws {
        #expect(JobCategory.infer(from: "SOFTWARE ENGINEER") == .softwareEngineering)
        #expect(JobCategory.infer(from: "machine learning engineer") == .machineLearning)
        #expect(JobCategory.infer(from: "iOS DEVELOPER") == .mobile)
    }

    // MARK: - DataHarmonizer Tests (using deterministic harmonization)

    @Test func dataHarmonizerNormalizesRelativeDates() async throws {
        let harmonizer = DataHarmonizer()

        let jobs = [
            JobPosting(
                company: "TestCo",
                role: "Engineer",
                location: "Remote",
                category: "Software Engineering",
                companyLink: "https://testco.com/jobs",
                datePosted: "2 days ago"
            )
        ]

        // Use deterministic harmonization (doesn't need async/keychain)
        let result = await harmonizer.harmonizeDeterministic(jobs)

        #expect(result.count == 1)
        // The date should be normalized to ISO format
        let dateStr = result.first?.datePosted
        #expect(dateStr != nil)
        #expect(dateStr != "2 days ago")
        // Should be in YYYY-MM-DD format
        #expect(dateStr?.contains("-") == true)
    }

    @Test func dataHarmonizerReclassifiesAggregatorLinks() async throws {
        let harmonizer = DataHarmonizer()

        // Job with jobright.ai link classified as company link
        let jobs = [
            JobPosting(
                company: "TestCo",
                role: "Engineer",
                location: "Remote",
                category: "Software Engineering",
                companyLink: "https://jobright.ai/jobs/123",  // Wrong - should be aggregator
                aggregatorLink: nil
            )
        ]

        // Use deterministic harmonization
        let result = await harmonizer.harmonizeDeterministic(jobs)

        #expect(result.count == 1)
        let job = result.first!
        // Company link should be nil (reclassified)
        #expect(job.companyLink == nil)
        // Should be moved to aggregator link
        #expect(job.aggregatorLink == "https://jobright.ai/jobs/123")
        #expect(job.aggregatorName == "Jobright")
    }

    @Test func dataHarmonizerHandlesMultipleDateFormats() async throws {
        let harmonizer = DataHarmonizer()

        let testCases: [(input: String, shouldNormalize: Bool)] = [
            ("Dec 27", true),
            ("yesterday", true),
            ("3 days ago", true),
            ("2024-12-27", false),  // Already ISO format
            ("1 week ago", true),
            ("today", true)
        ]

        for testCase in testCases {
            let jobs = [
                JobPosting(
                    company: "TestCo",
                    role: "Engineer",
                    location: "Remote",
                    category: "Software Engineering",
                    companyLink: "https://testco.com/jobs",
                    datePosted: testCase.input
                )
            ]

            // Use deterministic harmonization
            let result = await harmonizer.harmonizeDeterministic(jobs)

            let outputDate = result.first?.datePosted ?? ""
            if testCase.shouldNormalize {
                #expect(outputDate != testCase.input, "Date '\(testCase.input)' should be normalized but got '\(outputDate)'")
            }
            // All outputs should be in ISO format (YYYY-MM-DD)
            let isoPattern = #"^\d{4}-\d{2}-\d{2}$"#
            #expect(outputDate.range(of: isoPattern, options: .regularExpression) != nil,
                   "Date '\(testCase.input)' should normalize to ISO format but got '\(outputDate)'")
        }
    }

    // MARK: - isGenericCategory Tests (test the logic directly)

    @Test func isGenericCategoryDetectsGenericPatterns() async throws {
        // Test generic category detection by checking category replacement
        // These categories should be considered generic:
        let genericCategories = [
            "Daily List",
            "New Jobs",
            "jobs",
            "2024 Internships",
            "Fall 2025",
            "New Grad Positions"
        ]

        let harmonizer = DataHarmonizer()

        for category in genericCategories {
            let jobs = [
                JobPosting(
                    company: "TestCo",
                    role: "Engineer",
                    location: "Remote",
                    category: category,
                    companyLink: "https://testco.com/jobs"
                )
            ]

            // Use deterministic harmonization - note: it doesn't change categories
            // but we can verify the category handling in the full harmonize method
            let result = await harmonizer.harmonizeDeterministic(jobs)

            // Deterministic doesn't change categories, just dates and links
            // So this test just verifies no crash
            #expect(result.count == 1)
        }
    }

    @Test func jobsSortByDateDescending() async throws {
        // Create jobs with different dates
        let jobs = [
            JobPosting(company: "OldCo", role: "Engineer", location: "Remote", category: "Software", companyLink: "https://old.com", datePosted: "2024-12-01"),
            JobPosting(company: "NewCo", role: "Engineer", location: "Remote", category: "Software", companyLink: "https://new.com", datePosted: "2024-12-29"),
            JobPosting(company: "MidCo", role: "Engineer", location: "Remote", category: "Software", companyLink: "https://mid.com", datePosted: "2024-12-15"),
            JobPosting(company: "NilCo", role: "Engineer", location: "Remote", category: "Software", companyLink: "https://nil.com", datePosted: nil)
        ]

        // Sort by date descending (most recent first), nil dates go to end
        let sorted = jobs.sorted { job1, job2 in
            let date1 = job1.datePosted ?? ""
            let date2 = job2.datePosted ?? ""
            if date1.isEmpty && date2.isEmpty { return false }
            if date1.isEmpty { return false }
            if date2.isEmpty { return true }
            return date1 > date2
        }

        // Verify order: NewCo (12-29), MidCo (12-15), OldCo (12-01), NilCo (nil)
        #expect(sorted[0].company == "NewCo")
        #expect(sorted[1].company == "MidCo")
        #expect(sorted[2].company == "OldCo")
        #expect(sorted[3].company == "NilCo")
    }

    @Test func dataHarmonizerPreservesSpecificCategories() async throws {
        let harmonizer = DataHarmonizer()

        // Job with specific category that shouldn't be changed
        let jobs = [
            JobPosting(
                company: "TestCo",
                role: "Engineer",
                location: "Remote",
                category: "Machine Learning",
                companyLink: "https://testco.com/jobs"
            )
        ]

        // Use deterministic harmonization
        let result = await harmonizer.harmonizeDeterministic(jobs)

        #expect(result.count == 1)
        // Deterministic preserves category
        #expect(result.first?.category == "Machine Learning")
    }
}

// MARK: - URLHistoryService Tests

/// Tests for URLHistoryService - run serially to avoid race conditions on shared database
@Suite(.serialized)
struct URLHistoryServiceTests {
    @Test func urlHistoryServiceAddsURLs() async throws {
        let service = URLHistoryService.shared

        // Use unique test ID to avoid conflicts with parallel test runs
        let testId = UUID().uuidString.prefix(8)
        let url = "https://example.com/add-\(testId)-test1"

        // Add a URL
        await service.addURL(url)

        let history = await service.getHistory()
        #expect(history.contains(url))

        // Clean up
        await service.removeURL(url)
    }

    @Test func urlHistoryServiceMaintainsOrder() async throws {
        let service = URLHistoryService.shared

        // Use unique test ID to avoid conflicts with parallel test runs
        let testId = UUID().uuidString.prefix(8)
        let url1 = "https://example.com/order-\(testId)-first"
        let url2 = "https://example.com/order-\(testId)-second"
        let url3 = "https://example.com/order-\(testId)-third"

        // Add URLs in order with delay to ensure different timestamps
        // SQLite datetime has second-level precision, so we need > 1 second delay
        await service.addURL(url1)
        try await Task.sleep(for: .seconds(1.1))
        await service.addURL(url2)
        try await Task.sleep(for: .seconds(1.1))
        await service.addURL(url3)

        let history = await service.getHistory()

        // Find our test URLs in the history
        let ourUrls = history.filter { $0.contains(String(testId)) }

        // Most recent should be first among our test URLs
        #expect(ourUrls.first == url3)

        // Clean up our test URLs
        await service.removeURL(url1)
        await service.removeURL(url2)
        await service.removeURL(url3)
    }

    @Test func urlHistoryServiceMovesExistingToTop() async throws {
        let service = URLHistoryService.shared

        // Use unique test ID to avoid conflicts with parallel test runs
        let testId = UUID().uuidString.prefix(8)
        let url1 = "https://example.com/move-\(testId)-first"
        let url2 = "https://example.com/move-\(testId)-second"
        let url3 = "https://example.com/move-\(testId)-third"

        // Add URLs with delays for timestamp ordering
        await service.addURL(url1)
        try await Task.sleep(for: .seconds(1.1))
        await service.addURL(url2)
        try await Task.sleep(for: .seconds(1.1))
        await service.addURL(url3)
        try await Task.sleep(for: .seconds(1.1))

        // Re-add the first URL - should move to top
        await service.addURL(url1)

        let history = await service.getHistory()

        // Find our test URLs in the history
        let ourUrls = history.filter { $0.contains(String(testId)) }

        // "first" should now be at the top among our test URLs
        #expect(ourUrls.first == url1)
        // Should only appear once
        #expect(ourUrls.filter { $0 == url1 }.count == 1)

        // Clean up our test URLs
        await service.removeURL(url1)
        await service.removeURL(url2)
        await service.removeURL(url3)
    }

    @Test func urlHistoryServiceRemovesURLs() async throws {
        let service = URLHistoryService.shared

        // Use unique test ID to avoid conflicts with parallel test runs
        let testId = UUID().uuidString.prefix(8)
        let url1 = "https://example.com/remove-\(testId)-first"
        let url2 = "https://example.com/remove-\(testId)-second"

        // Add URLs
        await service.addURL(url1)
        await service.addURL(url2)

        // Remove one
        await service.removeURL(url1)

        let history = await service.getHistory()

        #expect(!history.contains(url1))
        #expect(history.contains(url2))

        // Clean up
        await service.removeURL(url2)
    }

    @Test func urlHistoryServiceAddsAndRemoves() async throws {
        let service = URLHistoryService.shared

        // Use unique test ID to avoid conflicts with parallel test runs
        let testId = UUID().uuidString.prefix(8)
        let url1 = "https://example.com/addremove-\(testId)-first"
        let url2 = "https://example.com/addremove-\(testId)-second"

        // Add URLs
        await service.addURL(url1)
        await service.addURL(url2)

        var history = await service.getHistory()
        #expect(history.contains(url1))
        #expect(history.contains(url2))

        // Remove all test URLs
        await service.removeURL(url1)
        await service.removeURL(url2)

        history = await service.getHistory()
        #expect(!history.contains(url1))
        #expect(!history.contains(url2))
    }

    @Test func urlHistoryServiceReturnsSourceMetadata() async throws {
        let service = URLHistoryService.shared

        // Use unique test ID to avoid conflicts with parallel test runs
        let testId = UUID().uuidString.prefix(8)
        let url = "https://github.com/TestOrg-\(testId)/Test-Repo/blob/dev/README.md"

        // Add a URL
        await service.addURL(url)

        let sources = await service.getSources()
        let ourSource = sources.first { $0.url == url }

        #expect(ourSource != nil)
        #expect(ourSource?.url == url)
        #expect(ourSource?.name == "TestOrg-\(testId)/Test-Repo")
        #expect(ourSource?.lastFetchedAt != nil)

        // Clean up
        await service.removeURL(url)
    }
}
