//
//  SearchFieldWithHistory.swift
//  JobScout
//
//  Created by Claude on 2/5/26.
//

import SwiftUI

/// A search field with a dropdown for saved searches
/// Used by both ScrapingDog and RapidAPI search panels
struct SearchFieldWithHistoryView: View {
    @Binding var searchField: String
    let placeholder: String
    let savedSearches: [JobSource]
    let accentColor: Color
    var onSubmit: () -> Void
    var onSelectSearch: (JobSource) -> Void
    var onDeleteSearch: (String) -> Void
    
    @State private var isShowingDropdown = false
    
    var body: some View {
        HStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField(placeholder, text: $searchField)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        if !searchField.isEmpty {
                            onSubmit()
                        }
                    }

                if !searchField.isEmpty {
                    Button {
                        searchField = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            
            // Dropdown button for saved searches
            if !savedSearches.isEmpty {
                Divider()
                    .frame(height: 20)
                
                Button {
                    isShowingDropdown.toggle()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isShowingDropdown ? 180 : 0))
                        .animation(.easeInOut(duration: 0.2), value: isShowingDropdown)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .popover(isPresented: $isShowingDropdown, arrowEdge: .bottom) {
                    SearchHistoryList(
                        sources: savedSearches,
                        accentColor: accentColor,
                        onSelect: { source in
                            onSelectSearch(source)
                            isShowingDropdown = false
                        },
                        onDelete: onDeleteSearch
                    )
                    .frame(minWidth: 400, maxHeight: 300)
                }
            }
        }
        .background(.quaternary, in: .rect(cornerRadius: 8))
    }
}

// MARK: - Search History List

/// Generic list of saved searches
struct SearchHistoryList: View {
    let sources: [JobSource]
    let accentColor: Color
    let onSelect: (JobSource) -> Void
    let onDelete: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Saved Searches")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sources, id: \.id) { source in
                        SearchHistoryRow(
                            source: source,
                            accentColor: accentColor,
                            onSelect: { onSelect(source) },
                            onDelete: { onDelete(source.url) }
                        )
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// A single row in the search history list
struct SearchHistoryRow: View {
    let source: JobSource
    let accentColor: Color
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    /// Format the last fetched date
    private var lastFetchedText: String {
        guard let date = source.lastFetchedAt else {
            return "Never searched"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Searched \(formatter.localizedString(for: date, relativeTo: Date()))"
    }
    
    /// Extract display info from the search URL based on source type
    private var searchInfo: (keyword: String, filters: [String]) {
        switch source.sourceType {
        case "rapidapi":
            if let params = RapidAPISearchParams.fromSourceURL(source.url) {
                var filters: [String] = []
                if let exp = params.experienceLevel { filters.append(exp.displayName) }
                if let remote = params.remote { filters.append(remote.displayName) }
                if let jobType = params.jobType { filters.append(jobType.displayName) }
                if params.easyApply == true { filters.append("Easy Apply") }
                if params.under10Applicants == true { filters.append("<10 Applicants") }
                return (params.keyword, filters)
            }
        case "scrapingdog":
            if let params = ScrapingDogSearchParams.fromSourceURL(source.url) {
                var filters: [String] = []
                if let exp = params.experienceLevel { filters.append(exp.displayName) }
                if let workType = params.workType { filters.append(workType.displayName) }
                if let jobType = params.jobType { filters.append(jobType.displayName) }
                return (params.field, filters)
            }
        default:
            break
        }
        return (source.name, [])
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(searchInfo.keyword)
                    .font(.system(.body, design: .default))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if !searchInfo.filters.isEmpty {
                        Text(searchInfo.filters.joined(separator: " • "))
                            .font(.caption)
                            .foregroundStyle(accentColor)
                            .lineLimit(1)
                    }

                    Text(lastFetchedText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if isHovering {
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove saved search and its jobs")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .background(isHovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear))
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            onSelect()
        }
    }
}

#Preview {
    SearchFieldWithHistoryView(
        searchField: .constant("iOS Engineer"),
        placeholder: "Job title or keyword...",
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
        accentColor: .purple,
        onSubmit: {},
        onSelectSearch: { _ in },
        onDeleteSearch: { _ in }
    )
    .frame(width: 400)
    .padding()
}
