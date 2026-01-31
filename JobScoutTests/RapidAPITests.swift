//
//  RapidAPITests.swift
//  JobScoutTests
//
//  Created by Claude on 1/29/26.
//

import Testing
import Foundation
@testable import JobScout

struct RapidAPITests {

    // MARK: - RapidAPIJob Conversion Tests

    @Test func rapidAPIJobConvertsToJobPosting() async throws {
        let job = RapidAPIJob(
            id: "123",
            title: "Software Engineer",
            url: "https://www.linkedin.com/jobs/view/123",
            listed_at: "2026-01-25T10:00:00.000Z",
            is_promote: false,
            is_easy_apply: true,
            location: "San Francisco, CA",
            company: RapidAPICompany(
                id: "456",
                name: "Acme Corp",
                url: "https://acme.com",
                verified: true,
                logo: nil
            )
        )

        let posting = job.toJobPosting()

        #expect(posting != nil)
        #expect(posting?.company == "Acme Corp")
        #expect(posting?.role == "Software Engineer")
        #expect(posting?.location == "San Francisco, CA")
        #expect(posting?.aggregatorLink == "https://www.linkedin.com/jobs/view/123")
        #expect(posting?.aggregatorName == "LinkedIn")
        #expect(posting?.companyWebsite == "https://acme.com")
        #expect(posting?.datePosted == "2026-01-25")
        #expect(posting?.hasEasyApply == true)
    }

    @Test func rapidAPIJobConversionReturnsNilWhenCompanyMissing() async throws {
        let job = RapidAPIJob(
            id: "123",
            title: "Software Engineer",
            url: "https://www.linkedin.com/jobs/view/123",
            listed_at: nil,
            is_promote: nil,
            is_easy_apply: nil,
            location: "SF",
            company: nil
        )

        let posting = job.toJobPosting()
        #expect(posting == nil)
    }

    @Test func rapidAPIJobConversionReturnsNilWhenTitleMissing() async throws {
        let job = RapidAPIJob(
            id: "123",
            title: nil,
            url: "https://www.linkedin.com/jobs/view/123",
            listed_at: nil,
            is_promote: nil,
            is_easy_apply: nil,
            location: "SF",
            company: RapidAPICompany(id: "1", name: "Acme", url: nil, verified: nil, logo: nil)
        )

        let posting = job.toJobPosting()
        #expect(posting == nil)
    }

    @Test func rapidAPIJobConversionReturnsNilWhenCompanyNameEmpty() async throws {
        let job = RapidAPIJob(
            id: "123",
            title: "Software Engineer",
            url: "https://www.linkedin.com/jobs/view/123",
            listed_at: nil,
            is_promote: nil,
            is_easy_apply: nil,
            location: "SF",
            company: RapidAPICompany(id: "1", name: "", url: nil, verified: nil, logo: nil)
        )

        let posting = job.toJobPosting()
        #expect(posting == nil)
    }

    @Test func rapidAPIJobMapsHasEasyApplyCorrectly() async throws {
        // is_easy_apply = true
        let jobTrue = RapidAPIJob(
            id: "1", title: "Dev", url: nil, listed_at: nil,
            is_promote: nil, is_easy_apply: true, location: nil,
            company: RapidAPICompany(id: "1", name: "Co", url: nil, verified: nil, logo: nil)
        )
        #expect(jobTrue.toJobPosting()?.hasEasyApply == true)

        // is_easy_apply = false
        let jobFalse = RapidAPIJob(
            id: "2", title: "Dev", url: nil, listed_at: nil,
            is_promote: nil, is_easy_apply: false, location: nil,
            company: RapidAPICompany(id: "1", name: "Co", url: nil, verified: nil, logo: nil)
        )
        #expect(jobFalse.toJobPosting()?.hasEasyApply == false)

        // is_easy_apply = nil
        let jobNil = RapidAPIJob(
            id: "3", title: "Dev", url: nil, listed_at: nil,
            is_promote: nil, is_easy_apply: nil, location: nil,
            company: RapidAPICompany(id: "1", name: "Co", url: nil, verified: nil, logo: nil)
        )
        #expect(jobNil.toJobPosting()?.hasEasyApply == nil)
    }

    @Test func rapidAPIJobParsesISO8601Date() async throws {
        let job = RapidAPIJob(
            id: "1", title: "Dev",
            url: nil,
            listed_at: "2026-01-20T15:30:00.000Z",
            is_promote: nil, is_easy_apply: nil, location: nil,
            company: RapidAPICompany(id: "1", name: "Co", url: nil, verified: nil, logo: nil)
        )

        let posting = job.toJobPosting()
        #expect(posting?.datePosted == "2026-01-20")
    }

