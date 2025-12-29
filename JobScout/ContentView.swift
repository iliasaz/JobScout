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
    @State private var errorMessage: String?
    @State private var analysisInfo: String = ""
    @State private var searchText = ""
    @State private var selectedCategories: Set<String> = []

    private let parser = DeterministicTableParser()

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
                .disabled(isLoading)
            }

            // Analysis Info
            if !analysisInfo.isEmpty {
                Text(analysisInfo)
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
                    TableColumn("Apply") { job in
                        if let link = job.companyLink, !link.isEmpty,
                           let url = URL(string: link) {
                            Link("Apply", destination: url)
                                .foregroundStyle(.blue)
                        } else {
                            Text("-")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .width(min: 50, ideal: 60)
                    TableColumn("Job Site") { job in
                        if let link = job.simplifyLink, !link.isEmpty,
                           let url = URL(string: link) {
                            Link("Apply", destination: url)
                                .foregroundStyle(.green)
                        } else {
                            Text("-")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .width(min: 60, ideal: 70)
                }
            }
        }
        .padding()
        .frame(minWidth: 800, minHeight: 600)
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

        Task.detached {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let content = String(data: data, encoding: .utf8) ?? ""

                // Parse the content
                let format = parser.detectFormat(content)
                let tables = parser.parseTables(content)
                let parsedJobs = parser.extractJobs(from: tables)

                let info = "Format: \(format.rawValue) | Tables: \(tables.count) | Total rows: \(tables.reduce(0) { $0 + $1.rowCount })"

                await MainActor.run {
                    jobs = parsedJobs
                    selectedCategories.removeAll()  // Reset category filters
                    analysisInfo = info
                    isLoading = false

                    if parsedJobs.isEmpty && !tables.isEmpty {
                        errorMessage = "Found tables but couldn't extract job postings. Headers may not match expected format."
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Error: \(error.localizedDescription)"
                    isLoading = false
                }
            }
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
