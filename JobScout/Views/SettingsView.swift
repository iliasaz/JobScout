//
//  SettingsView.swift
//  JobScout
//
//  Created by Ilia Sazonov on 12/29/25.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Settings view for configuring API keys and app preferences
struct SettingsView: View {
    @State private var openRouterAPIKey: String = ""
    @State private var isLoading = true
    @State private var saveStatus: SaveStatus = .idle
    @State private var enableHarmonization = true
    @State private var maxRowsToIngest: Int = 0
    @State private var maxRowsText: String = ""
    @State private var enableAnalysis = true
    @State private var maxParallelAnalysis: Int = 3

    // Resume upload state
    @State private var currentResume: UserResume?
    @State private var resumeUploadStatus: ResumeUploadStatus = .idle
    @State private var isLoadingResume = true

    private let keychainService = KeychainService.shared
    private let resumeRepository = ResumeRepository.shared

    /// Maximum allowed resume file size (10 MB)
    private let maxResumeFileSize = 10 * 1024 * 1024

    enum ResumeUploadStatus: Equatable {
        case idle
        case uploading
        case success
        case error(String)
    }

    /// Key for storing max rows setting in UserDefaults
    static let maxRowsKey = "maxRowsToIngest"

    enum SaveStatus: Equatable {
        case idle
        case saving
        case saved
        case error(String)
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SecureField("API Key", text: $openRouterAPIKey)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isLoading)