    // MARK: - Query Param Building Tests

    @Test func searchParamsBuildQueryItemsCorrectly() async throws {
        let params = RapidAPISearchParams(
            keyword: "Software Engineer",
            page: 2,
            sortBy: .recent,
            datePosted: .pastWeek,
            geocode: "103644278",
            experienceLevel: .midSenior,
            remote: .remote,
            jobType: .fullTime,
            easyApply: true,
            under10Applicants: true
        )

        let items = params.buildQueryItems()

        #expect(items.contains { $0.name == "keyword" && $0.value == "Software Engineer" })
        #expect(items.contains { $0.name == "page" && $0.value == "2" })
        #expect(items.contains { $0.name == "sort_by" && $0.value == "recent" })
        #expect(items.contains { $0.name == "date_posted" && $0.value == "past_week" })
        #expect(items.contains { $0.name == "geo_code" && $0.value == "103644278" })
        #expect(items.contains { $0.name == "experience_level" && $0.value == "mid_senior" })
        #expect(items.contains { $0.name == "remote" && $0.value == "remote" })
        #expect(items.contains { $0.name == "job_type" && $0.value == "full_time" })
        #expect(items.contains { $0.name == "easy_apply" && $0.value == "true" })
        #expect(items.contains { $0.name == "under_10_applicants" && $0.value == "true" })
    }

    @Test func searchParamsOmitsOptionalParametersWhenNil() async throws {
        let params = RapidAPISearchParams(
            keyword: "Data Scientist",
            page: 1,
            sortBy: .relevant,
            datePosted: nil,
            geocode: nil,
            experienceLevel: nil,
            remote: nil,
            jobType: nil,
            easyApply: nil,
            under10Applicants: nil
        )

        let items = params.buildQueryItems()

        #expect(items.contains { $0.name == "keyword" })
        #expect(items.contains { $0.name == "page" })
        #expect(!items.contains { $0.name == "sort_by" })  // relevant is default
        #expect(!items.contains { $0.name == "date_posted" })
        #expect(!items.contains { $0.name == "geo_code" })
        #expect(!items.contains { $0.name == "experience_level" })
        #expect(!items.contains { $0.name == "remote" })
        #expect(!items.contains { $0.name == "job_type" })
        #expect(!items.contains { $0.name == "easy_apply" })
        #expect(!items.contains { $0.name == "under_10_applicants" })
    }

    @Test func searchParamsBooleanFiltersOnlyIncludedWhenTrue() async throws {
        let paramsTrue = RapidAPISearchParams(
            keyword: "test",
            easyApply: true,
            under10Applicants: true,
            hasVerifications: true,
            fairChanceEmployer: true
        )
        let itemsTrue = paramsTrue.buildQueryItems()
        #expect(itemsTrue.contains { $0.name == "easy_apply" })
        #expect(itemsTrue.contains { $0.name == "under_10_applicants" })
        #expect(itemsTrue.contains { $0.name == "has_verifications" })
        #expect(itemsTrue.contains { $0.name == "fair_chance_employer" })

        // false should not be included
        let paramsFalse = RapidAPISearchParams(
            keyword: "test",
            easyApply: false,
            under10Applicants: false,
            hasVerifications: false,
            fairChanceEmployer: false
        )
        let itemsFalse = paramsFalse.buildQueryItems()
        #expect(!itemsFalse.contains { $0.name == "easy_apply" })
        #expect(!itemsFalse.contains { $0.name == "under_10_applicants" })
        #expect(!itemsFalse.contains { $0.name == "has_verifications" })
        #expect(!itemsFalse.contains { $0.name == "fair_chance_employer" })
    }

    // MARK: - Enum Raw Value Tests

    @Test func sortByEnumRawValuesMatchAPI() async throws {
        #expect(RapidAPISearchParams.SortBy.recent.rawValue == "recent")
        #expect(RapidAPISearchParams.SortBy.relevant.rawValue == "relevant")
    }

    @Test func datePostedEnumRawValuesMatchAPI() async throws {
        #expect(RapidAPISearchParams.DatePosted.anytime.rawValue == "anytime")
        #expect(RapidAPISearchParams.DatePosted.pastMonth.rawValue == "past_month")
        #expect(RapidAPISearchParams.DatePosted.pastWeek.rawValue == "past_week")
        #expect(RapidAPISearchParams.DatePosted.past24Hours.rawValue == "past_24_hours")
    }

