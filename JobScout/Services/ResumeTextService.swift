//
//  ResumeTextService.swift
//  JobScout
//
//  Created by Claude on 1/11/26.
//

import Foundation
import Zoni

/// Service for extracting text from PDF resumes and chunking the text
actor ResumeTextService {
    static let shared = ResumeTextService()

    private let pdfLoader: PDFLoader
    private let sentenceChunker: SentenceChunker

    init() {
        // Initialize PDF loader with default settings
        self.pdfLoader = PDFLoader(preserveLayout: false)

        // Initialize sentence chunker with settings optimized for resume content
        // - targetSize: 500 characters (resumes have shorter, denser sections)
        // - minSize: 50 characters (allow small chunks for headers/short sections)
        // - maxSize: 1000 characters (keep chunks manageable)
        // - overlapSentences: 1 (maintain context between chunks)
        self.sentenceChunker = SentenceChunker(
            targetSize: 500,
            minSize: 50,
            maxSize: 1000,
            overlapSentences: 1
        )
    }

    /// Extract text from PDF data
    /// - Parameter pdfData: The raw PDF file data
    /// - Returns: The extracted text content
    /// - Throws: ResumeTextError if extraction fails
    func extractText(from pdfData: Data) async throws -> String {
        do {
            let document = try await pdfLoader.load(from: pdfData, metadata: nil)
            let text = document.content.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !text.isEmpty else {
                throw ResumeTextError.emptyContent
            }

            return text
        } catch let error as ZoniError {
            throw ResumeTextError.extractionFailed(error.localizedDescription)
        } catch let error as ResumeTextError {
            throw error
        } catch {
            throw ResumeTextError.extractionFailed(error.localizedDescription)
        }
    }

    /// Chunk the extracted text into smaller segments using sentence-based chunking
    /// - Parameter text: The text to chunk
    /// - Returns: An array of text chunks with metadata
    /// - Throws: ResumeTextError if chunking fails
    func chunkText(_ text: String) async throws -> [TextChunk] {
        guard !text.isEmpty else {
            throw ResumeTextError.emptyContent
        }

        do {
            let chunks = try await sentenceChunker.chunk(text, metadata: nil)

            return chunks.enumerated().map { index, chunk in
                TextChunk(
                    index: index,
                    content: chunk.content,
                    characterCount: chunk.characterCount,
                    wordCount: chunk.wordCount
                )
            }
        } catch let error as ZoniError {
            throw ResumeTextError.chunkingFailed(error.localizedDescription)
        } catch {
            throw ResumeTextError.chunkingFailed(error.localizedDescription)
        }
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
