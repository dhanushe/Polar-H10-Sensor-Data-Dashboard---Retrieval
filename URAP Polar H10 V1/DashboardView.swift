//
//  DashboardView.swift
//  URAP Polar H10 V1
//
//  Created by Dhanush Eashwar on 10/7/25.
//


import SwiftUI

struct DashboardView: View {
    @StateObject private var polarManager = PolarManager()
    @State private var showDeviceList = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 30) {
                    // Connection Status Header
                    connectionHeader
                    
                    if polarManager.connectionState == .connected {
                        // 3-Metric Dashboard
                        metricsGrid
                    } else {
                        // Empty State
                        emptyState
                    }
                    
                    Spacer()
                    
                    // Error Message
                    if let error = polarManager.errorMessage {
                        errorBanner(error)
                    }
                    
                    // Connect Button
                    connectButton
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
    
    private var connectionHeader: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)
            
            Text(polarManager.connectionState.displayText)
                .font(.headline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            if !polarManager.isBluetoothOn {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
            }
        }
        .padding()
        .background(Color.white.opacity(0.9))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
    
    private var metricsGrid: some View {
        VStack(spacing: 20) {
            // Heart Rate
            MetricCard(
                title: "Heart Rate",
                value: "\(polarManager.heartRate)",
                unit: "BPM",
                icon: "heart.fill",
                color: .red,
                isActive: polarManager.heartRate > 0
            )
            
            // RR Interval
            MetricCard(
                title: "RR Interval",
                value: "\(polarManager.rrInterval)",
                unit: "ms",
                icon: "waveform.path.ecg",
                color: .blue,
                isActive: polarManager.rrInterval > 0
            )
            
            // Battery Level
            MetricCard(
                title: "Battery",
                value: "\(polarManager.batteryLevel)",
                unit: "%",
                icon: batteryIcon,
                color: batteryColor,
                isActive: polarManager.batteryLevel > 0
            )
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 80))
                .foregroundColor(.gray.opacity(0.5))
            
            Text("No Device Connected")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Connect to your Polar H-10 to see real-time metrics")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.top, 60)
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
    
    private var connectButton: some View {
        Button(action: {
            if polarManager.connectionState == .connected {
                polarManager.disconnect()
            } else {
                showDeviceList = true
            }
        }) {
            HStack {
                Image(systemName: polarManager.connectionState == .connected ? "minus.circle.fill" : "plus.circle.fill")
                Text(polarManager.connectionState == .connected ? "Disconnect" : "Connect Device")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(polarManager.connectionState == .connected ? Color.red : Color.blue)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .disabled(polarManager.connectionState == .connecting || !polarManager.isBluetoothOn)
    }
    
    // MARK: - Computed Properties
    
    private var statusColor: Color {
        switch polarManager.connectionState {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnected: return .gray
        }
    }
    
    private var batteryIcon: String {
        if polarManager.batteryLevel > 75 { return "battery.100" }
        if polarManager.batteryLevel > 50 { return "battery.75" }
        if polarManager.batteryLevel > 25 { return "battery.50" }
        if polarManager.batteryLevel > 10 { return "battery.25" }
        return "battery.0"
    }
    
    private var batteryColor: Color {
        polarManager.batteryLevel > 20 ? .green : .red
    }
}

// MARK: - Metric Card Component
struct MetricCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    let isActive: Bool
    
    var body: some View {
        HStack {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(color)
                .frame(width: 60)
            
            Spacer()
            
            // Value
            VStack(alignment: .trailing, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(isActive ? .primary : .gray.opacity(0.3))
                    
                    Text(unit)
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.9))
        .cornerRadius(16)
        .shadow(color: isActive ? color.opacity(0.2) : Color.clear, radius: 8, x: 0, y: 4)
    }
}

// MARK: - Device List View
struct DeviceListView: View {
    @ObservedObject var polarManager: PolarManager
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationView {
            List {
                if polarManager.discoveredDevices.isEmpty {
                    HStack {
                        Spacer()
                        if polarManager.isScanning {
                            ProgressView()
                                .padding()
                        } else {
                            Text("No devices found")
                                .foregroundColor(.secondary)
                                .padding()
                        }
                        Spacer()
                    }
                } else {
                    ForEach(polarManager.discoveredDevices, id: \.deviceId) { device in
                        Button(action: {
                            polarManager.connect(to: device)
                            isPresented = false
                        }) {
                            HStack {
                                Image(systemName: "sensor.tag.radiowaves.forward.fill")
                                    .foregroundColor(.blue)
                                
                                VStack(alignment: .leading) {
                                    Text(device.name)
                                        .font(.headline)
                                    Text(device.deviceId)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
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
                            ProgressView()
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
}

// MARK: - Preview
struct DashboardView_Previews: PreviewProvider {
    static var previews: some View {
        DashboardView()
    }
}