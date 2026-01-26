//
//  ContentView.swift
//  JobScout
//
//  Created by Ilia Sazonov on 12/26/25.
//

import AppKit
import SwiftUI

/// Filter for job type (intern/FAANG/all)
enum JobTypeFilter: String, CaseIterable {
    case all = "All"
    case internOnly = "Intern"
    case nonIntern = "Non-Intern"
    case faangOnly = "FAANG"
}

/// Filter for job status
enum StatusFilter: String, CaseIterable {
    case all = "All"
    case newOnly = "New Only"
    case appliedOnly = "Applied"
    case ignoredOnly = "Ignored"
    case excludeActioned = "Exclude Applied/Ignored"

    var displayName: String { rawValue }
}

/// Filter for job source
enum SourceFilter: String, CaseIterable {
    case all = "All Sources"
    case linkedInOnly = "LinkedIn"
    case githubOnly = "GitHub"

    var displayName: String { rawValue }
}

struct ContentView: View {
    @State private var urlText = "https://github.com/SimplifyJobs/New-Grad-Positions/blob/dev/README.md"
    @State private var urlSources: [JobSource] = []
    @State private var jobs: [JobPosting] = []
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var analysisInfo: String = ""
    @State private var searchText = ""
    @State private var selectedCategories: Set<String> = []
    @State private var jobTypeFilter: JobTypeFilter = .all
    @State private var statusFilter: StatusFilter = .all
    @State private var sourceFilter: SourceFilter = .all
    @State private var savedJobCount: Int = 0
    @State private var lastSaveInfo: String?
    @State private var showingClearConfirmation = false
    @State private var harmonizationInfo: String?
    @State private var isHarmonizing = false
    @State private var selectedJobId: Int?
    @State private var selectedJobAnalysis: JobAnalysisResult?
    @State private var selectedJobTechnologies: [JobTechnology] = []

    // FTS search state
    @State private var ftsSearchResults: [FTSSearchResult] = []
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var isSearching = false

    // ScrapingDog LinkedIn search state
    @State private var showScrapingDogSearch = false
    @State private var scrapingDogSearchField = ""
    @State private var scrapingDogLocation: ScrapingDogLocation?
    @State private var scrapingDogSortBy: ScrapingDogSearchParams.SortBy = .relevant
    @State private var scrapingDogJobType: ScrapingDogSearchParams.JobType?
    @State private var scrapingDogExperienceLevel: ScrapingDogSearchParams.ExperienceLevel?
    @State private var scrapingDogWorkType: ScrapingDogSearchParams.WorkType?
    @State private var isScrapingDogSearching = false
    @State private var scrapingDogSearchResults: [ScrapingDogJob] = []
    @State private var scrapingDogSearchError: String?
    @State private var scrapingDogSearchInfo: String?

    // Observe the analysis service for processing state
    @ObservedObject private var analysisService = JobAnalysisService.shared

    private let parser = DeterministicTableParser()
    private let repository = JobRepository()
    private let harmonizer = DataHarmonizer()
    private let linkClassifier = LinkClassifier()
    private let urlHistoryService = URLHistoryService.shared
    private let scrapingDogService = ScrapingDogService.shared

    /// All unique categories from loaded jobs
    var availableCategories: [String] {
        Array(Set(jobs.map { $0.category })).sorted()
    }

    /// Currently selected job for the inspector
    var selectedJob: JobPosting? {
        guard let id = selectedJobId else { return nil }
        return jobs.first { $0.persistedId == id }
    }

    /// Whether we're currently using FTS search results
    var isUsingFTSSearch: Bool {
        !searchText.isEmpty && !ftsSearchResults.isEmpty
    }

    /// Get FTS highlight info for a specific job
    func ftsHighlight(for job: JobPosting) -> FTSSearchResult? {
        guard let persistedId = job.persistedId else { return nil }
        return ftsSearchResults.first { $0.job.id == persistedId }
    }

