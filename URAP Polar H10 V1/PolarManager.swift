//
//  PolarManager.swift
//  URAP Polar H10 V1
//
//  Created by Dhanush Eashwar on 10/7/25.
//


//
//  PolarManager.swift
//  URAP Polar H10 V1
//
//  Fixed version compatible with PolarBleSdk 5.3.0
//

import Foundation
import Combine
import PolarBleSdk
import RxSwift
import CoreBluetooth

// MARK: - Data Point Models
struct HeartRateDataPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let monotonicTimestamp: TimeInterval  // High-precision monotonic time from CACurrentMediaTime()
    let value: UInt8
}

struct RRIntervalDataPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let monotonicTimestamp: TimeInterval  // High-precision monotonic time from CACurrentMediaTime()
    let value: UInt16
}

// MARK: - HRV Window Configuration
enum HRVWindow: String, CaseIterable, Identifiable {
    case ultraShort1min = "1 Minute"
    case ultraShort2min = "2 Minutes"
    case short5min = "5 Minutes"
    case extended10min = "10 Minutes"

    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .ultraShort1min: return 60
        case .ultraShort2min: return 120
        case .short5min: return 300
        case .extended10min: return 600
        }
    }

    var displayName: String { rawValue }

    var description: String {
        switch self {
        case .ultraShort1min: return "Ultra-short term (1 min)"
        case .ultraShort2min: return "Ultra-short term (2 min)"
        case .short5min: return "Short-term (5 min) - Research standard"
        case .extended10min: return "Extended (10 min)"
        }
    }
}

// MARK: - Recording State
enum RecordingState {
    case idle       // Not recording, sensor may be connected but data not being saved
    case recording  // Actively recording data
    case paused     // Recording paused, can resume

    var displayText: String {
        switch self {
        case .idle: return "Ready to Record"
        case .recording: return "Recording"
        case .paused: return "Paused"
        }
    }

    var icon: String {
        switch self {
        case .idle: return "circle"
        case .recording: return "record.circle.fill"
        case .paused: return "pause.circle.fill"
        }
    }
}

// MARK: - Connected Sensor Model
class ConnectedSensor: ObservableObject, Identifiable {
    let id: String // device ID
    let deviceName: String

    @Published var connectionState: ConnectionState = .connecting
    @Published var recordingState: RecordingState = .idle
    @Published var heartRate: UInt8 = 0
    @Published var rrInterval: UInt16 = 0
    @Published var batteryLevel: UInt = 0
    @Published var lastUpdate: Date = Date()

    // Historical data for graphing
    @Published var heartRateHistory: [HeartRateDataPoint] = []
    @Published var rrIntervalHistory: [RRIntervalDataPoint] = []

    // Session statistics
    @Published var sessionStartTime: Date?
    @Published var minHeartRate: UInt8 = 0
    @Published var maxHeartRate: UInt8 = 0
    @Published var totalHeartRateSamples: Int = 0
    private var heartRateSum: UInt64 = 0

    // High-precision timing for research-grade accuracy
    private var timingSession: TimingSession?
    var sessionStartMonotonicTime: TimeInterval?  // Monotonic timestamp of session start

    // HRV metrics
    @Published var sdnn: Double = 0  // Standard deviation of NN intervals
    @Published var rmssd: Double = 0 // Root mean square of successive differences
    @Published var hrvWindow: HRVWindow = .short5min  // Time window for HRV calculation
    @Published var hrvSampleCount: Int = 0  // Actual number of RR intervals used in last HRV calculation

    var hrDisposable: Disposable?
    var ppiDisposable: Disposable?

    // Maximum data points to keep (5 minutes at ~1Hz)
    private let maxDataPoints = 300

    init(deviceId: String, deviceName: String) {
        self.id = deviceId
        self.deviceName = deviceName
    }

    var displayId: String {
        // Show last 6 characters of device ID for brevity
        String(id.suffix(6))
    }

    var isActive: Bool {
        connectionState == .connected && heartRate > 0
    }

