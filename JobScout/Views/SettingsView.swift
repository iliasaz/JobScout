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

    private let keychainService = KeychainService.shared

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
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 350)
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
