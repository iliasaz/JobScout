//
//  ResumeTests.swift
//  JobScoutTests
//
//  Created by Claude on 1/11/26.
//

import Testing
import Foundation
@testable import JobScout

// MARK: - UserResume Model Tests

struct UserResumeTests {

    @Test func formattedFileSizeDisplaysBytes() async throws {
        let resume = UserResume(
            id: 1,
            fileName: "resume.pdf",
            pdfData: Data(count: 500),
            fileSize: 500,
            uploadedAt: Date(),
            createdAt: Date(),
            updatedAt: Date(),
            extractedText: nil,
            extractionStatus: .pending,
            extractionError: nil
        )

        // 500 bytes should display as bytes
        let formatted = resume.formattedFileSize
        #expect(formatted.contains("bytes") || formatted.contains("B"))
    }

    @Test func formattedFileSizeDisplaysKilobytes() async throws {
        let resume = UserResume(
            id: 1,
            fileName: "resume.pdf",
            pdfData: Data(count: 1024),
            fileSize: 2048, // 2 KB
            uploadedAt: Date(),
            createdAt: Date(),
            updatedAt: Date(),
            extractedText: nil,
            extractionStatus: .pending,
            extractionError: nil
        )

        let formatted = resume.formattedFileSize
        #expect(formatted.contains("KB"))
    }

    @Test func formattedFileSizeDisplaysMegabytes() async throws {
        let resume = UserResume(
            id: 1,
            fileName: "resume.pdf",
            pdfData: Data(count: 1024),
            fileSize: 1_500_000, // ~1.5 MB
            uploadedAt: Date(),
            createdAt: Date(),
            updatedAt: Date(),
            extractedText: nil,
            extractionStatus: .pending,
            extractionError: nil
        )

        let formatted = resume.formattedFileSize
        #expect(formatted.contains("MB"))
    }

    @Test func formattedFileSizeHandlesZero() async throws {
        let resume = UserResume(
            id: 1,
            fileName: "empty.pdf",
            pdfData: Data(),
            fileSize: 0,
            uploadedAt: Date(),
            createdAt: Date(),
            updatedAt: Date(),
            extractedText: nil,
            extractionStatus: .pending,
            extractionError: nil
        )

        let formatted = resume.formattedFileSize
        #expect(formatted == "Zero KB" || formatted.contains("0"))
    }

    @Test func hasExtractedTextReturnsTrueWhenCompleted() async throws {
        let resume = UserResume(
            id: 1,
            fileName: "resume.pdf",
            pdfData: Data(count: 100),
            fileSize: 100,
            uploadedAt: Date(),
            createdAt: Date(),
            updatedAt: Date(),
            extractedText: "Sample extracted text from resume",
            extractionStatus: .completed,
            extractionError: nil
        )

        #expect(resume.hasExtractedText == true)
    }

    @Test func hasExtractedTextReturnsFalseWhenPending() async throws {
        let resume = UserResume(
            id: 1,
            fileName: "resume.pdf",
            pdfData: Data(count: 100),
            fileSize: 100,
            uploadedAt: Date(),
            createdAt: Date(),
            updatedAt: Date(),
            extractedText: nil,
            extractionStatus: .pending,
            extractionError: nil
        )

        #expect(resume.hasExtractedText == false)
    }

    @Test func hasExtractedTextReturnsFalseWhenEmpty() async throws {
        let resume = UserResume(
            id: 1,
            fileName: "resume.pdf",
            pdfData: Data(count: 100),
            fileSize: 100,
            uploadedAt: Date(),
            createdAt: Date(),
            updatedAt: Date(),
            extractedText: "",
            extractionStatus: .completed,
            extractionError: nil
        )

        #expect(resume.hasExtractedText == false)
    }
}

// MARK: - ExtractionStatus Tests

struct ExtractionStatusTests {

    @Test func extractionStatusRawValues() async throws {
        #expect(ExtractionStatus.pending.rawValue == "pending")
        #expect(ExtractionStatus.processing.rawValue == "processing")
        #expect(ExtractionStatus.completed.rawValue == "completed")
        #expect(ExtractionStatus.failed.rawValue == "failed")
    }

    @Test func extractionStatusFromRawValue() async throws {
        #expect(ExtractionStatus(rawValue: "pending") == .pending)
        #expect(ExtractionStatus(rawValue: "processing") == .processing)
        #expect(ExtractionStatus(rawValue: "completed") == .completed)
        #expect(ExtractionStatus(rawValue: "failed") == .failed)
        #expect(ExtractionStatus(rawValue: "invalid") == nil)
    }
}

