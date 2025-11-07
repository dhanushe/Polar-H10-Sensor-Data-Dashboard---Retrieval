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
import UIKit
import ActivityKit

// MARK: - Data Point Models
struct HeartRateDataPoint: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let monotonicTimestamp: TimeInterval  // High-precision monotonic time from CACurrentMediaTime()
    let value: UInt8

    init(timestamp: Date, monotonicTimestamp: TimeInterval, value: UInt8) {
        self.id = UUID()
        self.timestamp = timestamp
        self.monotonicTimestamp = monotonicTimestamp
        self.value = value
    }
}

struct RRIntervalDataPoint: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let monotonicTimestamp: TimeInterval  // High-precision monotonic time from CACurrentMediaTime()
    let value: UInt16

    init(timestamp: Date, monotonicTimestamp: TimeInterval, value: UInt16) {
        self.id = UUID()
        self.timestamp = timestamp
        self.monotonicTimestamp = monotonicTimestamp
        self.value = value
    }
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
    var timingSession: TimingSession?
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

    // Thread-safe queue for statistics updates
    private let statsQueue: DispatchQueue

    init(deviceId: String, deviceName: String) {
        self.id = deviceId
        self.deviceName = deviceName
        // Create unique queue for this sensor's statistics
        self.statsQueue = DispatchQueue(label: "com.urap.sensorStats.\(deviceId)", qos: .userInitiated)
    }

    deinit {
        // Clean up RxSwift disposables to prevent memory leaks
        hrDisposable?.dispose()
        ppiDisposable?.dispose()
        print("🧹 ConnectedSensor \(id) deallocated - disposables cleaned")
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
        let previousState = recordingState
        recordingState = .recording

        // Create fresh timing session when starting new recording (from idle)
        // Keep existing session when resuming (from paused)
        if previousState == .idle {
            // Starting a new recording - reset timer to 00:00
            timingSession = TimingSession(sessionId: id)
            sessionStartTime = timingSession?.startWallTime
            sessionStartMonotonicTime = timingSession?.startMonotonicTime
            print("🎬 Started new recording session for \(displayId) - timer reset to 00:00")
        } else if previousState == .paused {
            // Resuming from pause - keep existing timing session
            print("▶️ Resumed recording session for \(displayId) - timer continuing from pause")
        }
    }

    func pauseRecording() {
        recordingState = .paused
        print("⏸ Paused recording session for \(displayId)")
    }

    func stopRecording() {
        recordingState = .idle
        print("⏹ Stopped recording session for \(displayId)")
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

        // Update statistics in thread-safe manner
        statsQueue.async { [weak self] in
            guard let self = self else { return }

            // Perform calculations on background queue
            let needsMinUpdate = self.minHeartRate == 0 || hr < self.minHeartRate
            let needsMaxUpdate = hr > self.maxHeartRate

            // Update @Published properties on main thread
            DispatchQueue.main.async {
                if needsMinUpdate {
                    self.minHeartRate = hr
                }
                if needsMaxUpdate {
                    self.maxHeartRate = hr
                }
            }

            // Update non-published statistics (these are thread-safe as Int operations)
            // Note: These are accessed atomically, but we use statsQueue for consistency
            self.heartRateSum += UInt64(hr)
            self.totalHeartRateSamples += 1
        }
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

        // Safety assertions for development/testing
        assert(!values.isEmpty, "HRV: values array should not be empty after guard")
        assert(values.count >= 5, "HRV: requires at least 5 samples after guard")
        assert(values.allSatisfy { $0 > 0 }, "HRV: all RR interval values must be positive")

        // Defensive check for production (guards against division by zero)
        guard values.count > 0 else {
            print("⚠️ HRV calculation error: empty values array")
            sdnn = 0
            rmssd = 0
            return
        }

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

    // MARK: - Live Activity Manager
    private var liveActivityManager: LiveActivityManager? {
        if #available(iOS 16.1, *) {
            return LiveActivityManager.shared
        }
        return nil
    }

    // MARK: - Private Properties
    private var api: PolarBleApi?
    private let disposeBag = DisposeBag()
    private var sensors: [String: ConnectedSensor] = [:] // deviceId -> sensor

    // MARK: - Background Support
    private var devicesToMaintain: Set<String> = [] // Devices that should stay connected
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private let backgroundTaskQueue = DispatchQueue(label: "com.urap.backgroundTask")
    private var connectionHealthTimer: Timer?
    private var reconnectionAttempts: [String: Int] = [:] // deviceId -> attempt count
    private let maxReconnectionAttempts = 5

    // Singleton instance for app lifecycle access
    static let shared = PolarManager()

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

        // Defensive check - should never happen, but guard against SDK failure
        guard let initializedApi = api else {
            fatalError("❌ CRITICAL: Failed to initialize PolarBleApi - SDK initialization failed")
        }

        // Configure API observers - safe to force unwrap here since we just validated it
        api!.polarFilter(true)  // Filter to show only Polar devices
        api!.observer = self
        api!.deviceInfoObserver = self
        api!.deviceFeaturesObserver = self
        api!.powerStateObserver = self

        isBluetoothOn = initializedApi.isBlePowered

        // Set initial error message if Bluetooth is off
        if !isBluetoothOn {
            errorMessage = "Bluetooth is turned off"
        }
    }
    
    // MARK: - Device Search
    func startScanning() {
        guard let api = api else {
            errorMessage = "Bluetooth API not initialized"
            return
        }

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
        guard let api = api else {
            errorMessage = "Bluetooth API not initialized"
            return
        }

        stopScanning()
        errorMessage = nil

        // Create new sensor instance
        let sensor = ConnectedSensor(deviceId: device.deviceId, deviceName: device.name)
        sensors[device.deviceId] = sensor
        updateConnectedSensorsList()

        // Add to devices to maintain connection for
        devicesToMaintain.insert(device.deviceId)
        reconnectionAttempts[device.deviceId] = 0

        do {
            try api.connectToDevice(device.deviceId)
        } catch {
            errorMessage = "Connection failed: \(error.localizedDescription)"
            sensors.removeValue(forKey: device.deviceId)
            devicesToMaintain.remove(device.deviceId)
            updateConnectedSensorsList()
        }
    }

    func disconnect(deviceId: String) {
        guard let sensor = sensors[deviceId] else { return }
        guard let api = api else {
            errorMessage = "Bluetooth API not initialized"
            return
        }

        // Remove from devices to maintain
        devicesToMaintain.remove(deviceId)
        reconnectionAttempts.removeValue(forKey: deviceId)

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

        // Update Live Activity sensor count if recording
        if globalRecordingState == .recording {
            let recordingSensorCount = sensors.values.filter { $0.recordingState == .recording }.count
            liveActivityManager?.updateSensorCount(recordingSensorCount)
        }
    }

    // MARK: - Global Recording Controls

    func startAllRecordings() {
        globalRecordingState = .recording
        for sensor in sensors.values {
            sensor.startRecording()
        }

        // Start Live Activity to show in Dynamic Island
        let recordingSensorCount = sensors.values.filter { $0.recordingState == .recording }.count
        liveActivityManager?.startRecordingActivity(sensorCount: recordingSensorCount, recordingState: "Recording")
        print("📱 Started Live Activity with \(recordingSensorCount) sensors")
    }

    func pauseAllRecordings() {
        globalRecordingState = .paused
        for sensor in sensors.values {
            sensor.pauseRecording()
        }

        // End Live Activity when paused
        liveActivityManager?.endActivity()
        print("📱 Ended Live Activity (paused)")
    }

    func stopAllRecordings() {
        globalRecordingState = .idle
        for sensor in sensors.values {
            sensor.stopRecording()
        }

        // End Live Activity when stopped
        liveActivityManager?.endActivity()
        print("📱 Ended Live Activity (stopped)")
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

    /// Checks if any sensors are recording individually (not from "Start All")
    /// Returns true if sensors are recording but global state is idle
    var hasIndividualRecordings: Bool {
        globalRecordingState == .idle && sensors.values.contains { $0.recordingState == .recording }
    }

    var globalSessionDuration: TimeInterval {
        // Return longest session duration among all sensors
        sensors.values.map { $0.sessionDuration }.max() ?? 0
    }

    // MARK: - Background Lifecycle Management

    func handleAppBackground() {
        print("📱 App entering background - requesting extended background time")

        // Request background execution time from iOS (thread-safe)
        backgroundTaskQueue.sync {
            guard backgroundTask == .invalid else {
                print("⚠️ Background task already active")
                return
            }

            backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
                print("⏰ Background task expired - cleaning up")
                self?.endBackgroundTask()
            }
        }

        // Start monitoring connection health
        startConnectionHealthMonitoring()

        print("✅ Background mode activated - connections will be maintained")
    }

    func handleAppForeground() {
        print("📱 App entering foreground - checking connection health")

        // Stop background task
        endBackgroundTask()

        // Stop health monitoring timer
        stopConnectionHealthMonitoring()

        // Check all connections and reconnect if needed
        reconnectLostDevices()

        // Restart all data streams to ensure they're active
        // This is critical because streams may have been suspended in background
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.restartStreamsForConnectedDevices()
        }

        print("✅ Foreground mode activated")
    }

    private func endBackgroundTask() {
        backgroundTaskQueue.sync {
            guard backgroundTask != .invalid else { return }
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
            print("🛑 Background task ended")
        }
    }

    // MARK: - Connection Health Monitoring

    private func startConnectionHealthMonitoring() {
        // Check connection health every 10 seconds in background
        connectionHealthTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.checkConnectionHealth()
        }
    }

    private func stopConnectionHealthMonitoring() {
        connectionHealthTimer?.invalidate()
        connectionHealthTimer = nil
    }

    private func checkConnectionHealth() {
        print("🔍 Checking connection health...")

        for deviceId in devicesToMaintain {
            guard let sensor = sensors[deviceId] else {
                print("⚠️ Sensor \(deviceId) not found - attempting reconnection")
                attemptReconnection(deviceId: deviceId)
                continue
            }

            if sensor.connectionState != .connected {
                print("⚠️ Sensor \(deviceId) disconnected - attempting reconnection")
                attemptReconnection(deviceId: deviceId)
            } else {
                // Reset reconnection attempts for healthy connections
                reconnectionAttempts[deviceId] = 0
                print("✅ Sensor \(deviceId) healthy")
            }
        }
    }

    // MARK: - Automatic Reconnection

    private func reconnectLostDevices() {
        print("🔄 Checking for lost connections...")

        for deviceId in devicesToMaintain {
            guard let sensor = sensors[deviceId] else {
                print("⚠️ Sensor \(deviceId) lost - will attempt reconnection")
                attemptReconnection(deviceId: deviceId)
                continue
            }

            if sensor.connectionState != .connected {
                print("⚠️ Sensor \(deviceId) not connected - attempting reconnection")
                attemptReconnection(deviceId: deviceId)
            }
        }
    }

    private func attemptReconnection(deviceId: String) {
        let attempts = reconnectionAttempts[deviceId] ?? 0

        guard attempts < maxReconnectionAttempts else {
            print("❌ Max reconnection attempts reached for \(deviceId)")
            errorMessage = "Failed to reconnect to device \(deviceId.suffix(6))"
            return
        }

        reconnectionAttempts[deviceId] = attempts + 1

        // Calculate exponential backoff delay
        let delay = Double(attempts) * 2.0

        print("🔄 Reconnection attempt \(attempts + 1)/\(maxReconnectionAttempts) for \(deviceId) in \(delay)s")

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            guard let api = self.api else {
                print("❌ Bluetooth API not initialized for reconnection")
                return
            }

            // Check if we should still try to reconnect
            guard self.devicesToMaintain.contains(deviceId) else {
                print("⏭️ Skipping reconnection - device no longer in maintain list")
                return
            }

            do {
                print("🔌 Attempting to reconnect to \(deviceId)...")
                try api.connectToDevice(deviceId)
            } catch {
                print("❌ Reconnection failed: \(error.localizedDescription)")

                // Try again if we haven't exceeded max attempts
                if attempts + 1 < self.maxReconnectionAttempts {
                    self.attemptReconnection(deviceId: deviceId)
                } else {
                    self.errorMessage = "Failed to reconnect to device \(deviceId.suffix(6))"
                }
            }
        }
    }

    // MARK: - Data Streaming

    /// Restart streams for all connected devices (used after returning from background)
    private func restartStreamsForConnectedDevices() {
        print("🔄 Restarting data streams for all connected devices...")

        for (deviceId, sensor) in sensors {
            if sensor.connectionState == .connected {
                restartStreams(for: deviceId)
            }
        }
    }

    /// Restart data streams for a specific device
    private func restartStreams(for deviceId: String) {
        guard let sensor = sensors[deviceId] else { return }

        print("🔄 Restarting streams for device \(deviceId)")

        // Dispose existing streams to avoid duplicates
        sensor.hrDisposable?.dispose()
        sensor.ppiDisposable?.dispose()

        // Small delay to ensure clean disposal
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startHeartRateStream(for: deviceId)
            self?.startRRIntervalStream(for: deviceId)
        }
    }

    private func startHeartRateStream(for deviceId: String) {
        guard let sensor = sensors[deviceId] else { return }
        guard let api = api else {
            print("❌ Bluetooth API not initialized for HR streaming")
            return
        }

        sensor.hrDisposable = api.startHrStreaming(deviceId)
            .observe(on: MainScheduler.instance)
            .subscribe { [weak sensor] event in
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
        guard let api = api else {
            print("❌ Bluetooth API not initialized for PPI streaming")
            return
        }

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

                // Reset reconnection attempts on successful connection
                self.reconnectionAttempts[polarDeviceInfo.deviceId] = 0

                // If this is a reconnection (device is in maintain list but streams might be stale),
                // restart the streams to ensure data flows
                if self.devicesToMaintain.contains(polarDeviceInfo.deviceId) {
                    print("✅ Device \(polarDeviceInfo.deviceId) connected - will restart streams")
                    // Small delay to ensure connection is fully established
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        self?.restartStreams(for: polarDeviceInfo.deviceId)
                    }
                }
            }
            self.errorMessage = nil
            self.updateConnectedSensorsList()
        }
    }

    func deviceDisconnected(_ polarDeviceInfo: PolarDeviceInfo, pairingError: Bool) {
        DispatchQueue.main.async {
            if let sensor = self.sensors[polarDeviceInfo.deviceId] {
                sensor.connectionState = .disconnected
                // Don't reset metrics - we want to preserve data during reconnection
            }

            if pairingError {
                self.errorMessage = "Pairing error with \(polarDeviceInfo.name)"
            }

            // If this device should be maintained, attempt reconnection
            if self.devicesToMaintain.contains(polarDeviceInfo.deviceId) {
                print("🔄 Device \(polarDeviceInfo.deviceId) disconnected unexpectedly - will reconnect")
                self.attemptReconnection(deviceId: polarDeviceInfo.deviceId)
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
