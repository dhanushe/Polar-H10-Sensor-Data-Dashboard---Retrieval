//
//  RecordingsStorageManager.swift
//  URAP Polar H10 V1
//
//  Handles file system operations for recording persistence
//

import Foundation
import UIKit
import UniformTypeIdentifiers

/// Manages persistent storage of recording sessions
class RecordingsStorageManager {
    static let shared = RecordingsStorageManager()

    private let fileManager = FileManager.default
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder

    // Documents directory for recordings
    private var recordingsDirectory: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("Recordings", isDirectory: true)
    }

    private init() {
        jsonEncoder = JSONEncoder()
        jsonEncoder.dateEncodingStrategy = .iso8601
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        jsonDecoder = JSONDecoder()
        jsonDecoder.dateDecodingStrategy = .iso8601

        // Ensure recordings directory exists
        createRecordingsDirectoryIfNeeded()
    }

    // MARK: - Directory Management

    private func createRecordingsDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: recordingsDirectory.path) {
            do {
                try fileManager.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
                print("📁 Created recordings directory at: \(recordingsDirectory.path)")
            } catch {
                print("❌ Failed to create recordings directory: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Save Recording

    /// Save a recording session to disk
    func saveRecording(_ recording: RecordingSession) -> Result<URL, RecordingStorageError> {
        let fileURL = recordingsDirectory.appendingPathComponent(recording.fileName)

        do {
            let data = try jsonEncoder.encode(recording)
            try data.write(to: fileURL, options: [.atomic])
            print("✅ Saved recording: \(recording.name) (\(data.count) bytes)")
            return .success(fileURL)
        } catch {
            print("❌ Failed to save recording: \(error.localizedDescription)")
            return .failure(.saveFailed(error))
        }
    }

    // MARK: - Load Recordings

    /// Load all recording metadata (fast - doesn't load full data)
    func loadAllRecordingMetadata() -> Result<[RecordingSession], RecordingStorageError> {
        do {
            let fileURLs = try fileManager.contentsOfDirectory(
                at: recordingsDirectory,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            ).filter { $0.pathExtension == "json" }

            var recordings: [RecordingSession] = []

            for fileURL in fileURLs {
                if let recording = loadRecording(from: fileURL) {
                    recordings.append(recording)
                }
            }

            print("📖 Loaded \(recordings.count) recordings")
            return .success(recordings)

        } catch {
            print("❌ Failed to load recordings: \(error.localizedDescription)")
            return .failure(.loadFailed(error))
        }
    }

    /// Load a specific recording from file URL
    func loadRecording(from fileURL: URL) -> RecordingSession? {
        do {
            let data = try Data(contentsOf: fileURL)
            let recording = try jsonDecoder.decode(RecordingSession.self, from: data)
            return recording
        } catch {
            print("❌ Failed to decode recording at \(fileURL.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    /// Load a specific recording by ID
    func loadRecording(withId id: String) -> Result<RecordingSession?, RecordingStorageError> {
        do {
            let fileURLs = try fileManager.contentsOfDirectory(
                at: recordingsDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ).filter { $0.pathExtension == "json" }

            for fileURL in fileURLs {
                if let recording = loadRecording(from: fileURL), recording.id == id {
                    return .success(recording)
                }
            }

            return .success(nil) // Not found

        } catch {
            return .failure(.loadFailed(error))
        }
    }

    // MARK: - Delete Recording

    /// Delete a recording by ID
    func deleteRecording(withId id: String) -> Result<Void, RecordingStorageError> {
        do {
            let fileURLs = try fileManager.contentsOfDirectory(
                at: recordingsDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ).filter { $0.pathExtension == "json" }

            for fileURL in fileURLs {
                if let recording = loadRecording(from: fileURL), recording.id == id {
                    try fileManager.removeItem(at: fileURL)
                    print("🗑️ Deleted recording: \(recording.name)")
                    return .success(())
                }
            }

            return .failure(.recordingNotFound)

        } catch {
            print("❌ Failed to delete recording: \(error.localizedDescription)")
            return .failure(.deleteFailed(error))
        }
    }

    // MARK: - Update Recording

    /// Update an existing recording (e.g., rename)
    func updateRecording(_ recording: RecordingSession) -> Result<Void, RecordingStorageError> {
        // First delete the old file
        switch deleteRecording(withId: recording.id) {
        case .success:
            // Then save the updated version
            switch saveRecording(recording) {
            case .success:
                return .success(())
            case .failure(let error):
                return .failure(error)
            }
        case .failure(let error):
            return .failure(error)
        }
    }

    // MARK: - Export Functionality

    /// Export recording as JSON file
    func exportJSON(_ recording: RecordingSession) -> Result<URL, RecordingStorageError> {
        let tempDirectory = fileManager.temporaryDirectory
        let exportURL = tempDirectory.appendingPathComponent("export_\(recording.fileName)")

        do {
            let data = try jsonEncoder.encode(recording)
            try data.write(to: exportURL, options: [.atomic])
            print("📤 Exported JSON to: \(exportURL.path)")
            return .success(exportURL)
        } catch {
            return .failure(.exportFailed(error))
        }
    }

    /// Export recording as CSV files (zipped)
    func exportCSV(_ recording: RecordingSession) -> Result<URL, RecordingStorageError> {
        let tempDirectory = fileManager.temporaryDirectory
        let exportFolderName = "recording_\(recording.id)_csv"
        let exportFolder = tempDirectory.appendingPathComponent(exportFolderName)

        do {
            // Create export folder
            if fileManager.fileExists(atPath: exportFolder.path) {
                try fileManager.removeItem(at: exportFolder)
            }
            try fileManager.createDirectory(at: exportFolder, withIntermediateDirectories: true)

            // Create session info CSV
            let sessionInfo = createSessionInfoCSV(recording)
            let sessionInfoURL = exportFolder.appendingPathComponent("session_info.csv")
            try sessionInfo.write(to: sessionInfoURL, atomically: true, encoding: .utf8)

            // Create CSV files for each sensor
            for (index, sensor) in recording.sensorRecordings.enumerated() {
                let prefix = "sensor_\(index + 1)_\(sensor.sensorId)"

                // Heart rate CSV
                let hrCSV = sensor.heartRateCSV()
                let hrURL = exportFolder.appendingPathComponent("\(prefix)_hr.csv")
                try hrCSV.write(to: hrURL, atomically: true, encoding: .utf8)

                // RR interval CSV
                let rrCSV = sensor.rrIntervalCSV()
                let rrURL = exportFolder.appendingPathComponent("\(prefix)_rr.csv")
                try rrCSV.write(to: rrURL, atomically: true, encoding: .utf8)

                // Statistics CSV
                let statsCSV = sensor.statisticsCSV()
                let statsURL = exportFolder.appendingPathComponent("\(prefix)_statistics.csv")
                try statsCSV.write(to: statsURL, atomically: true, encoding: .utf8)
            }

            // Create zip file
            let zipURL = tempDirectory.appendingPathComponent("\(exportFolderName).zip")
            if fileManager.fileExists(atPath: zipURL.path) {
                try fileManager.removeItem(at: zipURL)
            }

            try fileManager.zipItem(at: exportFolder, to: zipURL)

            // Clean up export folder
            try fileManager.removeItem(at: exportFolder)

            print("📤 Exported CSV to: \(zipURL.path)")
            return .success(zipURL)

        } catch {
            return .failure(.exportFailed(error))
        }
    }

    private func createSessionInfoCSV(_ recording: RecordingSession) -> String {
        var csv = "Recording Information\n\n"
        csv += "Session ID,\(recording.id)\n"
        csv += "Recording Name,\(recording.name)\n"
        csv += "Start Time,\(ISO8601DateFormatter().string(from: recording.startDate))\n"
        csv += "End Time,\(ISO8601DateFormatter().string(from: recording.endDate))\n"
        csv += "Duration (seconds),\(String(format: "%.1f", recording.duration))\n"
        csv += "Number of Sensors,\(recording.sensorCount)\n"
        csv += "Total Data Points,\(recording.totalDataPoints)\n"
        csv += "Average Heart Rate (BPM),\(String(format: "%.1f", recording.averageHeartRate))\n"
        csv += "Average SDNN (ms),\(String(format: "%.2f", recording.averageSDNN))\n"
        csv += "Average RMSSD (ms),\(String(format: "%.2f", recording.averageRMSSD))\n\n"

        csv += "Sensors\n"
        csv += "Sensor ID,Sensor Name,HR Samples,RR Samples,Avg HR,SDNN,RMSSD\n"
        for sensor in recording.sensorRecordings {
            csv += "\(sensor.sensorId),\(sensor.sensorName),\(sensor.heartRateData.count),\(sensor.rrIntervalData.count),\(sensor.statistics.averageHeartRate),\(String(format: "%.2f", sensor.statistics.sdnn)),\(String(format: "%.2f", sensor.statistics.rmssd))\n"
        }

        return csv
    }

    // MARK: - Storage Statistics

    /// Get storage statistics
    func getStorageInfo() -> StorageInfo {
        do {
            let fileURLs = try fileManager.contentsOfDirectory(
                at: recordingsDirectory,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            ).filter { $0.pathExtension == "json" }

            var totalSize: Int64 = 0
            for url in fileURLs {
                let attributes = try fileManager.attributesOfItem(atPath: url.path)
                if let fileSize = attributes[.size] as? Int64 {
                    totalSize += fileSize
                }
            }

            return StorageInfo(recordingCount: fileURLs.count, totalSizeBytes: totalSize)

        } catch {
            print("❌ Failed to get storage info: \(error.localizedDescription)")
            return StorageInfo(recordingCount: 0, totalSizeBytes: 0)
        }
    }
}

// MARK: - Supporting Types

enum RecordingStorageError: LocalizedError {
    case saveFailed(Error)
    case loadFailed(Error)
    case deleteFailed(Error)
    case exportFailed(Error)
    case recordingNotFound
    case invalidData

    var errorDescription: String? {
        switch self {
        case .saveFailed(let error):
            return "Failed to save recording: \(error.localizedDescription)"
        case .loadFailed(let error):
            return "Failed to load recordings: \(error.localizedDescription)"
        case .deleteFailed(let error):
            return "Failed to delete recording: \(error.localizedDescription)"
        case .exportFailed(let error):
            return "Failed to export recording: \(error.localizedDescription)"
        case .recordingNotFound:
            return "Recording not found"
        case .invalidData:
            return "Invalid recording data"
        }
    }
}

struct StorageInfo {
    let recordingCount: Int
    let totalSizeBytes: Int64

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSizeBytes, countStyle: .file)
    }
}

// MARK: - FileManager ZIP Extension

extension FileManager {
    /// Create a ZIP archive of a directory
    func zipItem(at sourceURL: URL, to destinationURL: URL) throws {
        // Use Foundation's built-in compression
        let coordinator = NSFileCoordinator()
        var error: NSError?

        coordinator.coordinate(readingItemAt: sourceURL, options: [.forUploading], error: &error) { zipURL in
            do {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: zipURL, to: destinationURL)
            } catch {
                print("❌ ZIP error: \(error)")
            }
        }

        if let error = error {
            throw error
        }
    }
}