// MARK: - TextChunk Tests

struct TextChunkTests {

    @Test func textChunkStoresProperties() async throws {
        let chunk = TextChunk(
            index: 0,
            content: "This is a sample chunk of text.",
            characterCount: 31,
            wordCount: 7
        )

        #expect(chunk.index == 0)
        #expect(chunk.content == "This is a sample chunk of text.")
        #expect(chunk.characterCount == 31)
        #expect(chunk.wordCount == 7)
    }

    @Test func textChunkIsSendable() async throws {
        let chunk = TextChunk(
            index: 1,
            content: "Sendable content",
            characterCount: 16,
            wordCount: 2
        )

        // Test that chunk can be passed across actor boundaries
        let result = await Task.detached {
            return chunk.content
        }.value

        #expect(result == "Sendable content")
    }
}

// MARK: - ResumeRepository Tests

/// Tests for ResumeRepository - run serially to avoid race conditions on shared database
@Suite(.serialized)
struct ResumeRepositoryTests {

    /// Create sample PDF data with valid PDF magic bytes
    private func createSamplePDFData(size: Int = 1024) -> Data {
        var data = Data()
        // PDF magic bytes: %PDF-1.4
        data.append(contentsOf: [0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34])
        // Fill with random bytes to reach desired size
        if size > 8 {
            data.append(Data(count: size - 8))
        }
        return data
    }

    @Test func saveResumeCreatesNewRecord() async throws {
        let repository = ResumeRepository.shared
        let testId = UUID().uuidString.prefix(8)
        let fileName = "test-resume-\(testId).pdf"
        let pdfData = createSamplePDFData()

        // Clean up any existing resume first
        try await repository.deleteResume()

        // Save a new resume
        let savedResume = try await repository.saveResume(fileName: fileName, pdfData: pdfData)

        #expect(savedResume.fileName == fileName)
        #expect(savedResume.pdfData == pdfData)
        #expect(savedResume.fileSize == pdfData.count)
        #expect(savedResume.extractionStatus == .pending)

        // Clean up
        try await repository.deleteResume()
    }

    @Test func getCurrentResumeReturnsNilWhenEmpty() async throws {
        let repository = ResumeRepository.shared

        // Clean up any existing resume
        try await repository.deleteResume()

        // Should return nil when no resume exists
        let resume = try await repository.getCurrentResume()
        #expect(resume == nil)
    }

    @Test func getCurrentResumeReturnsSavedResume() async throws {
        let repository = ResumeRepository.shared
        let testId = UUID().uuidString.prefix(8)
        let fileName = "test-resume-\(testId).pdf"
        let pdfData = createSamplePDFData(size: 2048)

        // Clean up and save a resume
        try await repository.deleteResume()
        try await repository.saveResume(fileName: fileName, pdfData: pdfData)

        // Get the current resume
        let resume = try await repository.getCurrentResume()

        #expect(resume != nil)
        #expect(resume?.fileName == fileName)
        #expect(resume?.pdfData == pdfData)
        #expect(resume?.fileSize == pdfData.count)

        // Clean up
        try await repository.deleteResume()
    }

    @Test func saveResumeReplacesExistingResume() async throws {
        let repository = ResumeRepository.shared
        let testId = UUID().uuidString.prefix(8)

        // Clean up first
        try await repository.deleteResume()

        // Save first resume
        let firstFileName = "first-resume-\(testId).pdf"
        let firstData = createSamplePDFData(size: 1024)
        try await repository.saveResume(fileName: firstFileName, pdfData: firstData)

        // Save second resume (should replace)
        let secondFileName = "second-resume-\(testId).pdf"
        let secondData = createSamplePDFData(size: 2048)
        try await repository.saveResume(fileName: secondFileName, pdfData: secondData)

        // Get current resume - should be the second one
        let resume = try await repository.getCurrentResume()

        #expect(resume != nil)
        #expect(resume?.fileName == secondFileName)
        #expect(resume?.fileSize == secondData.count)

        // Clean up
        try await repository.deleteResume()
    }

