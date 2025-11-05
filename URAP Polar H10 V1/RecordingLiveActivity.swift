//
//  RecordingLiveActivity.swift
//  RecordingWidget (Widget Extension)
//
//  IMPORTANT: Add this file to the Widget Extension target ONLY (not main app)
//  This defines the Live Activity widget configuration
//

import ActivityKit
import WidgetKit
import SwiftUI

@available(iOS 16.1, *)
struct RecordingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            // Lock screen/banner UI
            RecordingLockScreenView(context: context)

        } dynamicIsland: { context in
            // Dynamic Island UI
            DynamicIsland {
                // Expanded region - top area
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(.red)
                                .frame(width: 7, height: 7)

                            Text(context.state.recordingState)
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }

                        Text(context.state.sensorDescription)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(context.state.formattedDuration)
                            .font(.title)
                            .fontWeight(.heavy)
                            .foregroundColor(.white)
                            .monospacedDigit()

                        Text("Duration")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    // Tap anywhere to open app - no button needed
                    HStack {
                        Image(systemName: "waveform.path.ecg")
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.6))

                        Text("Tap to open app")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                }

            } compactLeading: {
                // Compact view - left side (shows when not expanded)
                HStack(spacing: 4) {
                    Circle()
                        .fill(.red)
                        .frame(width: 6, height: 6)

                    Text("REC")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                }

            } compactTrailing: {
                // Compact view - right side (shows duration)
                Text(context.state.formattedDuration)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)

            } minimal: {
                // Minimal view (smallest state - just a red dot)
                Circle()
                    .fill(.red)
                    .frame(width: 12, height: 12)
            }
            .keylineTint(.red)
        }
    }
}

// MARK: - Lock Screen View

@available(iOS 16.1, *)
struct RecordingLockScreenView: View {
    let context: ActivityViewContext<RecordingActivityAttributes>

    var body: some View {
        HStack(spacing: 16) {
            // Status indicator
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(context.state.statusEmoji)
                        .font(.title3)
                    Text(context.state.recordingState)
                        .font(.headline)
                        .fontWeight(.bold)
                }

                Text(context.state.sensorDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Duration
            VStack(alignment: .trailing, spacing: 4) {
                Text(context.state.formattedDuration)
                    .font(.title)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.red, .orange],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                Text("Duration")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
    }
}

// MARK: - Preview

@available(iOS 16.1, *)
struct RecordingLiveActivity_Previews: PreviewProvider {
    static let attributes = RecordingActivityAttributes(sessionId: "preview-session")
    static let contentState = RecordingActivityAttributes.ContentState(
        duration: 83,
        sensorCount: 2,
        recordingState: "Recording",
        lastUpdated: Date()
    )

    static var previews: some View {
        attributes
            .previewContext(contentState, viewKind: .content)
            .previewDisplayName("Lock Screen")

        attributes
            .previewContext(contentState, viewKind: .dynamicIsland(.compact))
            .previewDisplayName("Dynamic Island - Compact")

        attributes
            .previewContext(contentState, viewKind: .dynamicIsland(.expanded))
            .previewDisplayName("Dynamic Island - Expanded")

        attributes
            .previewContext(contentState, viewKind: .dynamicIsland(.minimal))
            .previewDisplayName("Dynamic Island - Minimal")
    }
}
