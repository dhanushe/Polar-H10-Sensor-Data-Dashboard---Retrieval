//
//  SettingsView.swift
//  URAP Polar H10 V1
//
//  Modern settings page with beautiful UI
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @Environment(\.colorScheme) var systemColorScheme

    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                AppTheme.darkGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: AppTheme.spacing.lg) {
                        // Header
                        headerSection

                        // HRV Settings
                        hrvSettingsSection

                        // About Section
                        aboutSection
                    }
                    .padding()
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        GlassCard {
            VStack(spacing: AppTheme.spacing.md) {
                Image(systemName: "waveform.path.ecg.rectangle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(AppTheme.primaryGradient)
                    .symbolRenderingMode(.hierarchical)

                GradientText("Polar H10", gradient: AppTheme.primaryGradient, font: .title2)

                Text("Research-Grade HRV Analysis")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(AppTheme.spacing.lg)
        }
    }

    // MARK: - HRV Settings Section

    private var hrvSettingsSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppTheme.spacing.md) {
                HStack {
                    Image(systemName: "heart.text.square.fill")
                        .font(.title2)
                        .foregroundStyle(AppTheme.primaryGradient)

                    Text("HRV Analysis")
                        .font(.headline)
                        .fontWeight(.bold)

                    Spacer()
                }

                Divider()
                    .background(Color.white.opacity(0.1))

                VStack(alignment: .leading, spacing: AppTheme.spacing.sm) {
                    Text("Default Analysis Window")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Picker("Default Window", selection: $settings.defaultHRVWindowEnum) {
                        ForEach(HRVWindow.allCases) { window in
                            Text(window.displayName).tag(window)
                        }
                    }
                    .pickerStyle(.segmented)
                    .background(AppTheme.glassMaterial)
                    .cornerRadius(AppTheme.cornerRadius.sm)

                    Text(windowDescription(settings.defaultHRVWindowEnum))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, AppTheme.spacing.xs)
                }
            }
            .padding(AppTheme.spacing.lg)
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppTheme.spacing.md) {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .font(.title2)
                        .foregroundStyle(AppTheme.primaryGradient)

                    Text("About")
                        .font(.headline)
                        .fontWeight(.bold)

                    Spacer()
                }

                Divider()
                    .background(Color.white.opacity(0.1))

                StatRow(label: "Version", value: settings.fullVersion, icon: "app.badge")

                Divider()
                    .background(Color.white.opacity(0.1))

                VStack(alignment: .leading, spacing: AppTheme.spacing.sm) {
                    Text("Features")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    FeatureRow(icon: "waveform.path.ecg", title: "Real-time HR & RR Monitoring", description: "High-precision heart rate and RR interval tracking")

                    FeatureRow(icon: "clock.fill", title: "Research-Grade Timing", description: "Microsecond-precision monotonic timestamps")

                    FeatureRow(icon: "chart.line.uptrend.xyaxis", title: "Time-Based HRV Analysis", description: "SDNN and RMSSD calculated over configurable windows")

                    FeatureRow(icon: "record.circle", title: "Manual Recording Control", description: "Start, pause, and stop data collection independently")
                }

                Divider()
                    .background(Color.white.opacity(0.1))

                Text("Built for advanced HRV research and analysis with the Polar H10 heart rate monitor.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .padding(AppTheme.spacing.lg)
        }
    }

    // MARK: - Helper Functions

    private func windowDescription(_ window: HRVWindow) -> String {
        switch window {
        case .ultraShort1min:
            return "Ultra-short term analysis. Best for quick assessments."
        case .ultraShort2min:
            return "Ultra-short term analysis. Good balance of speed and accuracy."
        case .short5min:
            return "Short-term analysis. Research standard for HRV measurement."
        case .extended10min:
            return "Extended analysis. Maximum data for comprehensive assessment."
        }
    }
}

// MARK: - Feature Row Component

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.spacing.md) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(AppTheme.primaryGradient)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .preferredColorScheme(.dark)
    }
}