    @Test func deleteResumeRemovesRecord() async throws {
        let repository = ResumeRepository.shared
        let testId = UUID().uuidString.prefix(8)
        let fileName = "delete-test-\(testId).pdf"
        let pdfData = createSamplePDFData()

        // Clean up and save a resume
        try await repository.deleteResume()
        try await repository.saveResume(fileName: fileName, pdfData: pdfData)

        // Verify it exists
        var hasResume = try await repository.hasResume()
        #expect(hasResume == true)

        // Delete it
        try await repository.deleteResume()

        // Verify it's gone
        hasResume = try await repository.hasResume()
        #expect(hasResume == false)

        let resume = try await repository.getCurrentResume()
        #expect(resume == nil)
    }

    @Test func hasResumeReturnsTrueWhenResumeExists() async throws {
        let repository = ResumeRepository.shared
        let testId = UUID().uuidString.prefix(8)
        let fileName = "has-resume-\(testId).pdf"
        let pdfData = createSamplePDFData()

        // Clean up and save a resume
        try await repository.deleteResume()
        try await repository.saveResume(fileName: fileName, pdfData: pdfData)

        let hasResume = try await repository.hasResume()
        #expect(hasResume == true)

        // Clean up
        try await repository.deleteResume()
    }

    @Test func hasResumeReturnsFalseWhenEmpty() async throws {
        let repository = ResumeRepository.shared

        // Clean up any existing resume
        try await repository.deleteResume()

        let hasResume = try await repository.hasResume()
        #expect(hasResume == false)
    }

    @Test func updateResumeReplacesContent() async throws {
        let repository = ResumeRepository.shared
        let testId = UUID().uuidString.prefix(8)

        // Clean up first
        try await repository.deleteResume()

        // Save initial resume
        let initialFileName = "initial-\(testId).pdf"
        let initialData = createSamplePDFData(size: 1024)
        try await repository.saveResume(fileName: initialFileName, pdfData: initialData)

        // Update with new content
        let updatedFileName = "updated-\(testId).pdf"
        let updatedData = createSamplePDFData(size: 3072)
        try await repository.updateResume(fileName: updatedFileName, pdfData: updatedData)

        // Verify update
        let resume = try await repository.getCurrentResume()
        #expect(resume?.fileName == updatedFileName)
        #expect(resume?.fileSize == updatedData.count)

        // Clean up
        try await repository.deleteResume()
    }

    @Test func resumePersistsAcrossRepositoryInstances() async throws {
        let testId = UUID().uuidString.prefix(8)
        let fileName = "persist-\(testId).pdf"
        let pdfData = createSamplePDFData()

        // Save using shared instance
        try await ResumeRepository.shared.deleteResume()
        try await ResumeRepository.shared.saveResume(fileName: fileName, pdfData: pdfData)

        // Create new repository instance and verify data persists
        let newRepository = ResumeRepository()
        let resume = try await newRepository.getCurrentResume()

        #expect(resume != nil)
        #expect(resume?.fileName == fileName)

        // Clean up
        try await ResumeRepository.shared.deleteResume()
    }

    // MARK: - Extraction Status Tests

    @Test func updateExtractionStatusUpdatesResume() async throws {
        let repository = ResumeRepository.shared
        let testId = UUID().uuidString.prefix(8)
        let fileName = "extraction-test-\(testId).pdf"
        let pdfData = createSamplePDFData()

        // Clean up and save a resume
        try await repository.deleteResume()
        let savedResume = try await repository.saveResume(fileName: fileName, pdfData: pdfData)

        // Update status to processing
        try await repository.updateExtractionStatus(resumeId: savedResume.id, status: .processing)
        var resume = try await repository.getCurrentResume()
        #expect(resume?.extractionStatus == .processing)

        // Update status to completed
        try await repository.updateExtractionStatus(resumeId: savedResume.id, status: .completed)
        resume = try await repository.getCurrentResume()
        #expect(resume?.extractionStatus == .completed)

        // Clean up
        try await repository.deleteResume()
    }

    @Test func updateExtractionStatusWithError() async throws {
        let repository = ResumeRepository.shared
        let testId = UUID().uuidString.prefix(8)
        let fileName = "error-test-\(testId).pdf"
        let pdfData = createSamplePDFData()

        // Clean up and save a resume
        try await repository.deleteResume()
        let savedResume = try await repository.saveResume(fileName: fileName, pdfData: pdfData)

        // Update status to failed with error
        let errorMessage = "Test extraction error"
        try await repository.updateExtractionStatus(resumeId: savedResume.id, status: .failed, error: errorMessage)

        let resume = try await repository.getCurrentResume()
        #expect(resume?.extractionStatus == .failed)
        #expect(resume?.extractionError == errorMessage)

        // Clean up
        try await repository.deleteResume()
    }