    var averageHeartRate: UInt8 {
        guard totalHeartRateSamples > 0 else { return 0 }
        return UInt8(heartRateSum / UInt64(totalHeartRateSamples))
    }

    var sessionDuration: TimeInterval {
        // Use monotonic time for accurate duration measurement
        if let session = timingSession {
            return session.elapsedTime()
        }
        // Fallback to wall-clock time if session not initialized
        guard let start = sessionStartTime else { return 0 }
        return Date().timeIntervalSince(start)
    }

    // MARK: - Recording Controls

    func startRecording() {
        recordingState = .recording

        // Initialize or resume timing session
        if timingSession == nil {
            timingSession = TimingSession(sessionId: id)
            sessionStartTime = timingSession?.startWallTime
            sessionStartMonotonicTime = timingSession?.startMonotonicTime
        }
    }

    func pauseRecording() {
        recordingState = .paused
    }

    func stopRecording() {
        recordingState = .idle
        // Note: We keep the data and timing session intact so user can review
        // Call resetMetrics() if you want to clear everything
    }

    // MARK: - Data Collection

    func addHeartRateDataPoint(_ hr: UInt8) {
        // Always update current heart rate for live display
        heartRate = hr
        lastUpdate = Date()

        // Only save data points when actively recording
        guard recordingState == .recording else { return }

        // Initialize timing session on first recorded data point
        if timingSession == nil {
            timingSession = TimingSession(sessionId: id)
            sessionStartTime = timingSession?.startWallTime
            sessionStartMonotonicTime = timingSession?.startMonotonicTime
        }

        // Capture high-precision timestamp
        let monotonicTime = timingSession?.now() ?? PrecisionTimer.shared.now()
        let wallTime = timingSession?.monotonicToDate(monotonicTime) ?? Date()

        let dataPoint = HeartRateDataPoint(
            timestamp: wallTime,
            monotonicTimestamp: monotonicTime,
            value: hr
        )
        heartRateHistory.append(dataPoint)

        // Remove old data points beyond max
        if heartRateHistory.count > maxDataPoints {
            heartRateHistory.removeFirst(heartRateHistory.count - maxDataPoints)
        }

        // Update statistics
        if minHeartRate == 0 || hr < minHeartRate {
            minHeartRate = hr
        }
        if hr > maxHeartRate {
            maxHeartRate = hr
        }

        heartRateSum += UInt64(hr)
        totalHeartRateSamples += 1
    }

    func addRRIntervalDataPoint(_ rr: UInt16) {
        // Always update current RR interval for live display
        rrInterval = rr

        // Only save data points when actively recording
        guard recordingState == .recording else { return }

        // Initialize timing session on first recorded data point (if not already done by HR)
        if timingSession == nil {
            timingSession = TimingSession(sessionId: id)
            sessionStartTime = timingSession?.startWallTime
            sessionStartMonotonicTime = timingSession?.startMonotonicTime
        }

        // Capture high-precision timestamp
        let monotonicTime = timingSession?.now() ?? PrecisionTimer.shared.now()
        let wallTime = timingSession?.monotonicToDate(monotonicTime) ?? Date()

        let dataPoint = RRIntervalDataPoint(
            timestamp: wallTime,
            monotonicTimestamp: monotonicTime,
            value: rr
        )
        rrIntervalHistory.append(dataPoint)

        // Remove old data points beyond max
        if rrIntervalHistory.count > maxDataPoints {
            rrIntervalHistory.removeFirst(rrIntervalHistory.count - maxDataPoints)
        }

        // Calculate HRV metrics
        calculateHRVMetrics()
    }