    var filteredJobs: [JobPosting] {
        var result: [JobPosting]

        // If we have FTS search results, use those (already ranked by relevance)
        if isUsingFTSSearch {
            result = ftsSearchResults.map { $0.job.toJobPosting() }
        } else {
            result = jobs
        }

        // Filter by job type (intern/FAANG/all)
        switch jobTypeFilter {
        case .all:
            break
        case .internOnly:
            result = result.filter { $0.isInternship }
        case .nonIntern:
            result = result.filter { !$0.isInternship }
        case .faangOnly:
            result = result.filter { $0.isFAANG }
        }

        // Filter by status
        switch statusFilter {
        case .all:
            break
        case .newOnly:
            // Exclude applied, ignored, and viewed jobs
            result = result.filter { $0.userStatus == .new && $0.lastViewed == nil }
        case .appliedOnly:
            result = result.filter { $0.userStatus == .applied }
        case .ignoredOnly:
            result = result.filter { $0.userStatus == .ignored }
        case .excludeActioned:
            result = result.filter { $0.userStatus == .new }
        }

        // Filter by selected categories (if any selected)
        if !selectedCategories.isEmpty {
            result = result.filter { selectedCategories.contains($0.category) }
        }

        // Filter by source
        switch sourceFilter {
        case .all:
            break
        case .linkedInOnly:
            result = result.filter { $0.aggregatorName == "LinkedIn" }
        case .githubOnly:
            result = result.filter { $0.aggregatorName != "LinkedIn" }
        }

        // If using FTS search, results are already sorted by relevance
        // Otherwise, sort by posted date descending
        if !isUsingFTSSearch {
            // Sort by posted date descending (most recent first)
            // Jobs without dates go to the end
            result.sort { job1, job2 in
                let date1 = job1.datePosted ?? ""
                let date2 = job2.datePosted ?? ""
                // Empty dates sort to the end
                if date1.isEmpty && date2.isEmpty { return false }
                if date1.isEmpty { return false }
                if date2.isEmpty { return true }
                // ISO dates (YYYY-MM-DD) sort correctly as strings
                return date1 > date2
            }
        }

        return result
    }

