//
//  ResumeTextService.swift
//  JobScout
//
//  Created by Claude on 1/11/26.
//

import Foundation
import NaturalLanguage
import PDFKit

/// Service for extracting text from PDF resumes and chunking the text
actor ResumeTextService {
    static let shared = ResumeTextService()

    // Chunking configuration optimized for resume content
    private let targetChunkSize = 500
    private let minChunkSize = 50
    private let maxChunkSize = 1000

    /// Extract text from PDF data using PDFKit
    /// - Parameter pdfData: The raw PDF file data
    /// - Returns: The extracted text content
    /// - Throws: ResumeTextError if extraction fails
    func extractText(from pdfData: Data) async throws -> String {
        guard let pdfDocument = PDFDocument(data: pdfData) else {
            throw ResumeTextError.extractionFailed("Failed to load PDF document")
        }

        var fullText = ""

        for pageIndex in 0..<pdfDocument.pageCount {
            guard let page = pdfDocument.page(at: pageIndex) else { continue }

            if let pageText = page.string {
                if !fullText.isEmpty {
                    fullText += "\n\n"
                }
                fullText += pageText
            }
        }

        let trimmedText = fullText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedText.isEmpty else {
            throw ResumeTextError.emptyContent
        }

        return trimmedText
    }

    /// Chunk the extracted text into smaller segments using sentence-based chunking
    /// - Parameter text: The text to chunk
    /// - Returns: An array of text chunks with metadata
    /// - Throws: ResumeTextError if chunking fails
    func chunkText(_ text: String) async throws -> [TextChunk] {
        guard !text.isEmpty else {
            throw ResumeTextError.emptyContent
        }

        // Split text into sentences
        let sentences = splitIntoSentences(text)

        guard !sentences.isEmpty else {
            // If no sentences found, create a single chunk from the whole text
            return [TextChunk(
                index: 0,
                content: text,
                characterCount: text.count,
                wordCount: countWords(text)
            )]
        }

        var chunks: [TextChunk] = []
        var currentChunk = ""
        var chunkIndex = 0

        for sentence in sentences {
            let potentialChunk = currentChunk.isEmpty ? sentence : currentChunk + " " + sentence

            if potentialChunk.count > maxChunkSize && !currentChunk.isEmpty {
                // Current chunk is full, save it and start new one
                chunks.append(createChunk(content: currentChunk, index: chunkIndex))
                chunkIndex += 1
                currentChunk = sentence
            } else if potentialChunk.count >= targetChunkSize {
                // Reached target size, save chunk
                chunks.append(createChunk(content: potentialChunk, index: chunkIndex))
                chunkIndex += 1
                currentChunk = ""
            } else {
                // Keep accumulating
                currentChunk = potentialChunk
            }
        }

        // Don't forget the last chunk
        if !currentChunk.isEmpty {
            // Merge with previous chunk if too small
            if currentChunk.count < minChunkSize && !chunks.isEmpty {
                let lastChunk = chunks.removeLast()
                let mergedContent = lastChunk.content + " " + currentChunk
                chunks.append(createChunk(content: mergedContent, index: lastChunk.index))
            } else {
                chunks.append(createChunk(content: currentChunk, index: chunkIndex))
            }
        }

        return chunks
    }

    /// Extract text from PDF and chunk it in one operation
    /// - Parameter pdfData: The raw PDF file data
    /// - Returns: A tuple containing the full extracted text and the chunks
    /// - Throws: ResumeTextError if either operation fails
    func extractAndChunk(from pdfData: Data) async throws -> (text: String, chunks: [TextChunk]) {
        let text = try await extractText(from: pdfData)
        let chunks = try await chunkText(text)
        return (text, chunks)
    }

    // MARK: - Private Helpers

    private func splitIntoSentences(_ text: String) -> [String] {
        var sentences: [String] = []

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
            return true
        }

        return sentences
    }

    private func countWords(_ text: String) -> Int {
        let words = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        return words.count
    }

    private func createChunk(content: String, index: Int) -> TextChunk {
        TextChunk(
            index: index,
            content: content,
            characterCount: content.count,
            wordCount: countWords(content)
        )
    }
}

/// Represents a chunk of text with metadata
struct TextChunk: Sendable {
    let index: Int
    let content: String
    let characterCount: Int
    let wordCount: Int
}

/// Errors specific to resume text processing
enum ResumeTextError: LocalizedError {
    case extractionFailed(String)
    case chunkingFailed(String)
    case emptyContent
    case unsupportedPlatform

    var errorDescription: String? {
        switch self {
        case .extractionFailed(let reason):
            return "Failed to extract text from PDF: \(reason)"
        case .chunkingFailed(let reason):
            return "Failed to chunk text: \(reason)"
        case .emptyContent:
            return "The PDF contains no extractable text content."
        case .unsupportedPlatform:
            return "PDF text extraction is not supported on this platform."
        }
    }
}