    func calculateHRVMetrics() {
        // Need at least 5 RR intervals for meaningful HRV
        guard rrIntervalHistory.count >= 5 else {
            sdnn = 0
            rmssd = 0
            hrvSampleCount = 0
            return
        }

        // Get current time and calculate cutoff based on selected window
        let currentTime = timingSession?.now() ?? PrecisionTimer.shared.now()
        let windowSeconds = hrvWindow.seconds
        let cutoffTime = currentTime - windowSeconds

        // Filter RR intervals within the time window using monotonic timestamps
        let windowedRR = rrIntervalHistory.filter { $0.monotonicTimestamp >= cutoffTime }

        // Need sufficient data in the window
        guard windowedRR.count >= 5 else {
            sdnn = 0
            rmssd = 0
            hrvSampleCount = 0
            return
        }

        // Extract RR interval values
        let values = windowedRR.map { Double($0.value) }
        hrvSampleCount = values.count

        // Calculate SDNN (Standard Deviation of NN intervals)
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count)
        sdnn = sqrt(variance)

        // Calculate RMSSD (Root Mean Square of Successive Differences)
        var successiveDifferences: [Double] = []
        for i in 1..<values.count {
            let diff = values[i] - values[i-1]
            successiveDifferences.append(pow(diff, 2))
        }
        if !successiveDifferences.isEmpty {
            let meanSquare = successiveDifferences.reduce(0, +) / Double(successiveDifferences.count)
            rmssd = sqrt(meanSquare)
        }
    }

    func resetMetrics() {
        heartRate = 0
        rrInterval = 0
        batteryLevel = 0
        heartRateHistory.removeAll()
        rrIntervalHistory.removeAll()
        sessionStartTime = nil
        minHeartRate = 0
        maxHeartRate = 0
        totalHeartRateSamples = 0
        heartRateSum = 0
        sdnn = 0
        rmssd = 0
        hrvSampleCount = 0

        // Reset high-precision timing session
        timingSession = nil
        sessionStartMonotonicTime = nil
    }

    enum ConnectionState {
        case connecting
        case connected
        case disconnected

        var displayText: String {
            switch self {
            case .connecting: return "Connecting..."
            case .connected: return "Connected"
            case .disconnected: return "Disconnected"
            }
        }
    }
}

/// Manages multiple Polar H-10 device connections and real-time data streaming
class PolarManager: NSObject, ObservableObject {

    // MARK: - Published Properties (Real-time Updates)
    @Published var isBluetoothOn = false
    @Published var isScanning = false
    @Published var discoveredDevices: [PolarDeviceInfo] = []
    @Published var connectedSensors: [ConnectedSensor] = []

    // MARK: - Global Recording State
    @Published var globalRecordingState: RecordingState = .idle

    // MARK: - Error Handling
    @Published var errorMessage: String?

    // MARK: - Private Properties
    private var api: PolarBleApi!
    private let disposeBag = DisposeBag()
    private var sensors: [String: ConnectedSensor] = [:] // deviceId -> sensor
    
    // MARK: - Initialization
    override init() {
        super.init()
        
        // Initialize Polar SDK with required features
        api = PolarBleApiDefaultImpl.polarImplementation(
            DispatchQueue.main,
            features: [
                .feature_hr,                    // Heart rate
                .feature_battery_info,          // Battery status
                .feature_polar_online_streaming // Real-time streaming (for PPI/RR)
            ]
        )
        
        api.polarFilter(true)  // Filter to show only Polar devices
        api.observer = self
        api.deviceInfoObserver = self
        api.deviceFeaturesObserver = self
        api.powerStateObserver = self

        isBluetoothOn = api.isBlePowered

        // Set initial error message if Bluetooth is off
        if !isBluetoothOn {
            errorMessage = "Bluetooth is turned off"
        }
    }
    
