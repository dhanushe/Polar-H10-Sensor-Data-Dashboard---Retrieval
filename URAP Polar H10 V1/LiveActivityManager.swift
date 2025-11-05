//
//  LiveActivityManager.swift
//  URAP Polar H10 V1
//
//  Manages Live Activities for recording sessions
//  Handles activity lifecycle: start, update, end
//

import ActivityKit
import Foundation
import Combine

/// Manages the Live Activity for recording sessions
/// Displays session duration and sensor count in Dynamic Island
@available(iOS 16.1, *)
class LiveActivityManager: ObservableObject {

    // MARK: - Singleton

    static let shared = LiveActivityManager()

    // MARK: - Properties

    /// Current active recording activity
    @Published private(set) var currentActivity: Activity<RecordingActivityAttributes>?

    /// Timer for periodic activity updates
    private var updateTimer: Timer?

    /// Session start time for duration calculation
    private var sessionStartTime: Date?

    /// Number of sensors recording
    private var currentSensorCount: Int = 0

    /// Recording state
    private var currentRecordingState: String = "Recording"

    // MARK: - Initialization

    private init() {
        print("📱 LiveActivityManager initialized")
    }

    // MARK: - Activity Lifecycle

    /// Starts a new recording Live Activity
    /// - Parameters:
    ///   - sensorCount: Number of sensors currently recording
    ///   - recordingState: Current recording state ("Recording" or "Paused")
    func startRecordingActivity(sensorCount: Int, recordingState: String = "Recording") {
        // End any existing activity first
        endActivity()

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("⚠️ Live Activities are not enabled")
            return
        }

        do {
            // Create initial content state
            let initialState = RecordingActivityAttributes.ContentState(
                duration: 0,
                sensorCount: sensorCount,
                recordingState: recordingState,
                lastUpdated: Date()
            )

            // Create activity attributes
            let attributes = RecordingActivityAttributes(
                sessionId: UUID().uuidString
            )

            // Request the activity
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil
            )

            currentActivity = activity
            sessionStartTime = Date()
            currentSensorCount = sensorCount
            currentRecordingState = recordingState

            print("✅ Live Activity started: \(activity.id)")

            // Start periodic updates
            startPeriodicUpdates()

        } catch {
            print("❌ Failed to start Live Activity: \(error.localizedDescription)")
        }
    }

    /// Updates the current activity with new sensor count
    /// - Parameter sensorCount: Updated number of sensors recording
    func updateSensorCount(_ sensorCount: Int) {
        guard sensorCount != currentSensorCount else { return }
        currentSensorCount = sensorCount
        updateActivityNow()
    }

    /// Updates the recording state
    /// - Parameter state: New recording state ("Recording" or "Paused")
    func updateRecordingState(_ state: String) {
        guard state != currentRecordingState else { return }
        currentRecordingState = state
        updateActivityNow()
    }

    /// Ends the current Live Activity
    func endActivity() {
        guard let activity = currentActivity else { return }

        // Stop the update timer
        stopPeriodicUpdates()

        Task {
            // Create final content state
            let finalDuration = sessionStartTime.map { Date().timeIntervalSince($0) } ?? 0
            let finalState = RecordingActivityAttributes.ContentState(
                duration: finalDuration,
                sensorCount: currentSensorCount,
                recordingState: "Stopped",
                lastUpdated: Date()
            )

            // End the activity with final state
            await activity.end(
                .init(state: finalState, staleDate: nil),
                dismissalPolicy: .immediate
            )

            print("✅ Live Activity ended: \(activity.id)")
        }

        currentActivity = nil
        sessionStartTime = nil
        currentSensorCount = 0
        currentRecordingState = "Recording"
    }

    // MARK: - Private Methods

    /// Starts periodic timer to update activity duration
    private func startPeriodicUpdates() {
        // Update every second to keep duration timer accurate
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateActivityNow()
        }
    }

    /// Stops the periodic update timer
    private func stopPeriodicUpdates() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    /// Immediately updates the activity with current values
    private func updateActivityNow() {
        guard let activity = currentActivity,
              let startTime = sessionStartTime else {
            return
        }

        Task {
            // Calculate current duration
            let currentDuration = Date().timeIntervalSince(startTime)

            // Create updated content state
            let updatedState = RecordingActivityAttributes.ContentState(
                duration: currentDuration,
                sensorCount: currentSensorCount,
                recordingState: currentRecordingState,
                lastUpdated: Date()
            )

            // Update the activity
            await activity.update(
                .init(state: updatedState, staleDate: nil)
            )
        }
    }
}
