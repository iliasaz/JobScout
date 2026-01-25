//
//  ScrapingDogTests.swift
//  JobScoutTests
//
//  Created by Claude on 1/25/26.
//

import Testing
import Foundation
@testable import JobScout

struct ScrapingDogTests {

    // MARK: - ScrapingDogJob Conversion Tests

    @Test func scrapingDogJobConvertsToJobPosting() async throws {
        let job = ScrapingDogJob(
            job_position: "Software Engineer",
            job_link: "https://linkedin.com/jobs/view/123",
            job_id: "123",
            company_name: "Acme Corp",
            company_profile: "https://acme.com",
            job_location: "San Francisco, CA",
            job_posting_date: "2026-01-25"
        )

        let posting = job.toJobPosting()

        #expect(posting != nil)
        #expect(posting?.company == "Acme Corp")
        #expect(posting?.role == "Software Engineer")
        #expect(posting?.location == "San Francisco, CA")
        #expect(posting?.aggregatorLink == "https://linkedin.com/jobs/view/123")
        #expect(posting?.aggregatorName == "LinkedIn")
        #expect(posting?.companyWebsite == "https://acme.com")
        #expect(posting?.datePosted == "2026-01-25")
    }

    @Test func scrapingDogJobConversionReturnsNilWhenCompanyMissing() async throws {
        let job = ScrapingDogJob(
            job_position: "Software Engineer",
            job_link: "https://linkedin.com/jobs/view/123",
            job_id: "123",
            company_name: nil,
            company_profile: nil,
            job_location: "San Francisco, CA",
            job_posting_date: nil
        )

        let posting = job.toJobPosting()
        #expect(posting == nil)
    }

    @Test func scrapingDogJobConversionReturnsNilWhenRoleMissing() async throws {
        let job = ScrapingDogJob(
            job_position: nil,
            job_link: "https://linkedin.com/jobs/view/123",
            job_id: "123",
            company_name: "Acme Corp",
            company_profile: nil,
            job_location: "San Francisco, CA",
            job_posting_date: nil
        )

        let posting = job.toJobPosting()
        #expect(posting == nil)
    }

    @Test func scrapingDogJobConversionReturnsNilWhenCompanyEmpty() async throws {
        let job = ScrapingDogJob(
            job_position: "Software Engineer",
            job_link: "https://linkedin.com/jobs/view/123",
            job_id: "123",
            company_name: "",
            company_profile: nil,
            job_location: "San Francisco, CA",
            job_posting_date: nil
        )

        let posting = job.toJobPosting()
        #expect(posting == nil)
    }

    // MARK: - ScrapingDogSearchParams Tests

    @Test func searchParamsBuildQueryItemsCorrectly() async throws {
        let params = ScrapingDogSearchParams(
            field: "Software Engineer",
            geoid: "103644278",
            page: 1,
            sortBy: .week,
            jobType: .fullTime,
            experienceLevel: .midSeniorLevel,
            workType: .remote
        )

        let items = params.buildQueryItems(apiKey: "test-key")

        // Check required items
        #expect(items.contains { $0.name == "api_key" && $0.value == "test-key" })
        #expect(items.contains { $0.name == "field" && $0.value == "Software Engineer" })
        #expect(items.contains { $0.name == "page" && $0.value == "1" })

        // Check optional items
        #expect(items.contains { $0.name == "geoid" && $0.value == "103644278" })
        #expect(items.contains { $0.name == "sort_by" && $0.value == "week" })
        #expect(items.contains { $0.name == "job_type" && $0.value == "full_time" })
        #expect(items.contains { $0.name == "exp_level" && $0.value == "mid_senior_level" })
        #expect(items.contains { $0.name == "work_type" && $0.value == "remote" })
    }