    var body: some View {
        HSplitView {
            // Main content
            mainContent

            // Inspector sidebar (conditional)
            if let job = selectedJob, job.hasDetails {
                let highlight = ftsHighlight(for: job)
                JobInspectorView(
                    job: job,
                    analysis: selectedJobAnalysis,
                    technologies: selectedJobTechnologies,
                    onClose: { selectedJobId = nil },
                    onApplyClick: { _ in
                        // Track the click if job is persisted
                        if let jobId = job.persistedId {
                            Task {
                                do {
                                    try await repository.recordApplyClick(jobId: jobId)
                                    updateLocalJob(jobId: jobId) { job in
                                        job.updating(lastViewed: Date())
                                    }
                                } catch {
                                    // Silently ignore
                                }
                            }
                        }
                    },
                    highlightedSummary: highlight?.highlightedSummary,
                    highlightedTechnologies: highlight?.highlightedTechnologies
                )
            }
        }
        .onChange(of: selectedJobId) { _, newId in
            loadJobAnalysis(jobId: newId)
        }
        .onChange(of: analysisService.completedCount) { _, _ in
            // Reload jobs when analysis completes to show updated status/icons
            Task {
                await reloadJobsFromDatabase()
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 12) {
            // URL Input
            HStack {
                URLComboBox(
                    text: $urlText,
                    placeholder: "GitHub README URL",
                    sources: urlSources,
                    onDelete: { url in
                        Task {
                            await urlHistoryService.removeURL(url)
                            await loadURLSources()
                        }
                    },
                    onSubmit: {
                        // When Enter is pressed, fetch the current URL
                        fetchAndParse()
                    }
                )

                Button {
                    fetchAndParse()
                } label: {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Fetch")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || isSaving)

                Button("Fetch All") {
                    fetchAllSources()
                }
                .buttonStyle(.bordered)
                .disabled(isLoading || isSaving || urlSources.isEmpty)
                .help("Fetch from all saved sources")

                Button("Load Saved") {
                    loadSavedJobs()
                }
                .buttonStyle(.bordered)
                .disabled(isLoading || isSaving)
            }

            // ScrapingDog LinkedIn Search Panel
            if showScrapingDogSearch {
                ScrapingDogSearchView(
                    searchField: $scrapingDogSearchField,
                    selectedLocation: $scrapingDogLocation,
                    sortBy: $scrapingDogSortBy,
                    jobType: $scrapingDogJobType,
                    experienceLevel: $scrapingDogExperienceLevel,
                    workType: $scrapingDogWorkType,
                    isSearching: $isScrapingDogSearching,
                    onSearch: performScrapingDogSearch,
                    onClear: clearScrapingDogSearch
                )

                // ScrapingDog search results info
                if let error = scrapingDogSearchError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(error)
                            .foregroundStyle(.red)
                    }
                    .font(.caption)
                }

                if let info = scrapingDogSearchInfo {
                    Text(info)
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }

            // Analysis Info
            if !analysisInfo.isEmpty || isHarmonizing {
                HStack {
                    if !analysisInfo.isEmpty {
                        Text(analysisInfo)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if isHarmonizing {
                        ProgressView()
                            .controlSize(.small)
                        Text("Harmonizing...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let harmInfo = harmonizationInfo {
                        Text(harmInfo)
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
            }

            // Save Info
            if let saveInfo = lastSaveInfo {
                Text(saveInfo)
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            // Database Status
            if savedJobCount > 0 {
                Text("Database: \(savedJobCount) jobs saved")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Error Message
            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            // Search and Filters
            if !jobs.isEmpty {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search jobs...", text: $searchText)
                        .textFieldStyle(.plain)
                        .onChange(of: searchText) { _, newValue in
                            performDebouncedSearch(query: newValue)
                        }
                    if isSearching {
                        ProgressView()
                            .controlSize(.small)
                    }
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            ftsSearchResults = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)

                // Job type filter (intern/FAANG/all)
                HStack {
                    Picker("Job Type", selection: $jobTypeFilter) {
                        ForEach(JobTypeFilter.allCases, id: \.self) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 350)

                    Picker("Status", selection: $statusFilter) {
                        ForEach(StatusFilter.allCases, id: \.self) { filter in
                            Text(filter.displayName).tag(filter)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 200)

                    Picker("Source", selection: $sourceFilter) {
                        ForEach(SourceFilter.allCases, id: \.self) { filter in
                            Text(filter.displayName).tag(filter)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 150)
                }

                // Category filters
                if !availableCategories.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Text("Categories:")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            ForEach(availableCategories, id: \.self) { category in
                                CategoryFilterButton(
                                    category: category,
                                    isSelected: selectedCategories.contains(category),
                                    jobCount: jobs.filter { $0.category == category }.count
                                ) {
                                    if selectedCategories.contains(category) {
                                        selectedCategories.remove(category)
                                    } else {
                                        selectedCategories.insert(category)
                                    }
                                }
                            }

                            if !selectedCategories.isEmpty {
                                Button("Clear") {
                                    selectedCategories.removeAll()
                                }
                                .font(.caption)
                                .foregroundStyle(.red)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Text("\(filteredJobs.count) jobs\(jobTypeFilter == .all && selectedCategories.isEmpty ? "" : " (filtered)")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Job List
            if jobs.isEmpty && !isLoading {
                ContentUnavailableView(
                    "No Jobs Loaded",
                    systemImage: "briefcase",
                    description: Text("Enter a GitHub URL and click Fetch to load job postings")
                )
            } else {
                Table(filteredJobs) {
                    TableColumn("") { job in
                        HStack(spacing: 0) {
                            Text(job.isFAANG ? "🔥" : "")
                            Text(job.isInternship ? "🎓" : "")
                        }
                    }
                    .width(min: 30, ideal: 40)
                    TableColumn("Status") { job in
                        JobStatusCell(
                            job: job,
                            isProcessing: job.persistedId.map { analysisService.processingJobIds.contains($0) } ?? false,
                            formatDate: formatRelativeDate,
                            onApplied: { setJobStatus(job: job, status: .applied) },
                            onIgnored: { setJobStatus(job: job, status: .ignored) },
                            onReset: { setJobStatus(job: job, status: .new) },
                            onShowDetails: { selectedJobId = job.persistedId }
                        )
                    }
                    .width(min: 120, ideal: 150)
                    TableColumn("Company") { job in
                        if let website = job.companyWebsite, let url = URL(string: website) {
                            Button(job.company) {
                                NSWorkspace.shared.open(url)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(job.userStatus == .applied ? .green : .blue)
                            .underline()
                        } else if let highlight = ftsHighlight(for: job) {
                            HighlightText(highlight.highlightedCompany)
                                .foregroundStyle(jobRowColor(job))
                        } else {
                            Text(job.company)
                                .foregroundStyle(jobRowColor(job))
                        }
                    }
                    .width(min: 100, ideal: 150)
                    TableColumn("Role") { job in
                        if let highlight = ftsHighlight(for: job) {
                            HighlightText(highlight.highlightedRole)
                                .foregroundStyle(jobRowColor(job))
                        } else {
                            Text(job.role)
                                .foregroundStyle(jobRowColor(job))
                        }
                    }
                    .width(min: 150, ideal: 250)
                    TableColumn("Location") { job in
                        if let highlight = ftsHighlight(for: job) {
                            HighlightText(highlight.highlightedLocation)
                                .foregroundStyle(jobRowColor(job))
                        } else {
                            Text(job.location)
                                .foregroundStyle(jobRowColor(job))
                        }
                    }
                    .width(min: 100, ideal: 150)
                    TableColumn("Country") { job in
                        Text(job.country)
                            .foregroundStyle(jobRowColor(job))
                    }
                    .width(min: 60, ideal: 80)
                    TableColumn("Category") { job in
                        Text(job.category)
                            .foregroundStyle(jobRowColor(job))
                    }
                    .width(min: 80, ideal: 120)
                    TableColumn("Posted") { job in
                        if let date = job.parsedDate {
                            Text(formatRelativeDate(date))
                                .foregroundStyle(postedDateColor(date))
                        } else if let dateStr = job.datePosted, !dateStr.isEmpty {
                            Text(dateStr)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("-")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .width(min: 50, ideal: 80)
                    TableColumn("Apply") { job in
                        HStack(spacing: 8) {
                            if let link = job.companyLink, !link.isEmpty,
                               let url = URL(string: link) {
                                Button("Company") {
                                    openURLAndTrack(url: url, job: job)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.blue)
                            }
                            if let link = job.aggregatorLink, !link.isEmpty,
                               let url = URL(string: link) {
                                Button(job.aggregatorName ?? aggregatorName(from: link)) {
                                    openURLAndTrack(url: url, job: job)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.green)
                            }
                            if job.companyLink == nil && job.aggregatorLink == nil {
                                Text("-")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .width(min: 100, ideal: 140)
                    TableColumn("Salary") { job in
                        if let salary = job.salaryDisplay {
                            Text(salary)
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else if job.analysisStatus == .processing {
                            Text("...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("-")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .width(min: 80, ideal: 100)
                }
            }
        }
        .padding()
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            // Load saved jobs immediately for fast UI rendering
            loadSavedJobs()

            Task {
                // Populate default URLs if this is first run
                await urlHistoryService.populateDefaultsIfNeeded()
                await loadURLSources()

                // Auto-fetch from all sources in the background
                await MainActor.run {
                    fetchAllSourcesInBackground()
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    withAnimation {
                        showScrapingDogSearch.toggle()
                    }
                } label: {
                    Label(
                        showScrapingDogSearch ? "Hide LinkedIn Search" : "LinkedIn Search",
                        systemImage: showScrapingDogSearch ? "briefcase.fill" : "briefcase"
                    )
                }
                .help(showScrapingDogSearch ? "Hide LinkedIn job search" : "Search LinkedIn for jobs")
            }

            ToolbarItem(placement: .destructiveAction) {
                Button {
                    showingClearConfirmation = true
                } label: {
                    Label("Clear Database", systemImage: "trash")
                }
                .disabled(savedJobCount == 0 || isLoading || isSaving)
                .help("Delete all saved jobs from the database")
            }
        }
        .confirmationDialog(
            "Clear Database?",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete All Jobs", role: .destructive) {
                clearDatabase()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all \(savedJobCount) saved jobs from the database. This action cannot be undone.")
        }
    }

    // MARK: - Methods

    /// Perform debounced FTS search
    private func performDebouncedSearch(query: String) {
        // Cancel any pending search
        searchDebounceTask?.cancel()

        // Clear results if query is empty
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            ftsSearchResults = []
            return
        }

        // Debounce by 300ms
        searchDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(300))

            // Check if cancelled
            guard !Task.isCancelled else { return }

            await MainActor.run {
                isSearching = true
            }

            do {
                let results = try await repository.searchJobsFTS(query: query)

                await MainActor.run {
                    ftsSearchResults = results
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    // Fall back to showing all jobs if FTS fails
                    ftsSearchResults = []
                    isSearching = false
                    errorMessage = "Search error: \(error.localizedDescription)"
                }
            }
        }
    }

    private func fetchAndParse() {
        fetchFromURL(urlText)
    }

    /// Fetch from a specific URL, parse, harmonize, and auto-save
    private func fetchFromURL(_ sourceURL: String) {
        guard let url = rawGitHubURL(from: sourceURL) else {
            errorMessage = "Invalid URL"
            return
        }

        isLoading = true
        errorMessage = nil
        analysisInfo = ""
        harmonizationInfo = nil

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let content = String(data: data, encoding: .utf8) ?? ""

                // Parse the content (parser is nonisolated, safe to call from any context)
                let format = parser.detectFormat(content)
                let tables = parser.parseTables(content)
                var parsedJobs = parser.extractJobs(from: tables)

                // Apply max rows limit if configured
                let maxRows = UserDefaults.standard.integer(forKey: SettingsView.maxRowsKey)
                if maxRows > 0 && parsedJobs.count > maxRows {
                    parsedJobs = Array(parsedJobs.prefix(maxRows))
                }

                // Extract page title from content
                let pageTitle = extractPageTitle(from: content, sourceURL: sourceURL)

                let totalRows = tables.reduce(0) { $0 + $1.rowCount }
                let limitInfo = maxRows > 0 ? " (limited to \(maxRows))" : ""
                let info = "Format: \(format.rawValue) | Tables: \(tables.count) | Total rows: \(totalRows)\(limitInfo)"

                // Update parsing info
                analysisInfo = info
                isLoading = false

                if parsedJobs.isEmpty && !tables.isEmpty {
                    errorMessage = "Found tables but couldn't extract job postings. Headers may not match expected format."
                    return
                }

                if parsedJobs.isEmpty {
                    return
                }

                // Harmonize the jobs
                isHarmonizing = true

                let result = await harmonizer.harmonize(
                    jobs: parsedJobs,
                    pageTitle: pageTitle,
                    pageURL: sourceURL
                )

                // Show harmonization info
                if result.errors.isEmpty {
                    harmonizationInfo = "Category: \(result.inferredCategory)"
                } else {
                    harmonizationInfo = "Category: \(result.inferredCategory) (with warnings)"
                    errorMessage = result.errors.joined(separator: "\n")
                }

                isHarmonizing = false

                // Auto-save to database
                await saveJobsFromSource(result.jobs, sourceURL: sourceURL)

                // Save URL to history after successful fetch
                await saveURLToHistory(sourceURL)
            } catch {
                errorMessage = "Error: \(error.localizedDescription)"
                isLoading = false
                isHarmonizing = false
            }
        }
    }

    /// Fetch from all saved sources (blocks UI with loading indicator)
    private func fetchAllSources() {
        guard !urlSources.isEmpty else {
            // No sources - just load saved jobs
            loadSavedJobs()
            return
        }

        isLoading = true
        errorMessage = nil
        analysisInfo = "Fetching from \(urlSources.count) sources..."
        lastSaveInfo = nil

        Task {
            await performFetchFromAllSources()
            await MainActor.run {
                isLoading = false
            }
        }
    }

    /// Fetch from all saved sources in background (doesn't block UI)
    private func fetchAllSourcesInBackground() {
        guard !urlSources.isEmpty else { return }

        // Show subtle indicator without blocking
        analysisInfo = "Refreshing from \(urlSources.count) sources..."

        Task {
            await performFetchFromAllSources()
        }
    }

    /// Shared implementation for fetching from all sources
    private func performFetchFromAllSources() async {
        var totalNew = 0
        var totalUpdated = 0
        var totalSkipped = 0
        var errors: [String] = []

        for source in urlSources {
            do {
                let result = try await fetchAndSaveFromSource(source.url)
                totalNew += result.savedCount
                totalUpdated += result.updatedCount
                totalSkipped += result.skippedCount
            } catch {
                errors.append("\(source.name): \(error.localizedDescription)")
            }
        }

        // Get total count
        let totalCount = (try? await repository.getJobCount()) ?? 0

        await MainActor.run {
            savedJobCount = totalCount

            // Build summary
            var parts: [String] = []
            if totalNew > 0 { parts.append("\(totalNew) new") }
            if totalUpdated > 0 { parts.append("\(totalUpdated) updated") }
            if totalSkipped > 0 { parts.append("\(totalSkipped) skipped") }
            let summary = parts.isEmpty ? "No changes" : parts.joined(separator: ", ")
            lastSaveInfo = "\(summary) | Total: \(totalCount)"

            if !errors.isEmpty {
                errorMessage = errors.joined(separator: "\n")
            }

            analysisInfo = "Fetched from \(urlSources.count) sources"
        }

        // Queue jobs for analysis
        await analysisService.queueAllUnanalyzed()

        // Reload jobs from database
        await reloadJobsFromDatabase()
    }

    /// Fetch and save from a single source URL (used by fetchAllSources)
    private func fetchAndSaveFromSource(_ sourceURL: String) async throws -> SaveResult {
        guard let url = rawGitHubURL(from: sourceURL) else {
            throw URLError(.badURL)
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let content = String(data: data, encoding: .utf8) ?? ""

        // Parse
        let tables = parser.parseTables(content)
        var parsedJobs = parser.extractJobs(from: tables)

        // Apply limit
        let maxRows = UserDefaults.standard.integer(forKey: SettingsView.maxRowsKey)
        if maxRows > 0 && parsedJobs.count > maxRows {
            parsedJobs = Array(parsedJobs.prefix(maxRows))
        }

        guard !parsedJobs.isEmpty else {
            return SaveResult(savedCount: 0, skippedCount: 0, updatedCount: 0)
        }

        // Harmonize
        let pageTitle = extractPageTitle(from: content, sourceURL: sourceURL)
        let result = await harmonizer.harmonize(
            jobs: parsedJobs,
            pageTitle: pageTitle,
            pageURL: sourceURL
        )

        // Save
        let sourceName = URL(string: sourceURL)?.lastPathComponent ?? "Unknown"
        let source = try await repository.getOrCreateSource(url: sourceURL, name: sourceName)
        let saveResult = try await repository.saveJobs(result.jobs, sourceId: source.id)
        try await repository.updateLastFetched(sourceId: source.id)

        return saveResult
    }

    /// Extract page title from markdown/HTML content
    private func extractPageTitle(from content: String, sourceURL: String? = nil) -> String {
        // Try markdown heading first (# Title)
        // Look for first line that starts with # and space
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                let title = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !title.isEmpty {
                    return title
                }
            }
        }

        // Try HTML title tag
        if let startRange = content.range(of: "<title>", options: .caseInsensitive),
           let endRange = content.range(of: "</title>", options: .caseInsensitive),
           startRange.upperBound < endRange.lowerBound {
            let title = String(content[startRange.upperBound..<endRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                return title
            }
        }

        // Fall back to URL-based title
        let urlForTitle = sourceURL ?? urlText
        if let url = URL(string: urlForTitle) {
            let pathComponents = url.pathComponents.filter { $0 != "/" }
            if pathComponents.count >= 2 {
                return pathComponents[pathComponents.count - 2] + "/" + pathComponents[pathComponents.count - 1]
            }
        }

        return "Job Listings"
    }

    /// Extract aggregator name from URL using LinkClassifier
    private func aggregatorName(from urlString: String) -> String {
        if let name = linkClassifier.aggregatorName(from: urlString) {
            return name
        }

        // Fall back to domain name extraction
        if let name = linkClassifier.extractDomainName(from: urlString) {
            return name
        }

        return "Apply"
    }

    /// Converts a GitHub blob URL to raw.githubusercontent.com URL
    private func rawGitHubURL(from urlString: String) -> URL? {
        guard let url = URL(string: urlString),
              url.host == "github.com" else {
            return URL(string: urlString)
        }

        var components = url.pathComponents.filter { $0 != "/" }
        guard components.count >= 4, components[2] == "blob" else {
            return URL(string: urlString)
        }

        components.remove(at: 2)
        let rawPath = components.joined(separator: "/")
        return URL(string: "https://raw.githubusercontent.com/\(rawPath)")
    }


    /// Reload jobs from database without resetting UI state
    private func reloadJobsFromDatabase() async {
        do {
            let persistedJobs = try await repository.getJobs()
            let loadedJobs = persistedJobs.map { $0.toJobPosting() }

            await MainActor.run {
                jobs = loadedJobs
            }
        } catch {
            // Silently ignore reload errors
        }
    }

    /// Load jobs from database
    private func loadSavedJobs() {
        isLoading = true
        errorMessage = nil
        analysisInfo = ""
        lastSaveInfo = nil

        Task {
            do {
                let persistedJobs = try await repository.getJobs()

                // Convert to JobPosting
                let loadedJobs = persistedJobs.map { $0.toJobPosting() }
                let totalCount = try await repository.getJobCount()

                await MainActor.run {
                    jobs = loadedJobs
                    savedJobCount = totalCount
                    selectedCategories.removeAll()
                    jobTypeFilter = .all
                    analysisInfo = "Loaded \(loadedJobs.count) jobs from database"
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Load error: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }

    /// Load saved job count on appear
    private func loadSavedJobCount() {
        Task {
            do {
                let count = try await repository.getJobCount()
                savedJobCount = count
            } catch {
                // Silently ignore - database might not exist yet
            }
        }
    }

    /// Clear all data from the database
    private func clearDatabase() {
        isLoading = true
        errorMessage = nil
        lastSaveInfo = nil

        Task {
            do {
                try await repository.deleteAllData()

                jobs = []
                savedJobCount = 0
                selectedCategories.removeAll()
                jobTypeFilter = .all
                analysisInfo = "Database cleared"
                isLoading = false

                // Repopulate default URLs and refresh the dropdown
                await urlHistoryService.populateDefaultsIfNeeded()
                await loadURLSources()
            } catch {
                errorMessage = "Clear error: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }

    /// Load URL sources from database
    @MainActor
    private func loadURLSources() async {
        urlSources = await urlHistoryService.getSources()
    }

    /// Save URL to history (creates or updates source in database)
    private func saveURLToHistory(_ url: String? = nil) async {
        await urlHistoryService.addURL(url ?? urlText)
        await loadURLSources()
    }

    /// Save jobs from a specific source URL (used by fetchFromURL)
    private func saveJobsFromSource(_ jobsToSave: [JobPosting], sourceURL: String) async {
        guard !jobsToSave.isEmpty else { return }

        isSaving = true
        lastSaveInfo = nil

        do {
            // Get or create source
            let sourceName = URL(string: sourceURL)?.lastPathComponent ?? "Unknown"
            let source = try await repository.getOrCreateSource(url: sourceURL, name: sourceName)

            // Save jobs
            let result = try await repository.saveJobs(jobsToSave, sourceId: source.id)

            // Update last fetched timestamp
            try await repository.updateLastFetched(sourceId: source.id)

            // Get total count
            let totalCount = try await repository.getJobCount()

            await MainActor.run {
                savedJobCount = totalCount
                // Build save info message
                var parts: [String] = []
                if result.savedCount > 0 {
                    parts.append("\(result.savedCount) new")
                }
                if result.updatedCount > 0 {
                    parts.append("\(result.updatedCount) updated")
                }
                if result.skippedCount > 0 {
                    parts.append("\(result.skippedCount) skipped (no links)")
                }
                let summary = parts.isEmpty ? "No changes" : parts.joined(separator: ", ")
                lastSaveInfo = "\(summary) | Total: \(totalCount)"
                isSaving = false
            }

            // Queue saved jobs for analysis and start processing
            if result.savedCount > 0 {
                await analysisService.queueAllUnanalyzed()
            }

            // Reload jobs from database to show updated state
            await reloadJobsFromDatabase()
        } catch {
            await MainActor.run {
                errorMessage = "Save error: \(error.localizedDescription)"
                isSaving = false
            }
        }
    }

    /// Open URL in browser and track the click in database
    private func openURLAndTrack(url: URL, job: JobPosting) {
        // Open the URL
        NSWorkspace.shared.open(url)

        // Track the click if job is persisted
        if let jobId = job.persistedId {
            Task {
                do {
                    try await repository.recordApplyClick(jobId: jobId)
                    // Update the local job's lastViewed
                    updateLocalJob(jobId: jobId) { job in
                        job.updating(lastViewed: Date())
                    }
                } catch {
                    // Silently ignore tracking errors - don't interrupt user flow
                }
            }
        }
    }

    /// Update a local job in the jobs array
    private func updateLocalJob(jobId: Int, transform: (JobPosting) -> JobPosting) {
        if let index = jobs.firstIndex(where: { $0.persistedId == jobId }) {
            jobs[index] = transform(jobs[index])
        }
    }

    /// Format posted date for display (relative to now)
    private func formatRelativeDate(_ date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)

        // Future dates (shouldn't happen, but handle gracefully)
        if interval < 0 {
            return "Upcoming"
        }

        if interval < 86400 {
            return "Today"
        } else if interval < 172800 {
            return "Yesterday"
        } else if interval < 604800 {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        } else if interval < 2592000 {
            let weeks = Int(interval / 604800)
            return "\(weeks)w ago"
        } else if interval < 31536000 {
            let months = Int(interval / 2592000)
            return "\(months)mo ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM yyyy"
            return formatter.string(from: date)
        }
    }

    /// Color for posted date based on recency
    private func postedDateColor(_ date: Date) -> Color {
        let interval = Date().timeIntervalSince(date)

        if interval < 86400 {
            return .green  // Today
        } else if interval < 259200 {
            return .blue   // 1-3 days
        } else if interval < 604800 {
            return .primary  // 3-7 days
        } else if interval < 1209600 {
            return .secondary  // 1-2 weeks
        } else {
            return .secondary.opacity(0.7)  // Older
        }
    }

    /// Set job status and update local state
    private func setJobStatus(job: JobPosting, status: JobStatus) {
        guard let jobId = job.persistedId else { return }

        Task {
            do {
                try await repository.setJobStatus(jobId: jobId, status: status)
                // Update local state preserving all fields
                updateLocalJob(jobId: jobId) { job in
                    job.updating(
                        userStatus: status,
                        statusChangedAt: status == .new ? .some(nil) : .some(Date())
                    )
                }
            } catch {
                errorMessage = "Failed to update status: \(error.localizedDescription)"
            }
        }
    }

    /// Color for job row based on status
    private func jobRowColor(_ job: JobPosting) -> Color {
        switch job.userStatus {
        case .new:
            return .primary
        case .applied:
            return .green
        case .ignored:
            return .secondary.opacity(0.5)
        }
    }

    /// Load job analysis data for inspector
    private func loadJobAnalysis(jobId: Int?) {
        guard let jobId = jobId else {
            selectedJobAnalysis = nil
            selectedJobTechnologies = []
            return
        }

        Task {
            do {
                let analysis = try await repository.getJobAnalysis(jobId: jobId)
                let technologies = try await repository.getJobTechnologies(jobId: jobId)

                await MainActor.run {
                    selectedJobAnalysis = analysis
                    selectedJobTechnologies = technologies
                }
            } catch {
                // Silently handle - job may not have analysis
                await MainActor.run {
                    selectedJobAnalysis = nil
                    selectedJobTechnologies = []
                }
            }
        }
    }

    // MARK: - ScrapingDog LinkedIn Search

    /// Perform ScrapingDog LinkedIn job search
    private func performScrapingDogSearch() {
        guard !scrapingDogSearchField.isEmpty else { return }

        isScrapingDogSearching = true
        scrapingDogSearchError = nil
        scrapingDogSearchInfo = nil

        Task {
            do {
                let params = ScrapingDogSearchParams(
                    field: scrapingDogSearchField,
                    geoid: scrapingDogLocation?.id,
                    page: 1,
                    sortBy: scrapingDogSortBy,
                    jobType: scrapingDogJobType,
                    experienceLevel: scrapingDogExperienceLevel,
                    workType: scrapingDogWorkType
                )

                let results = try await scrapingDogService.searchJobs(params: params)

                await MainActor.run {
                    scrapingDogSearchResults = results
                    isScrapingDogSearching = false

                    if results.isEmpty {
                        scrapingDogSearchInfo = "No jobs found matching your search criteria."
                    } else {
                        scrapingDogSearchInfo = "Found \(results.count) jobs. Saving to database..."
                    }
                }

                // Save results to database if we have any
                if !results.isEmpty {
                    await saveScrapingDogJobs(results)
                }
            } catch {
                await MainActor.run {
                    isScrapingDogSearching = false
                    scrapingDogSearchError = error.localizedDescription
                }
            }
        }
    }

    /// Clear ScrapingDog search state
    private func clearScrapingDogSearch() {
        scrapingDogSearchResults = []
        scrapingDogSearchError = nil
        scrapingDogSearchInfo = nil
    }

    /// Save ScrapingDog search results to database
    private func saveScrapingDogJobs(_ jobs: [ScrapingDogJob]) async {
        // Convert to JobPostings
        let jobPostings = jobs.compactMap { $0.toJobPosting() }

        guard !jobPostings.isEmpty else {
            await MainActor.run {
                scrapingDogSearchInfo = "No valid jobs to save."
            }
            return
        }

        do {
            // Create a source for ScrapingDog searches
            let sourceURL = "scrapingdog://search/\(scrapingDogSearchField.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? scrapingDogSearchField)"
            let source = try await repository.getOrCreateSource(url: sourceURL, name: "LinkedIn Search: \(scrapingDogSearchField)")

            // Save jobs
            let result = try await repository.saveJobs(jobPostings, sourceId: source.id)

            // Update last fetched timestamp
            try await repository.updateLastFetched(sourceId: source.id)

            // Get total count
            let totalCount = try await repository.getJobCount()

            await MainActor.run {
                savedJobCount = totalCount

                // Build save info message
                var parts: [String] = []
                if result.savedCount > 0 {
                    parts.append("\(result.savedCount) new")
                }
                if result.updatedCount > 0 {
                    parts.append("\(result.updatedCount) updated")
                }
                if result.skippedCount > 0 {
                    parts.append("\(result.skippedCount) skipped")
                }
                let summary = parts.isEmpty ? "No changes" : parts.joined(separator: ", ")
                scrapingDogSearchInfo = "LinkedIn: \(summary) | Total: \(totalCount)"
            }

            // Queue saved jobs for analysis
            if result.savedCount > 0 {
                await analysisService.queueAllUnanalyzed()
            }

            // Reload jobs from database to show new results
            await reloadJobsFromDatabase()
        } catch {
            await MainActor.run {
                scrapingDogSearchError = "Failed to save jobs: \(error.localizedDescription)"
            }
        }
    }
}


// MARK: - Category Filter Button

struct CategoryFilterButton: View {
    let category: String
    let isSelected: Bool
    let jobCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.caption)
                Text("\(category) (\(jobCount))")
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.1))
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Job Status Cell

struct JobStatusCell: View {
    let job: JobPosting
    let isProcessing: Bool
    let formatDate: (Date) -> String
    let onApplied: () -> Void
    let onIgnored: () -> Void
    let onReset: () -> Void
    let onShowDetails: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            // LEFT SIDE: Actions and final states (left-aligned)
            statusSection

            Spacer(minLength: 4)

            // RIGHT SIDE: Intermediate actions/states (right-aligned)
            indicatorsSection
        }
    }

    /// Left side: Status actions and final states
    @ViewBuilder
    private var statusSection: some View {
        switch job.userStatus {
        case .new:
            // Show action buttons for new jobs
            HStack(spacing: 4) {
                Button {
                    onApplied()
                } label: {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.green.opacity(0.7))
                .help("Mark as Applied")

                Button {
                    onIgnored()
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary.opacity(0.7))
                .help("Mark as Ignored")
            }

        case .applied:
            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 2) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                        Text("Applied")
                            .font(.caption)
                    }
                    .foregroundStyle(.green)
                    if let date = job.statusChangedAt {
                        Text(formatDate(date))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Button {
                    onReset()
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary.opacity(0.5))
                .help("Reset to New")
            }

        case .ignored:
            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 2) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                        Text("Ignored")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    if let date = job.statusChangedAt {
                        Text(formatDate(date))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Button {
                    onReset()
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary.opacity(0.5))
                .help("Reset to New")
            }
        }
    }

    /// Right side: Processing status, viewed indicator, details icon
    @ViewBuilder
    private var indicatorsSection: some View {
        HStack(spacing: 6) {
            // Processing spinner
            if isProcessing {
                ProgressView()
                    .controlSize(.small)
                    .help("Analyzing job description...")
            }

            // Viewed indicator
            if let lastViewed = job.lastViewed {
                Image(systemName: "eye.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.blue.opacity(0.6))
                    .help("Last viewed: \(formatFullDate(lastViewed))")
            }

            // Details available indicator (rightmost)
            if job.hasDetails {
                Button {
                    onShowDetails()
                } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.purple.opacity(0.7))
                .help("View job details")
            }
        }
    }

    /// Format date with full detail for tooltip
    private func formatFullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    ContentView()
}
