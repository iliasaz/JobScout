//
//  RapidAPISearchView.swift
//  JobScout
//
//  Created by Claude on 1/29/26.
//

import SwiftUI

/// Search controls for RapidAPI Fresh LinkedIn Scraper
struct RapidAPISearchView: View {
    @Binding var searchField: String
    @Binding var selectedLocation: ScrapingDogLocation?
    @Binding var sortBy: RapidAPISearchParams.SortBy
    @Binding var datePosted: RapidAPISearchParams.DatePosted?
    @Binding var experienceLevel: RapidAPISearchParams.ExperienceLevel?
    @Binding var remoteType: RapidAPISearchParams.RemoteType?
    @Binding var jobType: RapidAPISearchParams.JobType?
    @Binding var easyApplyOnly: Bool
    @Binding var under10Applicants: Bool
    @Binding var isSearching: Bool
    
    let savedSearches: [JobSource]
    var onSearch: () -> Void
    var onClear: () -> Void
    var onSelectSearch: (JobSource) -> Void
    var onDeleteSearch: (String) -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            // Row 1: Search field with dropdown, Location, Date Posted, Sort By
            HStack(spacing: 12) {
                SearchFieldWithHistoryView(
                    searchField: $searchField,
                    placeholder: "Job title or keyword...",
                    savedSearches: savedSearches,
                    accentColor: .purple,
                    onSubmit: onSearch,
                    onSelectSearch: onSelectSearch,
                    onDeleteSearch: onDeleteSearch
                )

                Picker("Location", selection: $selectedLocation) {
                    Text("Any Location").tag(nil as ScrapingDogLocation?)
                    ForEach(ScrapingDogLocation.commonLocations) { location in
                        Text(location.name).tag(location as ScrapingDogLocation?)
                    }
                }
                .frame(maxWidth: 200)

                Picker("Date Posted", selection: $datePosted) {
                    Text("Any Time").tag(nil as RapidAPISearchParams.DatePosted?)
                    ForEach(RapidAPISearchParams.DatePosted.allCases, id: \.self) { date in
                        Text(date.displayName).tag(date as RapidAPISearchParams.DatePosted?)
                    }
                }
                .frame(maxWidth: 150)

                Picker("Sort", selection: $sortBy) {
                    ForEach(RapidAPISearchParams.SortBy.allCases, id: \.self) { sort in
                        Text(sort.displayName).tag(sort)
                    }
                }
                .frame(maxWidth: 130)
            }

            // Row 2: Experience Level, Remote Type, Job Type
            HStack(spacing: 12) {
                Picker("Experience", selection: $experienceLevel) {
                    Text("Any Level").tag(nil as RapidAPISearchParams.ExperienceLevel?)
                    ForEach(RapidAPISearchParams.ExperienceLevel.allCases, id: \.self) { level in
                        Text(level.displayName).tag(level as RapidAPISearchParams.ExperienceLevel?)
                    }
                }
                .frame(maxWidth: 160)

                Picker("Remote", selection: $remoteType) {
                    Text("Any").tag(nil as RapidAPISearchParams.RemoteType?)
                    ForEach(RapidAPISearchParams.RemoteType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type as RapidAPISearchParams.RemoteType?)
                    }
                }
                .frame(maxWidth: 120)

                Picker("Job Type", selection: $jobType) {
                    Text("Any Type").tag(nil as RapidAPISearchParams.JobType?)
                    ForEach(RapidAPISearchParams.JobType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type as RapidAPISearchParams.JobType?)
                    }
                }
                .frame(maxWidth: 130)

                Spacer()
            }

            // Row 3: Toggles + Action buttons
            HStack(spacing: 12) {
                Toggle("Easy Apply", isOn: $easyApplyOnly)
                    .toggleStyle(.checkbox)

                Toggle("< 10 Applicants", isOn: $under10Applicants)
                    .toggleStyle(.checkbox)

                Spacer()

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
                    .tint(.purple)
                    .disabled(searchField.isEmpty || isSearching)
                }
            }
        }
        .padding()
        .glassBackground(tint: .orange.opacity(0.5))
    }

    private func clearFilters() {
        searchField = ""
        selectedLocation = nil
        sortBy = .relevant
        datePosted = nil
        experienceLevel = nil
        remoteType = nil
        jobType = nil
        easyApplyOnly = false
        under10Applicants = false
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var searchField = ""
        @State private var selectedLocation: ScrapingDogLocation?
        @State private var sortBy: RapidAPISearchParams.SortBy = .relevant
        @State private var datePosted: RapidAPISearchParams.DatePosted?
        @State private var experienceLevel: RapidAPISearchParams.ExperienceLevel?
        @State private var remoteType: RapidAPISearchParams.RemoteType?
        @State private var jobType: RapidAPISearchParams.JobType?
        @State private var easyApplyOnly = false
        @State private var under10Applicants = false
        @State private var isSearching = false

        var body: some View {
            RapidAPISearchView(
                searchField: $searchField,
                selectedLocation: $selectedLocation,
                sortBy: $sortBy,
                datePosted: $datePosted,
                experienceLevel: $experienceLevel,
                remoteType: $remoteType,
                jobType: $jobType,
                easyApplyOnly: $easyApplyOnly,
                under10Applicants: $under10Applicants,
                isSearching: $isSearching,
                savedSearches: [
                    JobSource(
                        id: 1,
                        url: "https://www.linkedin.com/jobs/search/?keywords=iOS%20Engineer&f_E=mid_senior&f_WT=remote",
                        name: "iOS Engineer",
                        sourceType: "rapidapi",
                        lastFetchedAt: Date(),
                        createdAt: Date()
                    ),
                    JobSource(
                        id: 2,
                        url: "https://www.linkedin.com/jobs/search/?keywords=Swift%20Developer&f_AL=true",
                        name: "Swift Developer",
                        sourceType: "rapidapi",
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
