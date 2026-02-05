//
//  URLComboBox.swift
//  JobScout
//
//  Created by Ilia Sazonov on 12/29/25.
//

import SwiftUI

/// A combo box component for URL input with history dropdown
struct URLComboBox: View {
    @Binding var text: String
    let placeholder: String
    let sources: [JobSource]
    let onDelete: (String) -> Void
    var onSubmit: (() -> Void)? = nil

    @State private var isShowingDropdown = false
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .focused($isTextFieldFocused)
                .disableAutocorrection(true)
                .onSubmit {
                    onSubmit?()
                }

            // Dropdown button
            if !sources.isEmpty {
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
                    URLHistoryList(
                        sources: sources,
                        onSelect: { url in
                            text = url
                            isShowingDropdown = false
                        },
                        onDelete: onDelete
                    )
                    .frame(minWidth: 400, maxHeight: 300)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.background)
        .clipShape(.rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.separator)
        }
    }
}

/// List of URL history items
struct URLHistoryList: View {
    let sources: [JobSource]
    let onSelect: (String) -> Void
    let onDelete: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent Sources")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sources, id: \.id) { source in
                        URLHistoryRow(
                            source: source,
                            onSelect: { onSelect(source.url) },
                            onDelete: { onDelete(source.url) }
                        )
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// A single row in the URL history list
struct URLHistoryRow: View {
    let source: JobSource
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    /// Format the last fetched date
    private var lastFetchedText: String {
        guard let date = source.lastFetchedAt else {
            return "Never fetched"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Fetched \(formatter.localizedString(for: date, relativeTo: Date()))"
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(source.name)
                    .font(.system(.body, design: .default))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(source.url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

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
                .help("Remove source and its jobs")
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
    URLComboBox(
        text: .constant("https://github.com/SimplifyJobs/New-Grad-Positions/blob/dev/README.md"),
        placeholder: "GitHub README URL",
        sources: [
            JobSource(
                id: 1,
                url: "https://github.com/SimplifyJobs/New-Grad-Positions/blob/dev/README.md",
                name: "SimplifyJobs/New-Grad-Positions",
                lastFetchedAt: Date(),
                createdAt: Date()
            ),
            JobSource(
                id: 2,
                url: "https://github.com/SimplifyJobs/Summer2025-Internships/blob/dev/README.md",
                name: "SimplifyJobs/Summer2025-Internships",
                lastFetchedAt: Date().addingTimeInterval(-86400),
                createdAt: Date()
            ),
            JobSource(
                id: 3,
                url: "https://github.com/pittcsc/Summer2024-Internships/blob/dev/README.md",
                name: "pittcsc/Summer2024-Internships",
                lastFetchedAt: nil,
                createdAt: Date()
            )
        ],
        onDelete: { _ in }
    )
    .frame(width: 500)
    .padding()
}
