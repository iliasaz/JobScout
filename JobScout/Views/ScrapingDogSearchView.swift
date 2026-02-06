//
//  ScrapingDogSearchView.swift
//  JobScout
//
//  Created by Claude on 1/25/26.
//

import SwiftUI

/// Search controls for ScrapingDog LinkedIn job search
struct ScrapingDogSearchView: View {
    @Binding var searchField: String
    @Binding var selectedLocation: ScrapingDogLocation?
    @Binding var sortBy: ScrapingDogSearchParams.SortBy
    @Binding var jobType: ScrapingDogSearchParams.JobType?
    @Binding var experienceLevel: ScrapingDogSearchParams.ExperienceLevel?
    @Binding var workType: ScrapingDogSearchParams.WorkType?
    @Binding var isSearching: Bool
    
    let savedSearches: [JobSource]
    var onSearch: () -> Void
    var onClear: () -> Void
    var onSelectSearch: (JobSource) -> Void
    var onDeleteSearch: (String) -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            // Search field row with dropdown
            SearchFieldWithHistoryView(
                searchField: $searchField,
                placeholder: "Job title or company...",
                savedSearches: savedSearches,
                accentColor: .blue,
                onSubmit: onSearch,
                onSelectSearch: onSelectSearch,
                onDeleteSearch: onDeleteSearch
            )

            // Filters row
            HStack(spacing: 12) {
                // Location picker
                Picker("Location", selection: $selectedLocation) {
                    Text("Any Location").tag(nil as ScrapingDogLocation?)
                    ForEach(ScrapingDogLocation.commonLocations) { location in
                        Text(location.name).tag(location as ScrapingDogLocation?)
                    }
                }
                .frame(maxWidth: 200)

                // Sort by
                Picker("Posted", selection: $sortBy) {
                    ForEach(ScrapingDogSearchParams.SortBy.allCases, id: \.self) { sort in
                        Text(sort.displayName).tag(sort)
                    }
                }
                .frame(maxWidth: 150)

                // Job type
                Picker("Job Type", selection: $jobType) {
                    Text("Any Type").tag(nil as ScrapingDogSearchParams.JobType?)
                    ForEach(ScrapingDogSearchParams.JobType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type as ScrapingDogSearchParams.JobType?)
                    }
                }
                .frame(maxWidth: 130)

                Spacer()
            }

            // Second filter row
            HStack(spacing: 12) {
                // Experience level
                Picker("Experience", selection: $experienceLevel) {
                    Text("Any Level").tag(nil as ScrapingDogSearchParams.ExperienceLevel?)
                    ForEach(ScrapingDogSearchParams.ExperienceLevel.allCases, id: \.self) { level in
                        Text(level.displayName).tag(level as ScrapingDogSearchParams.ExperienceLevel?)
                    }
                }
                .frame(maxWidth: 160)

                // Work type
                Picker("Work Type", selection: $workType) {
                    Text("Any").tag(nil as ScrapingDogSearchParams.WorkType?)
                    ForEach(ScrapingDogSearchParams.WorkType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type as ScrapingDogSearchParams.WorkType?)
                    }
                }
                .frame(maxWidth: 120)

                Spacer()

                // Action buttons
                HStack(spacing: 8) {
                    Button("Clear") {
                        clearFilters()
                        onClear()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSearching)

                    Button {
                        onSearch()
                    } label: {
                        if isSearching {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Search LinkedIn")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(searchField.isEmpty || isSearching)
                }
            }
        }
        .padding()
        .glassBackground(tint: .blue.opacity(0.5))
    }

    private func clearFilters() {
        searchField = ""
        selectedLocation = nil
        sortBy = .relevant
        jobType = nil
        experienceLevel = nil
        workType = nil
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var searchField = ""
        @State private var selectedLocation: ScrapingDogLocation?
        @State private var sortBy: ScrapingDogSearchParams.SortBy = .relevant
        @State private var jobType: ScrapingDogSearchParams.JobType?
        @State private var experienceLevel: ScrapingDogSearchParams.ExperienceLevel?
        @State private var workType: ScrapingDogSearchParams.WorkType?
        @State private var isSearching = false

        var body: some View {
            ScrapingDogSearchView(
                searchField: $searchField,
                selectedLocation: $selectedLocation,
                sortBy: $sortBy,
                jobType: $jobType,
                experienceLevel: $experienceLevel,
                workType: $workType,
                isSearching: $isSearching,
                savedSearches: [
                    JobSource(
                        id: 1,
                        url: "https://www.linkedin.com/jobs/search/?keywords=iOS%20Developer&f_E=mid_senior_level&f_WT=remote",
                        name: "iOS Developer",
                        sourceType: "scrapingdog",
                        lastFetchedAt: Date(),
                        createdAt: Date()
                    ),
                    JobSource(
                        id: 2,
                        url: "https://www.linkedin.com/jobs/search/?keywords=Swift%20Engineer",
                        name: "Swift Engineer",
                        sourceType: "scrapingdog",
                        lastFetchedAt: Date().addingTimeInterval(-86400),
                        createdAt: Date()
                    )
                ],
                onSearch: {},
                onClear: {},
                onSelectSearch: { _ in },
                onDeleteSearch: { _ in }
            )
            .padding()
        }
    }

    return PreviewWrapper()
}