    @Test func searchParamsOmitsOptionalParametersWhenNil() async throws {
        let params = ScrapingDogSearchParams(
            field: "Data Scientist",
            geoid: nil,
            page: 2,
            sortBy: .relevant,
            jobType: nil,
            experienceLevel: nil,
            workType: nil
        )

        let items = params.buildQueryItems(apiKey: "test-key")

        // Check required items are present
        #expect(items.contains { $0.name == "api_key" })
        #expect(items.contains { $0.name == "field" })
        #expect(items.contains { $0.name == "page" })

        // Check optional items are NOT present
        #expect(!items.contains { $0.name == "geoid" })
        #expect(!items.contains { $0.name == "sort_by" })  // relevant is default, not sent
        #expect(!items.contains { $0.name == "job_type" })
        #expect(!items.contains { $0.name == "experience_level" })
        #expect(!items.contains { $0.name == "work_type" })
    }

    // MARK: - Enum Raw Values Tests

    @Test func sortByEnumRawValuesMatchAPI() async throws {
        #expect(ScrapingDogSearchParams.SortBy.relevant.rawValue == "relevant")
        #expect(ScrapingDogSearchParams.SortBy.day.rawValue == "day")
        #expect(ScrapingDogSearchParams.SortBy.week.rawValue == "week")
        #expect(ScrapingDogSearchParams.SortBy.month.rawValue == "month")
    }

    @Test func jobTypeEnumRawValuesMatchAPI() async throws {
        #expect(ScrapingDogSearchParams.JobType.fullTime.rawValue == "full_time")
        #expect(ScrapingDogSearchParams.JobType.partTime.rawValue == "part_time")
        #expect(ScrapingDogSearchParams.JobType.contract.rawValue == "contract")
        #expect(ScrapingDogSearchParams.JobType.temporary.rawValue == "temporary")
        #expect(ScrapingDogSearchParams.JobType.volunteer.rawValue == "volunteer")
    }

    @Test func experienceLevelEnumRawValuesMatchAPI() async throws {
        #expect(ScrapingDogSearchParams.ExperienceLevel.internship.rawValue == "internship")
        #expect(ScrapingDogSearchParams.ExperienceLevel.entryLevel.rawValue == "entry_level")
        #expect(ScrapingDogSearchParams.ExperienceLevel.associate.rawValue == "associate")
        #expect(ScrapingDogSearchParams.ExperienceLevel.midSeniorLevel.rawValue == "mid_senior_level")
        #expect(ScrapingDogSearchParams.ExperienceLevel.director.rawValue == "director")
    }

    @Test func workTypeEnumRawValuesMatchAPI() async throws {
        #expect(ScrapingDogSearchParams.WorkType.onSite.rawValue == "at_work")
        #expect(ScrapingDogSearchParams.WorkType.remote.rawValue == "remote")
        #expect(ScrapingDogSearchParams.WorkType.hybrid.rawValue == "hybrid")
    }

    // MARK: - ScrapingDogJobDetails Tests

    @Test func jobDetailsEnrichesExistingJobPosting() async throws {
        let existingJob = JobPosting(
            company: "Old Company",
            role: "Old Role",
            location: "Old Location",
            category: "Software",
            aggregatorLink: "https://linkedin.com/jobs/view/123",
            aggregatorName: "LinkedIn"
        )

        let details = ScrapingDogJobDetails(
            job_position: "Senior Software Engineer",
            job_link: "https://linkedin.com/jobs/view/123",
            job_id: "123",
            company_name: "New Company",
            company_profile: "https://newcompany.com",
            job_location: "New York, NY",
            job_posting_date: "2026-01-20",
            job_description: "We are looking for a senior engineer...",
            job_apply_link: "https://newcompany.com/apply/123",
            Seniority_level: "Mid-Senior level",
            Employment_type: "Full-time",
            job_function: "Engineering",
            Industries: "Technology"
        )

        let enriched = details.enrichJobPosting(existingJob)

        #expect(enriched.company == "New Company")
        #expect(enriched.role == "Senior Software Engineer")
        #expect(enriched.location == "New York, NY")
        #expect(enriched.category == "Software")  // Preserved from original
        #expect(enriched.companyLink == "https://newcompany.com/apply/123")
        #expect(enriched.companyWebsite == "https://newcompany.com")
        #expect(enriched.descriptionText == "We are looking for a senior engineer...")
        #expect(enriched.aggregatorName == "LinkedIn")
    }

    // MARK: - ScrapingDogLocation Tests