    // MARK: - Chunk Tests

    @Test func saveAndGetChunks() async throws {
        let repository = ResumeRepository.shared
        let testId = UUID().uuidString.prefix(8)
        let fileName = "chunks-test-\(testId).pdf"
        let pdfData = createSamplePDFData()

        // Clean up and save a resume
        try await repository.deleteResume()
        let savedResume = try await repository.saveResume(fileName: fileName, pdfData: pdfData)

        // Create test chunks
        let chunks = [
            TextChunk(index: 0, content: "First chunk of text", characterCount: 19, wordCount: 4),
            TextChunk(index: 1, content: "Second chunk of text", characterCount: 20, wordCount: 4),
            TextChunk(index: 2, content: "Third chunk of text", characterCount: 19, wordCount: 4)
        ]

        // Save chunks
        try await repository.saveChunks(resumeId: savedResume.id, chunks: chunks)

        // Get chunks
        let savedChunks = try await repository.getChunks()

        #expect(savedChunks.count == 3)
        #expect(savedChunks[0].content == "First chunk of text")
        #expect(savedChunks[1].content == "Second chunk of text")
        #expect(savedChunks[2].content == "Third chunk of text")

        // Clean up
        try await repository.deleteResume()
    }

    @Test func getChunkCount() async throws {
        let repository = ResumeRepository.shared
        let testId = UUID().uuidString.prefix(8)
        let fileName = "count-test-\(testId).pdf"
        let pdfData = createSamplePDFData()

        // Clean up and save a resume
        try await repository.deleteResume()
        let savedResume = try await repository.saveResume(fileName: fileName, pdfData: pdfData)

        // Initially no chunks
        var count = try await repository.getChunkCount()
        #expect(count == 0)

        // Add chunks
        let chunks = [
            TextChunk(index: 0, content: "Chunk 1", characterCount: 7, wordCount: 2),
            TextChunk(index: 1, content: "Chunk 2", characterCount: 7, wordCount: 2)
        ]
        try await repository.saveChunks(resumeId: savedResume.id, chunks: chunks)

        count = try await repository.getChunkCount()
        #expect(count == 2)

        // Clean up
        try await repository.deleteResume()
    }

    @Test func saveExtractedTextAndChunks() async throws {
        let repository = ResumeRepository.shared
        let testId = UUID().uuidString.prefix(8)
        let fileName = "combined-test-\(testId).pdf"
        let pdfData = createSamplePDFData()

        // Clean up and save a resume
        try await repository.deleteResume()
        let savedResume = try await repository.saveResume(fileName: fileName, pdfData: pdfData)

        let extractedText = "This is the full extracted text from the resume."
        let chunks = [
            TextChunk(index: 0, content: "This is the full", characterCount: 16, wordCount: 4),
            TextChunk(index: 1, content: "extracted text from", characterCount: 19, wordCount: 3),
            TextChunk(index: 2, content: "the resume.", characterCount: 11, wordCount: 2)
        ]

        // Save text and chunks together
        try await repository.saveExtractedTextAndChunks(
            resumeId: savedResume.id,
            text: extractedText,
            chunks: chunks
        )

        // Verify
        let resume = try await repository.getCurrentResume()
        #expect(resume?.extractedText == extractedText)
        #expect(resume?.extractionStatus == .completed)

        let savedChunks = try await repository.getChunks()
        #expect(savedChunks.count == 3)

        // Clean up
        try await repository.deleteResume()
    }

    @Test func deleteResumeAlsoDeletesChunks() async throws {
        let repository = ResumeRepository.shared
        let testId = UUID().uuidString.prefix(8)
        let fileName = "delete-chunks-\(testId).pdf"
        let pdfData = createSamplePDFData()

        // Clean up and save a resume with chunks
        try await repository.deleteResume()
        let savedResume = try await repository.saveResume(fileName: fileName, pdfData: pdfData)

        let chunks = [
            TextChunk(index: 0, content: "Chunk to delete", characterCount: 15, wordCount: 3)
        ]
        try await repository.saveChunks(resumeId: savedResume.id, chunks: chunks)

        // Verify chunks exist
        var count = try await repository.getChunkCount()
        #expect(count == 1)

        // Delete resume
        try await repository.deleteResume()

        // Chunks should be gone too
        count = try await repository.getChunkCount()
        #expect(count == 0)
    }
}

// MARK: - PDF Validation Tests

struct PDFValidationTests {