                        Button(action: saveAPIKey) {
                            switch saveStatus {
                            case .saving:
                                ProgressView()
                                    .controlSize(.small)
                            case .saved:
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            default:
                                Text("Save")
                            }
                        }
                        .disabled(openRouterAPIKey.isEmpty || saveStatus == .saving)
                    }

                    Text("Get your API key from [openrouter.ai/keys](https://openrouter.ai/keys)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if case .error(let message) = saveStatus {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            } header: {
                Text("OpenRouter API")
            } footer: {
                Text("OpenRouter provides access to Claude and other AI models for intelligent data harmonization.")
            }

            Section {
                Toggle("Enable AI Harmonization", isOn: $enableHarmonization)
                    .onChange(of: enableHarmonization) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "enableHarmonization")
                    }

                if enableHarmonization {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("When enabled, JobScout will use AI to:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("  - Infer semantic job categories")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("  - Normalize date formats")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("  - Classify company vs aggregator links")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Data Harmonization")
            }

            Section {
                Toggle("Enable Background Analysis", isOn: $enableAnalysis)
                    .onChange(of: enableAnalysis) { _, newValue in
                        JobAnalysisService.shared.updateSettings(
                            enabled: newValue,
                            maxParallel: maxParallelAnalysis
                        )
                    }

                if enableAnalysis {
                    Stepper(
                        "Parallel job limit: \(maxParallelAnalysis)",
                        value: $maxParallelAnalysis,
                        in: 1...10
                    )
                    .onChange(of: maxParallelAnalysis) { _, newValue in
                        JobAnalysisService.shared.updateSettings(
                            enabled: enableAnalysis,
                            maxParallel: newValue
                        )
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("When enabled, JobScout will automatically:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("  - Fetch job descriptions from job pages")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("  - Extract technologies and skills")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("  - Extract salary and compensation info")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("  - Generate job summaries")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Job Description Analysis")
            } footer: {
                Text("Processing happens in the background after jobs are saved.")
            }

            Section {
                HStack {
                    Text("Maximum rows to ingest")
                    Spacer()
                    TextField("0", text: $maxRowsText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: maxRowsText) { _, newValue in
                            // Only allow numeric input
                            let filtered = newValue.filter { $0.isNumber }
                            if filtered != newValue {
                                maxRowsText = filtered
                            }
                            // Save to UserDefaults
                            if let value = Int(filtered) {
                                maxRowsToIngest = value
                                UserDefaults.standard.set(value, forKey: Self.maxRowsKey)
                            } else if filtered.isEmpty {
                                maxRowsToIngest = 0
                                UserDefaults.standard.set(0, forKey: Self.maxRowsKey)
                            }
                        }
                }
            } header: {
                Text("Parsing")
            } footer: {
                Text("Set to 0 for no limit. Useful for testing with large job lists.")
            }

            Section {
                if isLoadingResume {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading...")
                            .foregroundStyle(.secondary)
                    }
                } else if let resume = currentResume {
                    // Display current resume info
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "doc.fill")
                                .foregroundStyle(.red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(resume.fileName)
                                    .fontWeight(.medium)
                                Text(resume.formattedFileSize)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(action: selectResumeFile) {
                                Text("Replace")
                            }
                            .disabled(resumeUploadStatus == .uploading)

                            Button(action: deleteResume) {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                            .disabled(resumeUploadStatus == .uploading)
                        }

                        Text("Uploaded: \(resume.uploadedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    // No resume uploaded yet
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("No resume uploaded")
                                .foregroundStyle(.secondary)
                            Text("Upload a PDF file to use with job applications")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(action: selectResumeFile) {
                            HStack {
                                Image(systemName: "arrow.up.doc")
                                Text("Upload PDF")
                            }
                        }
                        .disabled(resumeUploadStatus == .uploading)
                    }
                }

                if resumeUploadStatus == .uploading {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Uploading...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if case .success = resumeUploadStatus {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Resume uploaded successfully")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                if case .error(let message) = resumeUploadStatus {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            } header: {
                Text("Resume")
            } footer: {
                Text("Your resume is stored locally and can be used when applying to jobs. Maximum file size: 10 MB.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 700)
        .onAppear {
            loadSettings()
            loadResume()
        }
    }

    private func loadSettings() {
        Task {
            do {
                if let key = try await keychainService.getOpenRouterAPIKey() {
                    await MainActor.run {
                        openRouterAPIKey = key
                    }
                }
            } catch {
                // Key not found or error - leave empty
            }

            await MainActor.run {
                enableHarmonization = UserDefaults.standard.bool(forKey: "enableHarmonization")
                // Default to true if not set
                if !UserDefaults.standard.bool(forKey: "enableHarmonizationSet") {
                    enableHarmonization = true
                    UserDefaults.standard.set(true, forKey: "enableHarmonization")
                    UserDefaults.standard.set(true, forKey: "enableHarmonizationSet")
                }

                // Load max rows setting
                maxRowsToIngest = UserDefaults.standard.integer(forKey: Self.maxRowsKey)
                maxRowsText = String(maxRowsToIngest)

                // Load analysis settings
                if UserDefaults.standard.object(forKey: JobAnalysisService.enabledKey) != nil {
                    enableAnalysis = UserDefaults.standard.bool(forKey: JobAnalysisService.enabledKey)
                } else {
                    enableAnalysis = true
                }

                let parallelSetting = UserDefaults.standard.integer(forKey: JobAnalysisService.maxParallelKey)
                maxParallelAnalysis = parallelSetting > 0 ? parallelSetting : 3

                isLoading = false
            }
        }
    }

    private func saveAPIKey() {
        saveStatus = .saving

        Task {
            do {
                try await keychainService.saveOpenRouterAPIKey(openRouterAPIKey)

                await MainActor.run {
                    saveStatus = .saved
                }

                // Reset status after delay
                try? await Task.sleep(for: .seconds(2))

                await MainActor.run {
                    saveStatus = .idle
                }
            } catch {
                await MainActor.run {
                    saveStatus = .error(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Resume Methods

    private func loadResume() {
        Task {
            do {
                let resume = try await resumeRepository.getCurrentResume()
                await MainActor.run {
                    currentResume = resume
                    isLoadingResume = false
                }
            } catch {
                await MainActor.run {
                    isLoadingResume = false
                }
            }
        }
    }

    private func selectResumeFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.pdf]
        panel.message = "Select a PDF resume to upload"
        panel.prompt = "Upload"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                uploadResume(from: url)
            }
        }
    }

    private func uploadResume(from url: URL) {
        resumeUploadStatus = .uploading

        Task {
            do {
                // Read the file data
                let data = try Data(contentsOf: url)

                // Check file size
                guard data.count <= maxResumeFileSize else {
                    await MainActor.run {
                        resumeUploadStatus = .error("File is too large. Maximum size is 10 MB.")
                    }
                    return
                }

                // Validate it's a PDF
                guard data.starts(with: [0x25, 0x50, 0x44, 0x46]) else { // %PDF magic bytes
                    await MainActor.run {
                        resumeUploadStatus = .error("The selected file is not a valid PDF.")
                    }
                    return
                }

                let fileName = url.lastPathComponent

                // Save to database
                let savedResume = try await resumeRepository.saveResume(fileName: fileName, pdfData: data)

                await MainActor.run {
                    currentResume = savedResume
                    resumeUploadStatus = .success
                }

                // Reset success status after delay
                try? await Task.sleep(for: .seconds(2))

                await MainActor.run {
                    resumeUploadStatus = .idle
                }
            } catch {
                await MainActor.run {
                    resumeUploadStatus = .error(error.localizedDescription)
                }
            }
        }
    }

    private func deleteResume() {
        Task {
            do {
                try await resumeRepository.deleteResume()
                await MainActor.run {
                    currentResume = nil
                }
            } catch {
                await MainActor.run {
                    resumeUploadStatus = .error("Failed to delete resume: \(error.localizedDescription)")
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