    // MARK: - Device Search
    func startScanning() {
        discoveredDevices.removeAll()
        isScanning = true
        errorMessage = nil
        
        Task {
            do {
                // Search for devices with "Polar" or "H10" prefix
                for try await device in api.searchForDevice().values {
                    await MainActor.run {
                        if !discoveredDevices.contains(where: { $0.deviceId == device.deviceId }) {
                            discoveredDevices.append(device)
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Search failed: \(error.localizedDescription)"
                    isScanning = false
                }
            }
        }
    }
    
    func stopScanning() {
        isScanning = false
    }
    
    // MARK: - Connection Management
    func connect(to device: PolarDeviceInfo) {
        stopScanning()
        errorMessage = nil

        // Create new sensor instance
        let sensor = ConnectedSensor(deviceId: device.deviceId, deviceName: device.name)
        sensors[device.deviceId] = sensor
        updateConnectedSensorsList()

        do {
            try api.connectToDevice(device.deviceId)
        } catch {
            errorMessage = "Connection failed: \(error.localizedDescription)"
            sensors.removeValue(forKey: device.deviceId)
            updateConnectedSensorsList()
        }
    }

    func disconnect(deviceId: String) {
        guard let sensor = sensors[deviceId] else { return }

        // Stop streaming
        sensor.hrDisposable?.dispose()
        sensor.ppiDisposable?.dispose()

        do {
            try api.disconnectFromDevice(deviceId)
        } catch {
            errorMessage = "Disconnect failed: \(error.localizedDescription)"
        }

        sensors.removeValue(forKey: deviceId)
        updateConnectedSensorsList()
    }

    private func updateConnectedSensorsList() {
        connectedSensors = Array(sensors.values).sorted { $0.id < $1.id }
    }

    // MARK: - Global Recording Controls

    func startAllRecordings() {
        globalRecordingState = .recording
        for sensor in sensors.values {
            sensor.startRecording()
        }
    }

    func pauseAllRecordings() {
        globalRecordingState = .paused
        for sensor in sensors.values {
            sensor.pauseRecording()
        }
    }

    func stopAllRecordings() {
        globalRecordingState = .idle
        for sensor in sensors.values {
            sensor.stopRecording()
        }
    }

    var recordingStats: (recording: Int, paused: Int, idle: Int) {
        var stats = (recording: 0, paused: 0, idle: 0)
        for sensor in sensors.values {
            switch sensor.recordingState {
            case .recording: stats.recording += 1
            case .paused: stats.paused += 1
            case .idle: stats.idle += 1
            }
        }
        return stats
    }

    var anyRecording: Bool {
        sensors.values.contains { $0.recordingState == .recording }
    }

    var globalSessionDuration: TimeInterval {
        // Return longest session duration among all sensors
        sensors.values.map { $0.sessionDuration }.max() ?? 0
    }

    // MARK: - Data Streaming
    private func startHeartRateStream(for deviceId: String) {
        guard let sensor = sensors[deviceId] else { return }

        sensor.hrDisposable = api.startHrStreaming(deviceId)
            .observe(on: MainScheduler.instance)
            .subscribe { [weak self, weak sensor] event in
                switch event {
                case .next(let data):
                    guard let hrData = data.first, let sensor = sensor else { return }
                    DispatchQueue.main.async {
                        sensor.heartRate = hrData.hr
                        sensor.lastUpdate = Date()
                        sensor.addHeartRateDataPoint(hrData.hr)

                        // RR intervals come with HR data - extract them here
                        if let rrMs = hrData.rrsMs.first {
                            let rrValue = UInt16(rrMs)
                            sensor.rrInterval = rrValue
                            sensor.addRRIntervalDataPoint(rrValue)
                        }
                    }

                case .error(let error):
                    print("HR stream error for \(deviceId): \(error.localizedDescription)")

                case .completed:
                    print("HR stream completed for \(deviceId)")
                }
            }
    }

    private func startRRIntervalStream(for deviceId: String) {
        guard let sensor = sensors[deviceId] else { return }

        sensor.ppiDisposable = api.startPpiStreaming(deviceId)
            .observe(on: MainScheduler.instance)
            .subscribe { [weak sensor] event in
                switch event {
                case .next(let data):
                    guard let sensor = sensor else { return }
                    if let sample = data.samples.first {
                        DispatchQueue.main.async {
                            sensor.rrInterval = sample.ppInMs
                            sensor.addRRIntervalDataPoint(sample.ppInMs)
                        }
                    }

                case .error(let error):
                    print("PPI stream not available for \(deviceId): \(error.localizedDescription)")

                case .completed:
                    print("PPI stream completed for \(deviceId)")
                }
            }
    }
}

// MARK: - PolarBleApiObserver (Connection Events)
extension PolarManager: PolarBleApiObserver {
    func deviceConnecting(_ polarDeviceInfo: PolarDeviceInfo) {
        DispatchQueue.main.async {
            if let sensor = self.sensors[polarDeviceInfo.deviceId] {
                sensor.connectionState = .connecting
            }
        }
    }

    func deviceConnected(_ polarDeviceInfo: PolarDeviceInfo) {
        DispatchQueue.main.async {
            if let sensor = self.sensors[polarDeviceInfo.deviceId] {
                sensor.connectionState = .connected
            }
            self.errorMessage = nil
            self.updateConnectedSensorsList()
        }
    }

    func deviceDisconnected(_ polarDeviceInfo: PolarDeviceInfo, pairingError: Bool) {
        DispatchQueue.main.async {
            if let sensor = self.sensors[polarDeviceInfo.deviceId] {
                sensor.connectionState = .disconnected
                sensor.resetMetrics()
            }

            if pairingError {
                self.errorMessage = "Pairing error with \(polarDeviceInfo.name)"
            }
        }
    }
}

// MARK: - PolarBleApiDeviceInfoObserver (Battery Updates)
extension PolarManager: PolarBleApiDeviceInfoObserver {
    func batteryChargingStatusReceived(_ identifier: String, chargingStatus: PolarBleSdk.BleBasClient.ChargeState) {

    }

    func disInformationReceivedWithKeysAsStrings(_ identifier: String, key: String, value: String) {

    }

    func batteryLevelReceived(_ identifier: String, batteryLevel: UInt) {
        DispatchQueue.main.async {
            if let sensor = self.sensors[identifier] {
                sensor.batteryLevel = batteryLevel
            }
        }
    }

    func disInformationReceived(_ identifier: String, uuid: CBUUID, value: String) {
        // Device information received - not used but required by protocol
    }

    func hrFeatureReady(_ identifier: String) {
        // HR feature ready - not used but required by protocol
    }
}

// MARK: - PolarBleApiDeviceFeaturesObserver (Feature Ready)
extension PolarManager: PolarBleApiDeviceFeaturesObserver {
    func bleSdkFeatureReady(_ identifier: String, feature: PolarBleSdk.PolarBleSdkFeature) {
        print("Feature ready: \(feature) for device: \(identifier)")

        DispatchQueue.main.async {
            switch feature {
            case .feature_hr:
                // Start streaming HR and RR interval data for this device
                self.startHeartRateStream(for: identifier)
                self.startRRIntervalStream(for: identifier)

            case .feature_battery_info:
                print("Battery info feature ready for \(identifier)")

            default:
                break
            }
        }
    }

    func ftpFeatureReady(_ identifier: String) {
        // FTP (File Transfer Protocol) feature ready - not used for basic metrics
        print("FTP feature ready for device: \(identifier)")
    }

    func streamingFeaturesReady(_ identifier: String, streamingFeatures: Set<PolarBleSdk.PolarDeviceDataType>) {
        // Called when streaming features are available (ECG, ACC, etc.)
        print("Streaming features ready for \(identifier): \(streamingFeatures)")
    }
}

// MARK: - PolarBleApiPowerStateObserver (Bluetooth State)
extension PolarManager: PolarBleApiPowerStateObserver {
    func blePowerOn() {
        DispatchQueue.main.async {
            self.isBluetoothOn = true
            // Clear Bluetooth error message when Bluetooth turns on
            if self.errorMessage == "Bluetooth is turned off" {
                self.errorMessage = nil
            }
        }
    }

    func blePowerOff() {
        DispatchQueue.main.async {
            self.isBluetoothOn = false
            self.errorMessage = "Bluetooth is turned off"
        }
    }
}
