//
//  RecordingWidgetBundle.swift
//  RecordingWidget
//
//  Updated to use custom RecordingLiveActivity for Dynamic Island
//

import WidgetKit
import SwiftUI

@main
struct RecordingWidgetBundle: WidgetBundle {
    var body: some Widget {
        // Register our custom Live Activity for recording sessions
        RecordingLiveActivity()
    }
}
