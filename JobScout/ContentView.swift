//
//  ContentView.swift
//  JobScout
//
//  Created by Ilia Sazonov on 12/26/25.
//

import SwiftUI

struct ContentView: View {
    @State private var urlText = "https://github.com/SimplifyJobs/New-Grad-Positions/blob/dev/README.md"
    @State private var jobs: [JobPosting] = []
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var analysisInfo: String = ""
    @State private var searchText = ""
    @State private var selectedCategories: Set<String> = []
    @State private var savedJobCount: Int = 0
    @State private var lastSaveInfo: String?

    private let parser = DeterministicTableParser()
    private let repository = JobRepository()

    /// All unique categories from loaded jobs
    var availableCategories: [String] {
        Array(Set(jobs.map { $0.category })).sorted()
    }

    var filteredJobs: [JobPosting] {
        var result = jobs

        // Filter by selected categories (if any selected)
        if !selectedCategories.isEmpty {
            result = result.filter { selectedCategories.contains($0.category) }
        }

        // Filter by search text
        if !searchText.isEmpty {
            result = result.filter { job in
                job.company.localizedCaseInsensitiveContains(searchText) ||
                job.role.localizedCaseInsensitiveContains(searchText) ||
                job.location.localizedCaseInsensitiveContains(searchText) ||
                job.country.localizedCaseInsensitiveContains(searchText) ||
                job.category.localizedCaseInsensitiveContains(searchText)
            }
        }

        return result
    }

    var body: some View {
        VStack(spacing: 12) {
            // URL Input
            HStack {
                TextField("GitHub README URL", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)

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

                if !jobs.isEmpty {
                    Button {
                        saveJobsToDatabase()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Save")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLoading || isSaving)
                }

                Button("Load Saved") {
                    loadSavedJobs()
                }
                .buttonStyle(.bordered)
                .disabled(isLoading || isSaving)
            }

            // Analysis Info
            if !analysisInfo.isEmpty {
                Text(analysisInfo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                }
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)

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

                Text("\(filteredJobs.count) jobs\(selectedCategories.isEmpty ? "" : " (filtered)")")
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
                        if job.isFAANG {
                            Text("🔥")
                        } else {
                            Text("")
                        }
                    }
                    .width(min: 25, ideal: 30)
                    TableColumn("Company", value: \.company)
                        .width(min: 100, ideal: 150)
                    TableColumn("Role", value: \.role)
                        .width(min: 150, ideal: 250)
                    TableColumn("Location", value: \.location)
                        .width(min: 100, ideal: 150)
                    TableColumn("Country", value: \.country)
                        .width(min: 60, ideal: 80)
                    TableColumn("Category", value: \.category)
                        .width(min: 80, ideal: 120)
                    TableColumn("Posted") { job in
                        Text(job.datePosted ?? "-")
                    }
                    .width(min: 50, ideal: 80)
                    TableColumn("Company Site") { job in
                        if let link = job.companyLink, !link.isEmpty,
                           let url = URL(string: link) {
                            Link("Apply", destination: url)
                                .foregroundStyle(.blue)
                        } else {
                            Text("-")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .width(min: 80, ideal: 100)
                    TableColumn("Aggregator") { job in
                        if let link = job.simplifyLink, !link.isEmpty,
                           let url = URL(string: link) {
                            Link(aggregatorName(from: link), destination: url)
                                .foregroundStyle(.green)
                        } else {
                            Text("-")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .width(min: 70, ideal: 90)
                }
            }
        }
        .padding()
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            loadSavedJobCount()
        }
    }

    // MARK: - Methods

    private func fetchAndParse() {
        guard let url = rawGitHubURL(from: urlText) else {
            errorMessage = "Invalid URL"
            return
        }

        isLoading = true
        errorMessage = nil
        analysisInfo = ""

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let content = String(data: data, encoding: .utf8) ?? ""

                // Parse the content (parser is nonisolated, safe to call from any context)
                let format = parser.detectFormat(content)
                let tables = parser.parseTables(content)
                let parsedJobs = parser.extractJobs(from: tables)

                let info = "Format: \(format.rawValue) | Tables: \(tables.count) | Total rows: \(tables.reduce(0) { $0 + $1.rowCount })"

                // Update UI state (already on MainActor since Task inherits context)
                jobs = parsedJobs
                selectedCategories.removeAll()
                analysisInfo = info
                isLoading = false

                if parsedJobs.isEmpty && !tables.isEmpty {
                    errorMessage = "Found tables but couldn't extract job postings. Headers may not match expected format."
                }
            } catch {
                errorMessage = "Error: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }

    /// Extract aggregator name from URL
    private func aggregatorName(from urlString: String) -> String {
        let lowercased = urlString.lowercased()

        if lowercased.contains("simplify.jobs") || lowercased.contains("simplify.co") {
            return "Simplify"
        } else if lowercased.contains("linkedin.com") {
            return "LinkedIn"
        } else if lowercased.contains("indeed.com") {
            return "Indeed"
        } else if lowercased.contains("glassdoor.com") {
            return "Glassdoor"
        } else if lowercased.contains("lever.co") {
            return "Lever"
        } else if lowercased.contains("greenhouse.io") {
            return "Greenhouse"
        } else if lowercased.contains("workday.com") {
            return "Workday"
        } else if lowercased.contains("ziprecruiter.com") {
            return "ZipRecruiter"
        } else if lowercased.contains("monster.com") {
            return "Monster"
        } else if lowercased.contains("dice.com") {
            return "Dice"
        } else if lowercased.contains("wellfound.com") || lowercased.contains("angel.co") {
            return "Wellfound"
        } else if lowercased.contains("builtin.com") {
            return "BuiltIn"
        } else {
            // Try to extract domain name
            if let url = URL(string: urlString), let host = url.host {
                let parts = host.split(separator: ".")
                if parts.count >= 2 {
                    return String(parts[parts.count - 2]).capitalized
                }
            }
            return "Apply"
        }
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

    /// Save current jobs to database
    private func saveJobsToDatabase() {
        guard !jobs.isEmpty else { return }

        isSaving = true
        lastSaveInfo = nil
        errorMessage = nil

        Task {
            do {
                // Get or create source from current URL
                let sourceName = URL(string: urlText)?.lastPathComponent ?? "Unknown"
                let source = try await repository.getOrCreateSource(url: urlText, name: sourceName)

                // Save jobs
                let savedCount = try await repository.saveJobs(jobs, sourceId: source.id)

                // Update last fetched timestamp
                try await repository.updateLastFetched(sourceId: source.id)

                // Get total count
                let totalCount = try await repository.getJobCount()

                await MainActor.run {
                    savedJobCount = totalCount
                    lastSaveInfo = "Saved \(savedCount) new jobs (total: \(totalCount))"
                    isSaving = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Save error: \(error.localizedDescription)"
                    isSaving = false
                }
            }
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
                await MainActor.run {
                    savedJobCount = count
                }
            } catch {
                // Silently ignore - database might not exist yet
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

#Preview {
    ContentView()
}