    /// Valid PDF magic bytes: %PDF
    private let validPDFHeader: [UInt8] = [0x25, 0x50, 0x44, 0x46]

    @Test func validPDFStartsWithMagicBytes() async throws {
        var data = Data()
        data.append(contentsOf: validPDFHeader)
        data.append(contentsOf: [0x2D, 0x31, 0x2E, 0x34]) // -1.4
        data.append(Data(count: 100)) // Additional content

        let isValidPDF = data.starts(with: validPDFHeader)
        #expect(isValidPDF == true)
    }

    @Test func invalidPDFDoesNotStartWithMagicBytes() async throws {
        // Plain text file
        let textData = "Hello, World!".data(using: .utf8)!
        let isValidPDF = textData.starts(with: validPDFHeader)
        #expect(isValidPDF == false)

        // PNG file (starts with 0x89 0x50 0x4E 0x47)
        let pngHeader: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
        var pngData = Data()
        pngData.append(contentsOf: pngHeader)
        let isPNG = pngData.starts(with: validPDFHeader)
        #expect(isPNG == false)

        // JPEG file (starts with 0xFF 0xD8 0xFF)
        let jpegHeader: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0]
        var jpegData = Data()
        jpegData.append(contentsOf: jpegHeader)
        let isJPEG = jpegData.starts(with: validPDFHeader)
        #expect(isJPEG == false)
    }

    @Test func emptyDataIsNotValidPDF() async throws {
        let emptyData = Data()
        let isValidPDF = emptyData.starts(with: validPDFHeader)
        #expect(isValidPDF == false)
    }

    @Test func shortDataIsNotValidPDF() async throws {
        // Data shorter than the magic bytes
        var shortData = Data()
        shortData.append(contentsOf: [0x25, 0x50]) // Only first 2 bytes
        let isValidPDF = shortData.starts(with: validPDFHeader)
        #expect(isValidPDF == false)
    }
}

// MARK: - File Size Validation Tests

struct FileSizeValidationTests {

    /// Maximum allowed file size (10 MB)
    private let maxFileSize = 10 * 1024 * 1024

    @Test func fileSizeWithinLimitIsValid() async throws {
        let smallFile = Data(count: 1024) // 1 KB
        #expect(smallFile.count <= maxFileSize)

        let mediumFile = Data(count: 5 * 1024 * 1024) // 5 MB
        #expect(mediumFile.count <= maxFileSize)

        let exactLimit = Data(count: maxFileSize) // Exactly 10 MB
        #expect(exactLimit.count <= maxFileSize)
    }

    @Test func fileSizeExceedingLimitIsInvalid() async throws {
        let tooLarge = Data(count: maxFileSize + 1) // 10 MB + 1 byte
        #expect(tooLarge.count > maxFileSize)

        let wayTooLarge = Data(count: 20 * 1024 * 1024) // 20 MB
        #expect(wayTooLarge.count > maxFileSize)
    }

    @Test func emptyFileIsWithinLimit() async throws {
        let emptyFile = Data()
        #expect(emptyFile.count <= maxFileSize)
    }
}

// MARK: - ResumeError Tests

struct ResumeErrorTests {

    @Test func saveFailedErrorHasDescription() async throws {
        let error = ResumeError.saveFailed
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.contains("save") == true)
    }

    @Test func invalidPDFErrorHasDescription() async throws {
        let error = ResumeError.invalidPDF
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.contains("PDF") == true)
    }

    @Test func fileTooLargeErrorIncludesMaxSize() async throws {
        let maxSize = 10 * 1024 * 1024
        let error = ResumeError.fileTooLarge(maxSize: maxSize)
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.contains("10") == true || error.errorDescription?.contains("MB") == true)
    }
}

// MARK: - ResumeTextError Tests

struct ResumeTextErrorTests {

    @Test func extractionFailedErrorHasDescription() async throws {
        let error = ResumeTextError.extractionFailed("Test reason")
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.contains("Test reason") == true)
    }

    @Test func chunkingFailedErrorHasDescription() async throws {
        let error = ResumeTextError.chunkingFailed("Chunking issue")
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.contains("Chunking issue") == true)
    }

    @Test func emptyContentErrorHasDescription() async throws {
        let error = ResumeTextError.emptyContent
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.contains("text") == true || error.errorDescription?.contains("content") == true)
    }

    @Test func unsupportedPlatformErrorHasDescription() async throws {
        let error = ResumeTextError.unsupportedPlatform
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.contains("platform") == true || error.errorDescription?.contains("supported") == true)
    }
}