    @Test func experienceLevelEnumRawValuesMatchAPI() async throws {
        #expect(RapidAPISearchParams.ExperienceLevel.internship.rawValue == "internship")
        #expect(RapidAPISearchParams.ExperienceLevel.entryLevel.rawValue == "entry_level")
        #expect(RapidAPISearchParams.ExperienceLevel.associate.rawValue == "associate")
        #expect(RapidAPISearchParams.ExperienceLevel.midSenior.rawValue == "mid_senior")
        #expect(RapidAPISearchParams.ExperienceLevel.director.rawValue == "director")
        #expect(RapidAPISearchParams.ExperienceLevel.executive.rawValue == "executive")
    }

    @Test func remoteTypeEnumRawValuesMatchAPI() async throws {
        #expect(RapidAPISearchParams.RemoteType.onsite.rawValue == "on_site")
        #expect(RapidAPISearchParams.RemoteType.remote.rawValue == "remote")
        #expect(RapidAPISearchParams.RemoteType.hybrid.rawValue == "hybrid")
    }

    @Test func jobTypeEnumRawValuesMatchAPI() async throws {
        #expect(RapidAPISearchParams.JobType.fullTime.rawValue == "full_time")
        #expect(RapidAPISearchParams.JobType.partTime.rawValue == "part_time")
        #expect(RapidAPISearchParams.JobType.contract.rawValue == "contract")
        #expect(RapidAPISearchParams.JobType.temporary.rawValue == "temporary")
        #expect(RapidAPISearchParams.JobType.volunteer.rawValue == "volunteer")
        #expect(RapidAPISearchParams.JobType.internship.rawValue == "internship")
        #expect(RapidAPISearchParams.JobType.other.rawValue == "other")
    }

    // MARK: - JSON Decoding Tests

