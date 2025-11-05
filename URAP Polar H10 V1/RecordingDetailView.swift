//
//  RecordingDetailView.swift
//  URAP Polar H10 V1
//
//  Detailed view of a single recording with charts and metrics
//

import SwiftUI
import Charts
import UniformTypeIdentifiers

struct RecordingDetailView: View {
    let recording: RecordingSession
    @StateObject private var recordingsManager = RecordingsManager.shared
    @State private var showRenameSheet = false
    @State private var exportDocument: ExportDocument?
    @State private var exportFilename: String = ""
    @State private var showExportError = false
    @State private var exportErrorMessage = ""
    @State private var expandedSensors: Set<String> = []
    @State private var showRawDataSheet = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.spacing.lg) {
                // Summary section
                summarySection

                // Per-sensor sections
                ForEach(recording.sensorRecordings) { sensor in
                    sensorSection(for: sensor)
                }

                // Raw data button
                rawDataButton
            }
            .padding()
        }
        .background(AppTheme.adaptiveBackground(for: colorScheme).ignoresSafeArea())
        .navigationTitle(recording.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { showRenameSheet = true }) {
                        Label("Rename", systemImage: "pencil")
                    }

                    Menu {
                        Button(action: { exportCSV() }) {
                            Label("Export as CSV", systemImage: "tablecells")
                        }

                        Button(action: { exportJSON() }) {
                            Label("Export as JSON", systemImage: "doc.text")
                        }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }

                    Divider()

                    Button(role: .destructive, action: {
                        recordingsManager.deleteRecording(withId: recording.id)
                    }) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(AppTheme.accentBlue)
                }
            }
        }
        .sheet(isPresented: $showRenameSheet) {
            RenameRecordingSheet(recording: recording) { newName in
                recordingsManager.renameRecording(withId: recording.id, newName: newName)
            }
        }
        .fileExporter(
            isPresented: Binding(
                get: { exportDocument != nil },
                set: { if !$0 { exportDocument = nil } }
            ),
            document: exportDocument,
            contentType: exportDocument?.contentType ?? UTType.data,
            defaultFilename: exportFilename
        ) { result in
            switch result {
            case .success(let url):
                print("✅ File exported to: \(url)")
            case .failure(let error):
                exportErrorMessage = error.localizedDescription
                showExportError = true
                print("❌ Export failed: \(error)")
            }
        }
        .alert("Export Failed", isPresented: $showExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportErrorMessage)
        }
        .sheet(isPresented: $showRawDataSheet) {
            RawDataViewerSheet(recording: recording)
        }
    }

    // MARK: - Summary Section

    private var summarySection: some View {
        VStack(spacing: AppTheme.spacing.md) {
            Text("Session Summary")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: AppTheme.spacing.md) {
                SummaryCard(
                    icon: "clock.fill",
                    title: "Duration",
                    value: recording.formattedDuration,
                    color: .blue
                )

                SummaryCard(
                    icon: "sensor.tag.radiowaves.forward.fill",
                    title: "Sensors",
                    value: "\(recording.sensorCount)",
                    color: .purple
                )

                SummaryCard(
                    icon: "heart.fill",
                    title: "Avg HR",
                    value: recording.averageHeartRate > 0 ? "\(Int(recording.averageHeartRate)) BPM" : "N/A",
                    color: .red
                )

                SummaryCard(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Data Points",
                    value: "\(recording.totalDataPoints)",
                    color: .green
                )

                if recording.averageSDNN > 0 {
                    SummaryCard(
                        icon: "waveform.path.ecg",
                        title: "Avg SDNN",
                        value: String(format: "%.1f ms", recording.averageSDNN),
                        color: .orange
                    )
                }

                if recording.averageRMSSD > 0 {
                    SummaryCard(
                        icon: "waveform",
                        title: "Avg RMSSD",
                        value: String(format: "%.1f ms", recording.averageRMSSD),
                        color: .cyan
                    )
                }
            }
        }
    }

    // MARK: - Sensor Section

    private func sensorSection(for sensor: SensorRecording) -> some View {
        let isExpanded = expandedSensors.contains(sensor.id)

        return VStack(spacing: AppTheme.spacing.md) {
            // Sensor header (tap to expand/collapse)
            Button(action: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    if isExpanded {
                        expandedSensors.remove(sensor.id)
                    } else {
                        expandedSensors.insert(sensor.id)
                    }
                }
            }) {
                GlassCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(sensor.sensorName)
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)

                            Text("\(sensor.dataPointCount) data points • \(String(format: "%.1f", sensor.duration))s")
                                .font(.caption)
                                .foregroundColor(.primary.opacity(0.6))
                        }

                        Spacer()

                        Image(systemName: "chevron.down.circle.fill")
                            .font(.title3)
                            .foregroundColor(AppTheme.accentBlue)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: isExpanded)
                    }
                    .padding(AppTheme.spacing.md)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .scaleEffect(isExpanded ? 1.01 : 1.0)
            .shadow(color: isExpanded ? AppTheme.accentBlue.opacity(0.2) : .clear, radius: 8, x: 0, y: 4)
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: isExpanded)

            // Expanded content
            if isExpanded {
                VStack(spacing: AppTheme.spacing.md) {
                    // Statistics grid
                    sensorStatistics(for: sensor)

                    // Heart rate chart
                    if !sensor.heartRateData.isEmpty {
                        heartRateChart(for: sensor)
                    }

                    // RR interval chart
                    if !sensor.rrIntervalData.isEmpty {
                        rrIntervalChart(for: sensor)
                    }

                    // HRV metrics
                    if sensor.statistics.sdnn > 0 || sensor.statistics.rmssd > 0 {
                        hrvMetrics(for: sensor)
                    }
                }
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.95, anchor: .top).combined(with: .opacity),
                    removal: .scale(scale: 0.95, anchor: .top).combined(with: .opacity)
                ))
            }
        }
    }

    // MARK: - Sensor Statistics

    private func sensorStatistics(for sensor: SensorRecording) -> some View {
        GlassCard {
            VStack(spacing: AppTheme.spacing.sm) {
                Text("Statistics")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: AppTheme.spacing.sm) {
                    StatItem(label: "Min HR", value: "\(sensor.statistics.minHeartRate)", unit: "BPM")
                    StatItem(label: "Avg HR", value: "\(sensor.statistics.averageHeartRate)", unit: "BPM")
                    StatItem(label: "Max HR", value: "\(sensor.statistics.maxHeartRate)", unit: "BPM")
                }
            }
            .padding(AppTheme.spacing.md)
        }
    }

    // MARK: - Heart Rate Chart

    private func heartRateChart(for sensor: SensorRecording) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppTheme.spacing.md) {
                HStack {
                    Image(systemName: "heart.fill")
                        .foregroundColor(.red)
                    Text("Heart Rate")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }

                Chart {
                    ForEach(Array(sensor.heartRateData.enumerated()), id: \.offset) { index, dataPoint in
                        LineMark(
                            x: .value("Time", dataPoint.timestamp),
                            y: .value("HR", dataPoint.value)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.red, .pink],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { value in
                        if let date = value.as(Date.self) {
                            AxisValueLabel {
                                Text(date, format: .dateTime.minute().second())
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 200)
            }
            .padding(AppTheme.spacing.md)
        }
    }

    // MARK: - RR Interval Chart

    private func rrIntervalChart(for sensor: SensorRecording) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppTheme.spacing.md) {
                HStack {
                    Image(systemName: "waveform.path.ecg")
                        .foregroundColor(.purple)
                    Text("RR Intervals")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }

                Chart {
                    ForEach(Array(sensor.rrIntervalData.enumerated()), id: \.offset) { index, dataPoint in
                        LineMark(
                            x: .value("Time", dataPoint.timestamp),
                            y: .value("RR", dataPoint.value)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { value in
                        if let date = value.as(Date.self) {
                            AxisValueLabel {
                                Text(date, format: .dateTime.minute().second())
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 200)
            }
            .padding(AppTheme.spacing.md)
        }
    }

    // MARK: - HRV Metrics

    private func hrvMetrics(for sensor: SensorRecording) -> some View {
        GlassCard {
            VStack(spacing: AppTheme.spacing.sm) {
                Text("HRV Metrics (\(sensor.statistics.hrvWindow))")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: AppTheme.spacing.lg) {
                    if sensor.statistics.sdnn > 0 {
                        VStack(spacing: 4) {
                            Text("SDNN")
                                .font(.caption)
                                .foregroundColor(.primary.opacity(0.6))
                            Text(sensor.statistics.formattedSDNN)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(AppTheme.accentBlue)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    if sensor.statistics.rmssd > 0 {
                        VStack(spacing: 4) {
                            Text("RMSSD")
                                .font(.caption)
                                .foregroundColor(.primary.opacity(0.6))
                            Text(sensor.statistics.formattedRMSSD)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(AppTheme.accentBlue)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    VStack(spacing: 4) {
                        Text("Samples")
                            .font(.caption)
                            .foregroundColor(.primary.opacity(0.6))
                        Text("\(sensor.statistics.hrvSampleCount)")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(AppTheme.spacing.md)
        }
    }

    // MARK: - Raw Data Button

    private var rawDataButton: some View {
        Button(action: {
            showRawDataSheet = true
        }) {
            GlassCard {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("View Raw Data")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)

                        Text("Explore all \(recording.totalDataPoints) data points")
                            .font(.caption)
                            .foregroundColor(.primary.opacity(0.6))
                    }

                    Spacer()

                    Image(systemName: "tablecells")
                        .font(.title2)
                        .foregroundColor(AppTheme.accentBlue)
                }
                .padding(AppTheme.spacing.lg)
            }
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius.lg)
                    .stroke(AppTheme.primaryGradient.opacity(0.3), lineWidth: 1.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Export Functions

    private func exportCSV() {
        guard let url = recordingsManager.exportCSV(recordingId: recording.id) else {
            exportErrorMessage = "Failed to create CSV export"
            showExportError = true
            return
        }

        do {
            exportDocument = try ExportDocument.zip(from: url)
            exportFilename = "\(recording.name.replacingOccurrences(of: " ", with: "_"))_CSV.zip"
        } catch {
            exportErrorMessage = "Failed to prepare CSV export: \(error.localizedDescription)"
            showExportError = true
        }
    }

    private func exportJSON() {
        guard let url = recordingsManager.exportJSON(recordingId: recording.id) else {
            exportErrorMessage = "Failed to create JSON export"
            showExportError = true
            return
        }

        do {
            exportDocument = try ExportDocument.json(from: url)
            exportFilename = "\(recording.name.replacingOccurrences(of: " ", with: "_")).json"
        } catch {
            exportErrorMessage = "Failed to prepare JSON export: \(error.localizedDescription)"
            showExportError = true
        }
    }
}

// MARK: - Summary Card

struct SummaryCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        GlassCard {
            VStack(spacing: AppTheme.spacing.sm) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)

                Text(title)
                    .font(.caption)
                    .foregroundColor(.primary.opacity(0.6))

                Text(value)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(AppTheme.spacing.md)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Stat Item

struct StatItem: View {
    let label: String
    let value: String
    let unit: String

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.primary.opacity(0.6))
            HStack(spacing: 2) {
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                Text(unit)
                    .font(.caption2)
                    .foregroundColor(.primary.opacity(0.6))
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct RecordingDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            RecordingDetailView(recording: RecordingSession.preview)
        }
        .preferredColorScheme(.dark)
    }
}
#endif
