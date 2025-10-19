//
//  SensorDetailView.swift
//  URAP Polar H10 V1
//
//  Detailed view for individual sensor with real-time graphs and HRV analysis
//

import SwiftUI
import Charts

struct SensorDetailView: View {
    @ObservedObject var sensor: ConnectedSensor
    @State private var selectedTimeRange: TimeRange = .twoMinutes
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header Card
                headerCard

                // Primary Heart Rate Card
                primaryHeartRateCard

                // Statistics Grid
                statisticsGrid

                // HRV Metrics Card
                hrvMetricsCard

                // Time Range Selector
                timeRangeSelector

                // Heart Rate Chart
                heartRateChart

                // RR Interval Chart
                rrIntervalChart

                // Session Info
                sessionInfoCard
            }
            .padding()
        }
        .background(Color(UIColor.systemGroupedBackground))
        .navigationTitle(sensor.deviceName)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header Card
    private var headerCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Device ID: \(sensor.displayId)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)

                    Text(sensor.connectionState.displayText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if sensor.sessionDuration > 0 {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(formatDuration(sensor.sessionDuration))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    // MARK: - Primary Heart Rate Card
    private var primaryHeartRateCard: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "heart.fill")
                    .font(.title)
                    .foregroundColor(.red)
                    .symbolEffect(.pulse, options: .repeating, value: sensor.isActive)

                Text("\(sensor.heartRate)")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundColor(sensor.isActive ? .primary : .secondary.opacity(0.3))

                Text("BPM")
                    .font(.title2)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 8)
            }

            if !sensor.isActive {
                Text("Waiting for data...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
                .shadow(color: sensor.isActive ? Color.red.opacity(0.2) : Color.clear, radius: 12, x: 0, y: 4)
        )
    }

    // MARK: - Statistics Grid
    private var statisticsGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                StatCard(title: "Min", value: "\(sensor.minHeartRate)", unit: "BPM", color: .blue)
                StatCard(title: "Max", value: "\(sensor.maxHeartRate)", unit: "BPM", color: .red)
                StatCard(title: "Avg", value: "\(sensor.averageHeartRate)", unit: "BPM", color: .green)
            }

            HStack(spacing: 12) {
                StatCard(title: "RR Interval", value: "\(sensor.rrInterval)", unit: "ms", color: .blue)
                    .frame(maxWidth: .infinity)

                BatteryCard(level: sensor.batteryLevel)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - HRV Metrics Card
    private var hrvMetricsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Heart Rate Variability (HRV)")
                .font(.headline)
                .foregroundColor(.primary)

            if sensor.sdnn > 0 {
                VStack(spacing: 12) {
                    HRVMetricRow(
                        name: "SDNN",
                        value: sensor.sdnn,
                        interpretation: interpretSDNN(sensor.sdnn),
                        description: "Standard deviation of RR intervals"
                    )

                    Divider()

                    HRVMetricRow(
                        name: "RMSSD",
                        value: sensor.rmssd,
                        interpretation: interpretRMSSD(sensor.rmssd),
                        description: "Root mean square of successive differences"
                    )
                }
            } else {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                    Text("Collecting data for HRV analysis...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    // MARK: - Time Range Selector
    private var timeRangeSelector: some View {
        HStack(spacing: 12) {
            ForEach(TimeRange.allCases, id: \.self) { range in
                Button(action: {
                    selectedTimeRange = range
                }) {
                    Text(range.displayName)
                        .font(.subheadline)
                        .fontWeight(selectedTimeRange == range ? .semibold : .regular)
                        .foregroundColor(selectedTimeRange == range ? .white : .primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            selectedTimeRange == range ?
                            Color.blue :
                            Color(UIColor.secondarySystemGroupedBackground)
                        )
                        .cornerRadius(8)
                }
            }
        }
    }

    // MARK: - Heart Rate Chart
    private var heartRateChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Heart Rate")
                .font(.headline)
                .padding(.horizontal)

            if filteredHeartRateData.isEmpty {
                EmptyChartView(message: "No heart rate data yet")
            } else {
                Chart(filteredHeartRateData) { dataPoint in
                    LineMark(
                        x: .value("Time", dataPoint.timestamp),
                        y: .value("BPM", dataPoint.value)
                    )
                    .foregroundStyle(.red)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Time", dataPoint.timestamp),
                        y: .value("BPM", dataPoint.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.red.opacity(0.3), .red.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour().minute().second())
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 200)
                .padding()
            }
        }
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    // MARK: - RR Interval Chart
    private var rrIntervalChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RR Interval")
                .font(.headline)
                .padding(.horizontal)

            if filteredRRIntervalData.isEmpty {
                EmptyChartView(message: "No RR interval data yet")
            } else {
                Chart(filteredRRIntervalData) { dataPoint in
                    LineMark(
                        x: .value("Time", dataPoint.timestamp),
                        y: .value("ms", dataPoint.value)
                    )
                    .foregroundStyle(.blue)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Time", dataPoint.timestamp),
                        y: .value("ms", dataPoint.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue.opacity(0.3), .blue.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour().minute().second())
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 200)
                .padding()
            }
        }
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    // MARK: - Session Info Card
    private var sessionInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session Information")
                .font(.headline)

            VStack(spacing: 8) {
                InfoRow(label: "Connected Since", value: formatTimestamp(sensor.sessionStartTime))
                InfoRow(label: "Data Points", value: "\(sensor.heartRateHistory.count) HR / \(sensor.rrIntervalHistory.count) RR")
                InfoRow(label: "Duration", value: formatDuration(sensor.sessionDuration))
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    // MARK: - Computed Properties
    private var statusColor: Color {
        switch sensor.connectionState {
        case .connected: return sensor.isActive ? .green : .yellow
        case .connecting: return .orange
        case .disconnected: return .red
        }
    }

    private var filteredHeartRateData: [HeartRateDataPoint] {
        let cutoffTime = Date().addingTimeInterval(-selectedTimeRange.seconds)
        return sensor.heartRateHistory.filter { $0.timestamp >= cutoffTime }
    }

    private var filteredRRIntervalData: [RRIntervalDataPoint] {
        let cutoffTime = Date().addingTimeInterval(-selectedTimeRange.seconds)
        return sensor.rrIntervalHistory.filter { $0.timestamp >= cutoffTime }
    }

    // MARK: - Helper Functions
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes > 0 {
            return String(format: "%dm %ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }

    private func formatTimestamp(_ date: Date?) -> String {
        guard let date = date else { return "N/A" }
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private func interpretSDNN(_ value: Double) -> (String, Color) {
        if value > 100 { return ("Excellent", .green) }
        if value > 50 { return ("Good", .green) }
        if value > 25 { return ("Fair", .orange) }
        return ("Low", .red)
    }

    private func interpretRMSSD(_ value: Double) -> (String, Color) {
        if value > 50 { return ("Excellent", .green) }
        if value > 30 { return ("Good", .green) }
        if value > 15 { return ("Fair", .orange) }
        return ("Low", .red)
    }
}

// MARK: - Time Range Enum
enum TimeRange: CaseIterable {
    case thirtySeconds
    case oneMinute
    case twoMinutes
    case fiveMinutes

    var displayName: String {
        switch self {
        case .thirtySeconds: return "30s"
        case .oneMinute: return "1m"
        case .twoMinutes: return "2m"
        case .fiveMinutes: return "5m"
        }
    }

    var seconds: TimeInterval {
        switch self {
        case .thirtySeconds: return 30
        case .oneMinute: return 60
        case .twoMinutes: return 120
        case .fiveMinutes: return 300
        }
    }
}

// MARK: - Supporting Views

struct StatCard: View {
    let title: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(color)

            Text(unit)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

struct BatteryCard: View {
    let level: UInt

    var body: some View {
        VStack(spacing: 8) {
            Text("Battery")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 4) {
                Image(systemName: batteryIcon)
                    .font(.title2)
                    .foregroundColor(batteryColor)

                Text("\(level)%")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
            }

            Text(" ")
                .font(.caption2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private var batteryIcon: String {
        if level > 75 { return "battery.100" }
        if level > 50 { return "battery.75" }
        if level > 25 { return "battery.50" }
        if level > 10 { return "battery.25" }
        return "battery.0"
    }

    private var batteryColor: Color {
        level > 20 ? .green : .red
    }
}

struct HRVMetricRow: View {
    let name: String
    let value: Double
    let interpretation: (String, Color)
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                Text(String(format: "%.1f ms", value))
                    .font(.title3)
                    .fontWeight(.bold)

                Text(interpretation.0)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(interpretation.1)
                    .cornerRadius(6)
            }

            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
}

struct EmptyChartView: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
    }
}