    @Test func searchResponseDecodesFromJSON() async throws {
        let json = """
        {
            "success": true,
            "cost": 1,
            "page": 1,
            "total": 100,
            "has_more": true,
            "data": [
                {
                    "id": "123",
                    "title": "iOS Developer",
                    "url": "https://www.linkedin.com/jobs/view/123",
                    "listed_at": "2026-01-20T10:00:00.000Z",
                    "is_promote": false,
                    "is_easy_apply": true,
                    "location": "Cupertino, CA",
                    "company": {
                        "id": "456",
                        "name": "Apple Inc",
                        "url": "https://apple.com",
                        "verified": true,
                        "logo": [
                            {
                                "url": "https://logo.example.com/apple.png",
                                "width": 100,
                                "height": 100
                            }
                        ]
                    }
                }
            ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(RapidAPISearchResponse.self, from: json)

        #expect(response.success == true)
        #expect(response.page == 1)
        #expect(response.total == 100)
        #expect(response.has_more == true)
        #expect(response.data?.count == 1)
        #expect(response.data?.first?.title == "iOS Developer")
        #expect(response.data?.first?.is_easy_apply == true)
        #expect(response.data?.first?.company?.name == "Apple Inc")
        #expect(response.data?.first?.company?.logo?.first?.url == "https://logo.example.com/apple.png")
    }

    @Test func searchResponseHandlesErrorResponse() async throws {
        let json = """
        {
            "success": false,
            "error": "Invalid API key",
            "message": "Please provide a valid RapidAPI key"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(RapidAPISearchResponse.self, from: json)

        #expect(response.success == false)
        #expect(response.data == nil)
        #expect(response.error == "Invalid API key")
        #expect(response.message == "Please provide a valid RapidAPI key")
    }

    @Test func jobDetailsResponseDecodesFromJSON() async throws {
        let json = """
        {
            "success": true,
            "cost": 1,
            "data": {
                "id": "123",
                "title": "Senior Software Engineer",
                "description": "We are looking for a senior engineer...",
                "job_url": "https://www.linkedin.com/jobs/view/123",
                "location": "San Francisco, CA",
                "level": "Mid-Senior level",
                "employment_status": "Full-time",
                "salary": {
                    "min_salary": 150000,
                    "max_salary": 200000,
                    "currency": "USD",
                    "pay_period": "yearly",
                    "salary_exists": true
                },
                "industries": ["Technology", "Software"],
                "job_functions": ["Engineering"],
                "benefits": ["Health Insurance", "401k"],
                "workplace_types": ["On-site"],
                "company": {
                    "name": "Tech Corp",
                    "url": "https://techcorp.com",
                    "description": "A tech company",
                    "staff_count": 5000,
                    "headquarter": "San Francisco, CA"
                }
            }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(RapidAPIJobDetailsResponse.self, from: json)

        #expect(response.success == true)
        #expect(response.data?.title == "Senior Software Engineer")
        #expect(response.data?.salary?.min_salary == 150000)
        #expect(response.data?.salary?.max_salary == 200000)
        #expect(response.data?.salary?.salary_exists == true)
        #expect(response.data?.industries?.count == 2)
        #expect(response.data?.benefits?.count == 2)
        #expect(response.data?.company?.name == "Tech Corp")
        #expect(response.data?.company?.staff_count == 5000)
    }

    @Test func salaryDecodesCorrectly() async throws {
        let json = """
        {
            "min_salary": 120000.5,
            "max_salary": 180000.0,
            "currency": "USD",
            "pay_period": "yearly",
            "salary_exists": true
        }
        """.data(using: .utf8)!

        let salary = try JSONDecoder().decode(RapidAPISalary.self, from: json)

        #expect(salary.min_salary == 120000.5)
        #expect(salary.max_salary == 180000.0)
        #expect(salary.currency == "USD")
        #expect(salary.pay_period == "yearly")
        #expect(salary.salary_exists == true)
    }

    @Test func nestedCompanyDecodesCorrectly() async throws {
        let json = """
        {
            "id": "789",
            "name": "Google",
            "url": "https://google.com",
            "verified": true,
            "logo": [
                {"url": "https://logo.example.com/google.png", "width": 200, "height": 200}
            ]
        }
        """.data(using: .utf8)!

        let company = try JSONDecoder().decode(RapidAPICompany.self, from: json)

        #expect(company.id == "789")
        #expect(company.name == "Google")
        #expect(company.url == "https://google.com")
        #expect(company.verified == true)
        #expect(company.logo?.count == 1)
        #expect(company.logo?.first?.width == 200)
    }

    // MARK: - Job Details Enrichment Tests

    @Test func jobDetailsEnrichesExistingJobPosting() async throws {
        let existingJob = JobPosting(
            company: "Old Company",
            role: "Old Role",
            location: "Old Location",
            category: "Software",
            aggregatorLink: "https://www.linkedin.com/jobs/view/123",
            aggregatorName: "LinkedIn"
        )

        let details = RapidAPIJobDetails(
            id: "123",
            title: "Senior Software Engineer",
            description: "We need a great engineer",
            job_url: "https://www.linkedin.com/jobs/view/123",
            location: "New York, NY",
            level: "Mid-Senior level",
            employment_status: "Full-time",
            salary: RapidAPISalary(
                min_salary: 150000,
                max_salary: 200000,
                currency: "USD",
                pay_period: "yearly",
                salary_exists: true
            ),
            industries: ["Technology"],
            job_functions: ["Engineering"],
            benefits: ["Health Insurance"],
            workplace_types: ["On-site"],
            company: RapidAPIDetailCompany(
                name: "New Company",
                url: "https://newcompany.com",
                description: "A company",
                staff_count: 1000,
                headquarter: "NYC"
            )
        )

        let enriched = details.enrichJobPosting(existingJob)

        #expect(enriched.company == "New Company")
        #expect(enriched.role == "Senior Software Engineer")
        #expect(enriched.location == "New York, NY")
        #expect(enriched.category == "Software")  // Preserved from original
        #expect(enriched.companyWebsite == "https://newcompany.com")
        #expect(enriched.aggregatorName == "LinkedIn")
        #expect(enriched.descriptionText != nil)
        #expect(enriched.descriptionText!.contains("We need a great engineer"))
        #expect(enriched.salaryDisplay != nil)
        #expect(enriched.salaryDisplay!.contains("150k"))
        #expect(enriched.salaryDisplay!.contains("200k"))
    }

    @Test func jobDetailsPreservesExistingWhenFieldsNil() async throws {
        let existingJob = JobPosting(
            company: "Existing Co",
            role: "Existing Role",
            location: "Existing Location",
            category: "Engineering",
            companyWebsite: "https://existing.com",
            aggregatorLink: "https://www.linkedin.com/jobs/view/123",
            aggregatorName: "LinkedIn",
            descriptionText: "Existing description"
        )

        let details = RapidAPIJobDetails(
            id: nil,
            title: nil,
            description: nil,
            job_url: nil,
            location: nil,
            level: nil,
            employment_status: nil,
            salary: nil,
            industries: nil,
            job_functions: nil,
            benefits: nil,
            workplace_types: nil,
            company: nil
        )

        let enriched = details.enrichJobPosting(existingJob)

        #expect(enriched.company == "Existing Co")
        #expect(enriched.role == "Existing Role")
        #expect(enriched.location == "Existing Location")
        #expect(enriched.companyWebsite == "https://existing.com")
        #expect(enriched.descriptionText == "Existing description")
    }
}
