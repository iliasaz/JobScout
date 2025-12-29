//
//  JobScoutTests.swift
//  JobScoutTests
//
//  Created by Ilia Sazonov on 12/26/25.
//

import Testing
import Foundation
@testable import JobScout

struct JobScoutTests {

    // MARK: - JobPosting Tests

    @Test func jobPostingUniqueIdUsesCompanyLink() async throws {
        let job = JobPosting(
            company: "TestCo",
            role: "Engineer",
            location: "Remote",
            companyLink: "https://testco.com/jobs/123",
            aggregatorLink: "https://simplify.jobs/abc"
        )

        // ID should include the company link
        #expect(job.id.contains("https://testco.com/jobs/123"))
    }

    @Test func jobPostingExtractsCountryFromLocation() async throws {
        let usJob = JobPosting(company: "Co", role: "Dev", location: "San Francisco, CA")
        #expect(usJob.country == "USA")

        let canadaJob = JobPosting(company: "Co", role: "Dev", location: "Toronto, Canada")
        #expect(canadaJob.country == "Canada")

        let ukJob = JobPosting(company: "Co", role: "Dev", location: "London, UK")
        #expect(ukJob.country == "UK")

        let remoteJob = JobPosting(company: "Co", role: "Dev", location: "Remote")
        #expect(remoteJob.country == "USA") // Defaults to USA
    }

    @Test func jobPostingDetectsInternship() async throws {
        // Should detect "intern" in various positions
        let intern1 = JobPosting(company: "Co", role: "Software Engineering Intern", location: "Remote")
        #expect(intern1.isInternship == true)

        let intern2 = JobPosting(company: "Co", role: "Intern - Data Science", location: "Remote")
        #expect(intern2.isInternship == true)

        let intern3 = JobPosting(company: "Co", role: "Summer Internship", location: "Remote")
        #expect(intern3.isInternship == true)

        // Case insensitive
        let intern4 = JobPosting(company: "Co", role: "INTERN", location: "Remote")
        #expect(intern4.isInternship == true)

        // Should NOT detect as internship
        let notIntern1 = JobPosting(company: "Co", role: "Software Engineer", location: "Remote")
        #expect(notIntern1.isInternship == false)

        let notIntern2 = JobPosting(company: "Co", role: "Senior Developer", location: "Remote")
        #expect(notIntern2.isInternship == false)
    }

    @Test func jobPostingCanOverrideInternshipFlag() async throws {
        // Explicit false should override auto-detection
        let job = JobPosting(
            company: "Co",
            role: "Software Engineering Intern",
            location: "Remote",
            isInternship: false
        )
        #expect(job.isInternship == false)
    }

    // MARK: - PersistedJobPosting Tests

    @Test func persistedJobPostingFromReturnsNilWithoutLinks() async throws {
        let job = JobPosting(
            company: "TestCo",
            role: "Engineer",
            location: "Remote",
            companyLink: nil,
            aggregatorLink: nil
        )

        let draft = PersistedJobPosting.from(job, sourceId: 1)
        #expect(draft == nil)
    }

    @Test func persistedJobPostingFromUsesCompanyLinkAsUniqueLink() async throws {
        let job = JobPosting(
            company: "TestCo",
            role: "Engineer",
            location: "Remote",
            companyLink: "https://company.com/job",
            aggregatorLink: "https://simplify.jobs/xyz"
        )

        let draft = PersistedJobPosting.from(job, sourceId: 1)
        #expect(draft != nil)
        #expect(draft?.uniqueLink == "https://company.com/job")
    }

    @Test func persistedJobPostingFromFallsBackToAggregatorLink() async throws {
        let job = JobPosting(
            company: "TestCo",
            role: "Engineer",
            location: "Remote",
            companyLink: nil,
            aggregatorLink: "https://simplify.jobs/xyz"
        )

        let draft = PersistedJobPosting.from(job, sourceId: 1)
        #expect(draft != nil)
        #expect(draft?.uniqueLink == "https://simplify.jobs/xyz")
    }

    // MARK: - DeterministicTableParser Tests

    @Test func parserDetectsHTMLFormat() async throws {
        let parser = DeterministicTableParser()
        let html = "<table><tr><th>Company</th></tr></table>"
        let format = parser.detectFormat(html)
        #expect(format == .html)
    }

    @Test func parserDetectsMarkdownFormat() async throws {
        let parser = DeterministicTableParser()
        let markdown = "| Company | Role |\n|---|---|\n| Test | Dev |"
        let format = parser.detectFormat(markdown)
        #expect(format == .markdown)
    }

    @Test func parserDetectsMarkdownFormatWithSpacesInSeparator() async throws {
        // jobright.ai uses spaces around dashes in separator row
        let parser = DeterministicTableParser()
        let markdown = "| Company | Job Title |\n| ----- | --------- |\n| Test | Dev |"
        let format = parser.detectFormat(markdown)
        #expect(format == .markdown)
    }

    @Test func parserExtractsJobsFromMarkdownTable() async throws {
        let parser = DeterministicTableParser()
        let markdown = """
        | Company | Role | Location | Link |
        |---------|------|----------|------|
        | TestCo | Engineer | Remote | [Apply](https://test.com/job) |
        """

        let tables = parser.parseTables(markdown)
        #expect(tables.count == 1)

        let jobs = parser.extractJobs(from: tables)
        #expect(jobs.count == 1)
        #expect(jobs.first?.company == "TestCo")
        #expect(jobs.first?.role == "Engineer")
    }

    @Test func parserSkipsJobsWithoutLinks() async throws {
        let parser = DeterministicTableParser()
        // Job without any link should be skipped (inactive posting)
        let markdown = """
        | Company | Role | Location | Link |
        |---------|------|----------|------|
        | TestCo | Engineer | Remote | - |
        """

        let tables = parser.parseTables(markdown)
        let jobs = parser.extractJobs(from: tables)
        #expect(jobs.isEmpty)
    }

    @Test func parserExtractsJobsWithEmbeddedLinks() async throws {
        // Test jobright.ai format where links are embedded in Company and Job Title columns
        let parser = DeterministicTableParser()
        let markdown = """
| Company | Job Title | Location | Work Model | Date Posted |
|---------|-----------|----------|------------|-------------|
| **[Acme Corp](https://acme.com)** | **[Software Engineer](https://jobright.ai/jobs/123)** | San Francisco, CA | Remote | Dec 29 |
"""

        let tables = parser.parseTables(markdown)
        #expect(tables.count == 1)

        let jobs = parser.extractJobs(from: tables)
        #expect(jobs.count == 1)
        #expect(jobs.first?.company == "Acme Corp")
        #expect(jobs.first?.role == "Software Engineer")
        #expect(jobs.first?.location == "San Francisco, CA")
        // jobright.ai links are classified as aggregator links
        #expect(jobs.first?.aggregatorLink == "https://jobright.ai/jobs/123")
        #expect(jobs.first?.aggregatorName == "Jobright")
        // acme.com is the company link
        #expect(jobs.first?.companyLink == "https://acme.com")
    }

    // MARK: - ColumnMapping Tests

    @Test func columnMappingMatchesCompanyVariants() async throws {
        let headers1 = ["Company", "Role", "Location"]
        let mapping1 = ColumnMapping.from(headers: headers1)
        #expect(mapping1.company == 0)

        let headers2 = ["Employer", "Position", "City"]
        let mapping2 = ColumnMapping.from(headers: headers2)
        #expect(mapping2.company == 0)
        #expect(mapping2.role == 1)
    }
}
