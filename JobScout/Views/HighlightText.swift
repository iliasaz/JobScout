//
//  HighlightText.swift
//  JobScout
//
//  Created by Ilia Sazonov on 12/31/25.
//

import SwiftUI

/// Renders text with **bold** markers as highlighted text
/// Used for displaying FTS search result highlights
struct HighlightText: View {
    let text: String
    let highlightColor: Color
    let font: Font

    init(_ text: String, highlightColor: Color = .yellow.opacity(0.4), font: Font = .body) {
        self.text = text
        self.highlightColor = highlightColor
        self.font = font
    }

    var body: some View {
        // Use AttributedString for proper background highlighting
        Text(attributedString)
            .font(font)
    }

    /// Create attributed string with background highlights
    private var attributedString: AttributedString {
        let segments = parseHighlights(text)
        var result = AttributedString()

        for segment in segments {
            var attributed = AttributedString(segment.text)
            if segment.isHighlighted {
                attributed.inlinePresentationIntent = .stronglyEmphasized
                attributed.backgroundColor = highlightColor
            }
            result.append(attributed)
        }

        return result
    }

    /// Parse text to find **highlighted** segments
    private func parseHighlights(_ input: String) -> [TextSegment] {
        var segments: [TextSegment] = []
        var currentIndex = input.startIndex

        while currentIndex < input.endIndex {
            // Look for opening **
            if let openRange = input.range(of: "**", range: currentIndex..<input.endIndex) {
                // Add text before the opening marker as non-highlighted
                if currentIndex < openRange.lowerBound {
                    let normalText = String(input[currentIndex..<openRange.lowerBound])
                    if !normalText.isEmpty {
                        segments.append(TextSegment(text: normalText, isHighlighted: false))
                    }
                }

                // Look for closing **
                let searchStart = openRange.upperBound
                if searchStart < input.endIndex,
                   let closeRange = input.range(of: "**", range: searchStart..<input.endIndex) {
                    // Found matching pair - add highlighted text
                    let highlightedText = String(input[openRange.upperBound..<closeRange.lowerBound])
                    if !highlightedText.isEmpty {
                        segments.append(TextSegment(text: highlightedText, isHighlighted: true))
                    }
                    currentIndex = closeRange.upperBound
                } else {
                    // No closing marker - treat the ** as literal text
                    segments.append(TextSegment(text: "**", isHighlighted: false))
                    currentIndex = openRange.upperBound
                }
            } else {
                // No more ** markers - add remaining text
                let remainingText = String(input[currentIndex...])
                if !remainingText.isEmpty {
                    segments.append(TextSegment(text: remainingText, isHighlighted: false))
                }
                break
            }
        }

        return segments
    }
}

/// A segment of text that may or may not be highlighted
private struct TextSegment {
    let text: String
    let isHighlighted: Bool
}

// MARK: - Preview

#Preview("Single highlight") {
    HighlightText("This is a **highlighted** word")
        .padding()
}

#Preview("Multiple highlights") {
    HighlightText("**React** and **TypeScript** skills required")
        .padding()
}

#Preview("No highlights") {
    HighlightText("No highlights here")
        .padding()
}

#Preview("Custom color") {
    HighlightText("Custom **green** highlight", highlightColor: .green.opacity(0.3))
        .padding()
}
