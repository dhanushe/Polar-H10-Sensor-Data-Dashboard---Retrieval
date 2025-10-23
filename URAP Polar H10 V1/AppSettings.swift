//
//  AppSettings.swift
//  URAP Polar H10 V1
//
//  User preferences and settings persistence
//

import SwiftUI
import Combine

class AppSettings: ObservableObject {

    // MARK: - Singleton

    static let shared = AppSettings()

    // MARK: - Published Settings

    @Published var defaultHRVWindow: String {
        didSet {
            UserDefaults.standard.set(defaultHRVWindow, forKey: "defaultHRVWindow")
        }
    }

    // MARK: - Computed Properties

    var defaultHRVWindowEnum: HRVWindow {
        get { HRVWindow(rawValue: defaultHRVWindow) ?? .short5min }
        set { defaultHRVWindow = newValue.rawValue }
    }

    // Fixed accent color - iOS Blue
    var accentColor: Color {
        Color(hex: "0A84FF")
    }

    var accentGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: "0A84FF"), Color(hex: "0A84FF").opacity(0.8)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - App Info

    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var fullVersion: String {
        "\(appVersion) (\(buildNumber))"
    }

    // MARK: - Private Init

    private init() {
        // Load saved settings or use defaults
        self.defaultHRVWindow = UserDefaults.standard.string(forKey: "defaultHRVWindow") ?? HRVWindow.short5min.rawValue
    }
}
