//
//  JobInspectorView.swift
//  JobScout
//
//  Created by Ilia Sazonov on 12/30/25.
//

import SwiftUI

/// Inspector sidebar showing detailed job analysis
struct JobInspectorView: View {
    let job: JobPosting
    let analysis: JobAnalysisResult?
    let technologies: [JobTechnology]
    let onClose: () -> Void
    let onApplyClick: (URL) -> Void

    // Optional FTS highlighting
    var highlightedSummary: String?
    var highlightedTechnologies: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.role)
                        .font(.headline)
                        .lineLimit(2)
                    Text(job.company)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Summary section
                    if let summary = analysis?.summary, !summary.isEmpty {
                        SectionView(title: "Summary") {
                            if let highlighted = highlightedSummary, !highlighted.isEmpty {
                                HighlightText(highlighted, font: .callout)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(summary)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // Compensation section
                    if analysis?.salary != nil || analysis?.stock != nil {
                        SectionView(title: "Compensation") {
                            VStack(alignment: .leading, spacing: 8) {
                                // Salary
                                if let salary = analysis?.salary {
                                    HStack {
                                        Image(systemName: "dollarsign.circle.fill")
                                            .foregroundStyle(.green)
                                        Text(salary.displayString)
                                            .font(.callout)
                                    }
                                }

                                // Stock
                                if let stock = analysis?.stock, stock.hasStock {
                                    HStack(alignment: .top) {
                                        Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                                            .foregroundStyle(.blue)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(stock.type?.rawValue.uppercased() ?? "Equity")
                                                .font(.callout)
                                            if let details = stock.details {
                                                Text(details)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Technologies section
                    if !technologies.isEmpty {
                        SectionView(title: "Technologies") {
                            TechnologiesGridView(
                                technologies: technologies,
                                highlightedTechnologies: highlightedTechnologies
                            )
                        }
                    }

                    // Location section
                    SectionView(title: "Location") {
                        HStack {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(.orange)
                            Text(job.location)
                                .font(.callout)
                        }
                        if job.country != "USA" {
                            Text(job.country)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 24)
                        }
                    }

                    // Links section
                    if job.companyLink != nil || job.aggregatorLink != nil {
                        SectionView(title: "Apply") {
                            VStack(alignment: .leading, spacing: 8) {
                                if let link = job.companyLink, let url = URL(string: link) {
                                    LinkButton(title: "Company Career Page", url: url, color: .blue) {
                                        onApplyClick(url)
                                    }
                                }
                                if let link = job.aggregatorLink, let url = URL(string: link) {
                                    LinkButton(
                                        title: job.aggregatorName ?? "Job Aggregator",
                                        url: url,
                                        color: .green
                                    ) {
                                        onApplyClick(url)
                                    }
                                }
                            }
                        }
                    }

                    // Status section
                    SectionView(title: "Status") {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Status:")
                                    .foregroundStyle(.secondary)
                                Text(job.userStatus.rawValue.capitalized)
                                    .foregroundStyle(statusColor(job.userStatus))
                            }
                            .font(.callout)

                            if let date = job.statusChangedAt {
                                Text("Changed: \(formatDate(date))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if let lastViewed = job.lastViewed {
                                Text("Last viewed: \(formatDate(lastViewed))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Spacer(minLength: 20)
                }
                .padding()
            }
        }
        .frame(minWidth: 280, maxWidth: 320)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func statusColor(_ status: JobStatus) -> Color {
        switch status {
        case .new: return .primary
        case .applied: return .green
        case .ignored: return .secondary
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Section View

private struct SectionView<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            content
        }
    }
}

// MARK: - Technologies Grid View

private struct TechnologiesGridView: View {
    let technologies: [JobTechnology]
    var highlightedTechnologies: String?

    // Parse highlighted technologies to get list of terms to highlight
    private var highlightedTerms: Set<String> {
        guard let highlighted = highlightedTechnologies else { return [] }
        // Extract text between ** markers
        var terms = Set<String>()
        var current = highlighted.startIndex
        while current < highlighted.endIndex {
            if let openRange = highlighted.range(of: "**", range: current..<highlighted.endIndex),
               openRange.upperBound < highlighted.endIndex,
               let closeRange = highlighted.range(of: "**", range: openRange.upperBound..<highlighted.endIndex) {
                let term = String(highlighted[openRange.upperBound..<closeRange.lowerBound])
                    .lowercased()
                    .trimmingCharacters(in: .whitespaces)
                if !term.isEmpty {
                    terms.insert(term)
                }
                current = closeRange.upperBound
            } else {
                break
            }
        }
        return terms
    }

    // Check if a technology should be highlighted
    private func isHighlighted(_ tech: JobTechnology) -> Bool {
        guard !highlightedTerms.isEmpty else { return false }
        let techName = tech.technology.lowercased()
        return highlightedTerms.contains { term in
            techName.contains(term) || term.contains(techName)
        }
    }

    // Group technologies by category
    var groupedTechnologies: [(String, [JobTechnology])] {
        let grouped = Dictionary(grouping: technologies) { $0.category?.rawValue ?? "Other" }
        return grouped.sorted { $0.key < $1.key }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(groupedTechnologies, id: \.0) { category, techs in
                VStack(alignment: .leading, spacing: 4) {
                    Text(category)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    FlowLayout(spacing: 4) {
                        ForEach(techs) { tech in
                            TechBadge(technology: tech, isHighlighted: isHighlighted(tech))
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Tech Badge

private struct TechBadge: View {
    let technology: JobTechnology
    var isHighlighted: Bool = false

    var body: some View {
        HStack(spacing: 2) {
            if technology.isRequired {
                Image(systemName: "star.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.yellow)
            }
            Text(technology.technology)
                .font(.caption)
                .fontWeight(isHighlighted ? .bold : .regular)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isHighlighted ? Color.yellow.opacity(0.4) : badgeColor.opacity(0.15))
        .foregroundStyle(badgeColor)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isHighlighted ? Color.yellow : Color.clear, lineWidth: 2)
        )
    }

    var badgeColor: Color {
        switch technology.category {
        case .language: return .blue
        case .framework: return .purple
        case .database: return .orange
        case .cloud: return .cyan
        case .tool: return .green
        case .platform: return .indigo
        case .methodology: return .teal
        case .other, .none: return .gray
        }
    }
}

// MARK: - Link Button

private struct LinkButton: View {
    let title: String
    let url: URL
    let color: Color
    let action: () -> Void

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
            action()
        } label: {
            HStack {
                Image(systemName: "link")
                Text(title)
                    .font(.callout)
            }
            .foregroundStyle(color)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flow Layout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)

        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(result.sizes[index])
            )
        }
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> LayoutResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            sizes.append(size)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }

        let totalHeight = currentY + lineHeight
        return LayoutResult(
            size: CGSize(width: maxWidth, height: totalHeight),
            positions: positions,
            sizes: sizes
        )
    }

    private struct LayoutResult {
        var size: CGSize
        var positions: [CGPoint]
        var sizes: [CGSize]
    }
}
