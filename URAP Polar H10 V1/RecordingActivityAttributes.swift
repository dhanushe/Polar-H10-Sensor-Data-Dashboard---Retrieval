//
//  RecordingActivityAttributes.swift
//  URAP Polar H10 V1
//
//  Defines the data structure for recording Live Activities
//  This file must be added to BOTH the main app target AND the widget extension target
//

import ActivityKit
import Foundation

/// Attributes for the recording session Live Activity
/// Shows session duration and number of sensors recording in Dynamic Island
struct RecordingActivityAttributes: ActivityAttributes {

    /// Static attributes that don't change during the activity
    public struct ContentState: Codable, Hashable {
        /// Current session duration in seconds
        var duration: TimeInterval

        /// Number of sensors currently recording
        var sensorCount: Int

        /// Current recording state ("Recording" or "Paused")
        var recordingState: String

        /// Timestamp of last update for display purposes
        var lastUpdated: Date

        /// Formatted duration string for display (e.g., "01:23")
        var formattedDuration: String {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return String(format: "%02d:%02d", minutes, seconds)
        }

        /// Recording status emoji
        var statusEmoji: String {
            recordingState == "Recording" ? "🔴" : "⏸"
        }

        /// Sensor count description
        var sensorDescription: String {
            sensorCount == 1 ? "1 sensor" : "\(sensorCount) sensors"
        }
    }

    /// Session identifier (doesn't change during activity)
    var sessionId: String
}
