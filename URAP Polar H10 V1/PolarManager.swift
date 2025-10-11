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

/// Manages Polar H-10 device connection and real-time data streaming
class PolarManager: NSObject, ObservableObject {
    
    // MARK: - Published Properties (Real-time Updates)
    @Published var isBluetoothOn = false
    @Published var isScanning = false
    @Published var discoveredDevices: [PolarDeviceInfo] = []
    @Published var connectionState: ConnectionState = .disconnected
    
    // MARK: - Metrics
    @Published var heartRate: UInt8 = 0
    @Published var rrInterval: UInt16 = 0  // milliseconds
    @Published var batteryLevel: UInt = 0   // 0-100%
    
    // MARK: - Error Handling
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    private var api: PolarBleApi!
    private let disposeBag = DisposeBag()
    private var currentDeviceId: String?
    private var hrDisposable: Disposable?
    private var ppiDisposable: Disposable?
    
    // MARK: - Connection States
    enum ConnectionState {
        case disconnected
        case connecting
        case connected
        
        var displayText: String {
            switch self {
            case .disconnected: return "Disconnected"
            case .connecting: return "Connecting..."
            case .connected: return "Connected"
            }
        }
    }
    
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
        currentDeviceId = device.deviceId
        connectionState = .connecting
        errorMessage = nil
        
        do {
            try api.connectToDevice(device.deviceId)
        } catch {
            errorMessage = "Connection failed: \(error.localizedDescription)"
            connectionState = .disconnected
        }
    }
    
    func disconnect() {
        guard let deviceId = currentDeviceId else { return }
        
        // Stop streaming
        hrDisposable?.dispose()
        ppiDisposable?.dispose()
        
        do {
            try api.disconnectFromDevice(deviceId)
        } catch {
            errorMessage = "Disconnect failed: \(error.localizedDescription)"
        }
        
        connectionState = .disconnected
        currentDeviceId = nil
        resetMetrics()
    }
    
    // MARK: - Data Streaming
    private func startHeartRateStream() {
        guard let deviceId = currentDeviceId else { return }
        
        hrDisposable = api.startHrStreaming(deviceId)
            .observe(on: MainScheduler.instance)
            .subscribe { [weak self] event in
                switch event {
                case .next(let data):
                    guard let hrData = data.first else { return }
                    self?.heartRate = hrData.hr
                    
                    // RR intervals come with HR data - extract them here
                    if let rrMs = hrData.rrsMs.first {
                        self?.rrInterval = UInt16(rrMs)
                    }
                    
                case .error(let error):
                    // Only show critical errors, not streaming errors
                    print("HR stream error: \(error.localizedDescription)")
                    
                case .completed:
                    print("HR stream completed")
                }
            }
    }
    
    private func startRRIntervalStream() {
        guard let deviceId = currentDeviceId else { return }
        
        // Try to start PPI streaming, but don't show errors if it fails
        // RR intervals are already available from HR stream
        ppiDisposable = api.startPpiStreaming(deviceId)
            .observe(on: MainScheduler.instance)
            .subscribe { [weak self] event in
                switch event {
                case .next(let data):
                    if let sample = data.samples.first {
                        self?.rrInterval = sample.ppInMs
                    }
                    
                case .error(let error):
                    // PPI streaming often fails - just log it, don't show to user
                    print("PPI stream not available: \(error.localizedDescription)")
                    
                case .completed:
                    print("PPI stream completed")
                }
            }
    }
    
    private func resetMetrics() {
        heartRate = 0
        rrInterval = 0
        batteryLevel = 0
    }
}

// MARK: - PolarBleApiObserver (Connection Events)
extension PolarManager: PolarBleApiObserver {
    func deviceConnecting(_ polarDeviceInfo: PolarDeviceInfo) {
        DispatchQueue.main.async {
            self.connectionState = .connecting
        }
    }
    
    func deviceConnected(_ polarDeviceInfo: PolarDeviceInfo) {
        DispatchQueue.main.async {
            self.connectionState = .connected
            self.errorMessage = nil
        }
    }
    
    func deviceDisconnected(_ polarDeviceInfo: PolarDeviceInfo, pairingError: Bool) {
        DispatchQueue.main.async {
            self.connectionState = .disconnected
            self.currentDeviceId = nil
            self.resetMetrics()
            
            if pairingError {
                self.errorMessage = "Pairing error. Please unpair and reconnect."
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
            self.batteryLevel = batteryLevel
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
        print("Feature ready: \(feature)")
        
        DispatchQueue.main.async {
            switch feature {
            case .feature_hr:
                // Start streaming HR and RR interval data
                self.startHeartRateStream()
                self.startRRIntervalStream()
                
            case .feature_battery_info:
                print("Battery info feature ready")
                
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
        print("Streaming features ready: \(streamingFeatures)")
    }
}

// MARK: - PolarBleApiPowerStateObserver (Bluetooth State)
extension PolarManager: PolarBleApiPowerStateObserver {
    func blePowerOn() {
        DispatchQueue.main.async {
            self.isBluetoothOn = true
        }
    }
    
    func blePowerOff() {
        DispatchQueue.main.async {
            self.isBluetoothOn = false
            self.errorMessage = "Bluetooth is turned off"
        }
    }
}
