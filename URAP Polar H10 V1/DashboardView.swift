//
//  DashboardView.swift
//  URAP Polar H10 V1
//
//  Created by Dhanush Eashwar on 10/7/25.
//


import SwiftUI
import PolarBleSdk

struct DashboardView: View {
    @StateObject private var polarManager = PolarManager()
    @State private var showDeviceList = false

    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header
                    headerSection

                    // Sensors Grid or Empty State
                    if polarManager.connectedSensors.isEmpty {
                        emptyState
                    } else {
                        sensorsScrollView
                    }

                    // Error Message
                    if let error = polarManager.errorMessage {
                        errorBanner(error)
                            .padding()
                    }
                }

                // Floating Action Button
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        addSensorButton
                    }
                }
                .padding()
            }
            .navigationTitle("Polar H-10 Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showDeviceList) {
                DeviceListView(polarManager: polarManager, isPresented: $showDeviceList)
            }
        }
    }
    
    // MARK: - Subviews

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(polarManager.connectedSensors.count) Sensors")
                    .font(.title2)
                    .fontWeight(.bold)

                if !polarManager.isBluetoothOn {
                    Label("Bluetooth Off", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Spacer()
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
    }

    private var sensorsScrollView: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16)
            ], spacing: 16) {
                ForEach(polarManager.connectedSensors) { sensor in
                    NavigationLink(destination: SensorDetailView(sensor: sensor)) {
                        CompactSensorCard(sensor: sensor) {
                            polarManager.disconnect(deviceId: sensor.id)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding()
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "sensor.tag.radiowaves.forward")
                .font(.system(size: 80))
                .foregroundColor(.secondary)
                .symbolRenderingMode(.hierarchical)

            Text("No Sensors Connected")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Tap the + button to connect your Polar H-10 sensors")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.circle.fill")
            Text(message)
                .font(.caption)
            Spacer()
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }

    private var addSensorButton: some View {
        Button(action: {
            showDeviceList = true
        }) {
            Image(systemName: "plus")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(width: 60, height: 60)
                .background(
                    LinearGradient(
                        colors: [Color.blue, Color.blue.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(Circle())
                .shadow(color: Color.blue.opacity(0.4), radius: 8, x: 0, y: 4)
        }
        .disabled(!polarManager.isBluetoothOn)
        .opacity(polarManager.isBluetoothOn ? 1.0 : 0.5)
    }
}

// MARK: - Compact Sensor Card Component
struct CompactSensorCard: View {
    @ObservedObject var sensor: ConnectedSensor
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with device ID and status
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                Text(sensor.displayId)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: {
                    onDelete()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }

            // Heart Rate - Primary metric
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundColor(.red)

                    Text("\(sensor.heartRate)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(sensor.isActive ? .primary : .secondary.opacity(0.3))
                        .animation(.easeInOut(duration: 0.3), value: sensor.heartRate)

                    Text("BPM")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, -2)
                }
            }

            // RR Interval & Battery - Secondary metrics (stacked vertically)
            VStack(alignment: .leading, spacing: 6) {
                // RR Interval
                HStack(spacing: 4) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.caption2)
                        .foregroundColor(.blue)
                        .frame(width: 12)

                    Text("\(sensor.rrInterval) ms")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                }

                // Battery
                HStack(spacing: 4) {
                    Image(systemName: batteryIcon(for: sensor.batteryLevel))
                        .font(.caption2)
                        .foregroundColor(batteryColor(for: sensor.batteryLevel))
                        .frame(width: 12)

                    Text("\(sensor.batteryLevel)%")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                }
            }

            // Tap indicator
            HStack {
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.5))
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: sensor.isActive ? Color.red.opacity(0.15) : Color.clear, radius: 6, x: 0, y: 3)
        .scaleEffect(sensor.isActive ? 1.0 : 0.98)
        .animation(.easeInOut(duration: 0.3), value: sensor.isActive)
    }

    private var statusColor: Color {
        switch sensor.connectionState {
        case .connected: return sensor.isActive ? .green : .yellow
        case .connecting: return .orange
        case .disconnected: return .red
        }
    }

    private func batteryIcon(for level: UInt) -> String {
        if level > 75 { return "battery.100" }
        if level > 50 { return "battery.75" }
        if level > 25 { return "battery.50" }
        if level > 10 { return "battery.25" }
        return "battery.0"
    }

    private func batteryColor(for level: UInt) -> Color {
        level > 20 ? .green : .red
    }
}

// MARK: - Device List View
struct DeviceListView: View {
    @ObservedObject var polarManager: PolarManager
    @Binding var isPresented: Bool

    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    if polarManager.isScanning {
                        HStack {
                            ProgressView()
                                .padding(.trailing, 8)
                            Text("Scanning for sensors...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                    }

                    if availableDevices.isEmpty && !polarManager.isScanning {
                        VStack(spacing: 16) {
                            Spacer()
                            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                                .font(.system(size: 60))
                                .foregroundColor(.secondary)

                            Text("No Devices Found")
                                .font(.headline)

                            Text("Make sure your Polar H-10 is nearby and powered on")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)

                            Button(action: {
                                polarManager.startScanning()
                            }) {
                                Label("Scan Again", systemImage: "arrow.clockwise")
                                    .fontWeight(.semibold)
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                            }
                            .padding(.top)

                            Spacer()
                        }
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(availableDevices, id: \.deviceId) { device in
                                    DeviceRow(device: device, isConnected: isDeviceConnected(device)) {
                                        if isDeviceConnected(device) {
                                            polarManager.disconnect(deviceId: device.deviceId)
                                        } else {
                                            polarManager.connect(to: device)
                                        }
                                    }
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
            .navigationTitle("Add Sensors")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        polarManager.stopScanning()
                        isPresented = false
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        if polarManager.isScanning {
                            polarManager.stopScanning()
                        } else {
                            polarManager.startScanning()
                        }
                    }) {
                        if polarManager.isScanning {
                            Text("Stop")
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .onAppear {
                polarManager.startScanning()
            }
            .onDisappear {
                polarManager.stopScanning()
            }
        }
    }

    private var availableDevices: [PolarDeviceInfo] {
        polarManager.discoveredDevices
    }

    private func isDeviceConnected(_ device: PolarDeviceInfo) -> Bool {
        polarManager.connectedSensors.contains { $0.id == device.deviceId }
    }
}

// MARK: - Device Row Component
struct DeviceRow: View {
    let device: PolarDeviceInfo
    let isConnected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(isConnected ? Color.green.opacity(0.2) : Color.blue.opacity(0.2))
                        .frame(width: 50, height: 50)

                    Image(systemName: isConnected ? "checkmark.circle.fill" : "sensor.tag.radiowaves.forward.fill")
                        .font(.title3)
                        .foregroundColor(isConnected ? .green : .blue)
                }

                // Device Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.name)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(device.deviceId)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Action indicator
                if isConnected {
                    Text("Connected")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.2))
                        .cornerRadius(8)
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(.blue)
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview
struct DashboardView_Previews: PreviewProvider {
    static var previews: some View {
        DashboardView()
    }
}
