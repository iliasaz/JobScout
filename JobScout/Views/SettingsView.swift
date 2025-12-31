//
//  SettingsView.swift
//  JobScout
//
//  Created by Ilia Sazonov on 12/29/25.
//

import SwiftUI

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

    private let keychainService = KeychainService.shared

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
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 550)
        .onAppear {
            loadSettings()
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
}

#Preview {
    SettingsView()
}
