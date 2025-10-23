//
//  MainTabView.swift
//  URAP Polar H10 V1
//
//  Beautiful bottom tab navigation with glassmorphism
//

import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Dashboard Tab
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(0)

            // Settings Tab
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(1)
        }
        .accentColor(AppTheme.accentBlue)
        .onAppear {
            setupTabBarAppearance()
        }
    }

    private func setupTabBarAppearance() {
        let appearance = UITabBarAppearance()

        // Glassmorphic background
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = UIColor(AppTheme.cardBackground)

        // Selected item - use accent blue
        appearance.stackedLayoutAppearance.selected.iconColor = UIColor(AppTheme.accentBlue)
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: UIColor(AppTheme.accentBlue),
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold)
        ]

        // Normal item - subtle gray
        appearance.stackedLayoutAppearance.normal.iconColor = UIColor.systemGray
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor.systemGray,
            .font: UIFont.systemFont(ofSize: 11, weight: .regular)
        ]

        UITabBar.appearance().standardAppearance = appearance
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }
}

// MARK: - Preview

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
            .preferredColorScheme(.dark)
    }
}