    @Test func commonLocationsHaveValidGeoids() async throws {
        let locations = ScrapingDogLocation.commonLocations

        #expect(!locations.isEmpty)

        // All locations should have non-empty id and name
        for location in locations {
            #expect(!location.id.isEmpty)
            #expect(!location.name.isEmpty)
        }

        // Check specific well-known location
        let usLocation = locations.first { $0.name == "United States" }
        #expect(usLocation != nil)
        #expect(usLocation?.id == "103644278")
    }

    // MARK: - JSON Decoding Tests

    @Test func scrapingDogJobDecodesFromJSON() async throws {
        let json = """
        {
            "job_position": "iOS Developer",
            "job_link": "https://linkedin.com/jobs/view/456",
            "job_id": "456",
            "company_name": "Apple Inc",
            "company_profile": "https://apple.com",
            "job_location": "Cupertino, CA",
            "job_posting_date": "Jan 15"
        }
        """.data(using: .utf8)!

        let job = try JSONDecoder().decode(ScrapingDogJob.self, from: json)

        #expect(job.job_position == "iOS Developer")
        #expect(job.company_name == "Apple Inc")
        #expect(job.job_id == "456")
    }

    @Test func scrapingDogSearchResponseDecodesFromJSON() async throws {
        let json = """
        {
            "jobs": [
                {
                    "job_position": "Software Engineer",
                    "job_link": "https://linkedin.com/jobs/view/789",
                    "job_id": "789",
                    "company_name": "Google",
                    "company_profile": "https://google.com",
                    "job_location": "Mountain View, CA",
                    "job_posting_date": "Jan 20"
                }
            ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ScrapingDogSearchResponse.self, from: json)

        #expect(response.jobs?.count == 1)
        #expect(response.jobs?.first?.company_name == "Google")
        #expect(response.error == nil)
    }

    @Test func scrapingDogSearchResponseHandlesErrorResponse() async throws {
        let json = """
        {
            "error": "Invalid API key",
            "message": "Please provide a valid API key"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ScrapingDogSearchResponse.self, from: json)

        #expect(response.jobs == nil)
        #expect(response.error == "Invalid API key")
        #expect(response.message == "Please provide a valid API key")
    }

    // MARK: - Direct Array Response Tests

    @Test func scrapingDogDirectArrayResponseDecodes() async throws {
        // The API returns a direct JSON array, not wrapped in an object
        let json = """
        [
            {
                "job_position": "Software Engineer",
                "job_link": "https://linkedin.com/jobs/view/123",
                "job_id": "123",
                "company_name": "Google",
                "company_profile": "https://google.com",
                "job_location": "Mountain View, CA",
                "job_posting_date": "2 days ago"
            },
            {
                "job_position": "Senior Developer",
                "job_link": "https://linkedin.com/jobs/view/456",
                "job_id": "456",
                "company_name": "Meta",
                "company_profile": "https://meta.com",
                "job_location": "Menlo Park, CA",
                "job_posting_date": "1 week ago"
            }
        ]
        """.data(using: .utf8)!

        let jobs = try JSONDecoder().decode([ScrapingDogJob].self, from: json)

        #expect(jobs.count == 2)
        #expect(jobs[0].company_name == "Google")
        #expect(jobs[0].job_position == "Software Engineer")
        #expect(jobs[1].company_name == "Meta")
        #expect(jobs[1].job_position == "Senior Developer")
    }

    @Test func scrapingDogJobHandlesCompanyLogoField() async throws {
        // API also returns company_logo_url which we should handle gracefully
        let json = """
        {
            "job_position": "iOS Developer",
            "job_link": "https://linkedin.com/jobs/view/789",
            "job_id": "789",
            "company_name": "Apple",
            "company_profile": "https://apple.com",
            "company_logo_url": "https://logo.clearbit.com/apple.com",
            "job_location": "Cupertino, CA",
            "job_posting_date": "3 days ago"
        }
        """.data(using: .utf8)!

        let job = try JSONDecoder().decode(ScrapingDogJob.self, from: json)

        #expect(job.company_name == "Apple")
        #expect(job.job_position == "iOS Developer")
        // company_logo_url should be ignored gracefully
    }
}
