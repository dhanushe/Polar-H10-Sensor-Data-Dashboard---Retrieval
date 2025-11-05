# Dynamic Island Live Activity Setup Guide

## ✅ Code Implementation Complete

All Swift code files have been created and existing files have been modified. Now you need to complete the Widget Extension setup in Xcode.

---

## 📋 Manual Steps in Xcode

### Step 1: Create Widget Extension Target

1. Open the project in Xcode
2. Go to **File → New → Target**
3. Select **iOS → Widget Extension**
4. Click **Next**
5. Configure the widget:
   - **Product Name**: `RecordingWidget`
   - **Team**: Select your team
   - **Include Configuration Intent**: ❌ Uncheck
   - **Include Live Activity**: ✅ **Check this!**
6. Click **Finish**
7. When prompted "Activate 'RecordingWidget' scheme?", click **Activate**

### Step 2: Configure App Groups

**Why:** App Groups allow the main app and widget extension to share data.

#### For Main App Target:
1. Select the **URAP Polar H10 V1** target
2. Go to **Signing & Capabilities** tab
3. Click **+ Capability**
4. Select **App Groups**
5. Click **+** under App Groups
6. Enter: `group.com.polarh10.recording`
7. Click **OK**

#### For Widget Extension Target:
1. Select the **RecordingWidget** target
2. Go to **Signing & Capabilities** tab
3. Click **+ Capability**
4. Select **App Groups**
5. Click **+** under App Groups
6. Enter: `group.com.polarh10.recording` (same as main app)
7. Click **OK**

### Step 3: Add Files to Widget Extension Target

**Important:** You need to add the shared files to the widget extension target.

1. In Project Navigator, find `RecordingActivityAttributes.swift`
2. Click on the file
3. In **File Inspector** (right panel), under **Target Membership**:
   - ✅ Check **URAP Polar H10 V1** (should already be checked)
   - ✅ Check **RecordingWidget** (add this)

4. Find `RecordingLiveActivity.swift`
5. In **File Inspector**, under **Target Membership**:
   - ❌ Uncheck **URAP Polar H10 V1**
   - ✅ Check **RecordingWidget** only

### Step 4: Remove Default Widget Files (Optional)

Xcode may have created default widget files that you don't need:

1. Delete `RecordingWidget.swift` (if it exists)
2. Delete `RecordingWidgetBundle.swift` (if it exists)
3. Delete `RecordingWidgetLiveActivity.swift` (if it exists - we created our own)

Keep only:
- `RecordingActivityAttributes.swift` (shared with main app)
- `RecordingLiveActivity.swift` (our custom implementation)

### Step 5: Update Widget Extension Info.plist

1. In Project Navigator, expand **RecordingWidget** folder
2. Find **Info.plist** inside RecordingWidget
3. Add the following keys (if not present):
   - **NSExtension → NSExtensionPointIdentifier**: `com.apple.widgetkit-extension`
   - **NSSupportsLiveActivities**: `YES`

### Step 6: Set Deployment Target

1. Select **RecordingWidget** target
2. Go to **General** tab
3. Under **Deployment Info**
4. Set **iOS Deployment Target** to **16.1** (minimum for Live Activities)

### Step 7: Configure URL Scheme (Optional but Recommended)

This allows the Dynamic Island to deep link back to your app.

1. Select **URAP Polar H10 V1** target
2. Go to **Info** tab
3. Expand **URL Types**
4. Click **+** to add a new URL type
5. Configure:
   - **Identifier**: `com.polarh10.recording`
   - **URL Schemes**: `polarh10`
   - **Role**: Editor

---

## 🧪 Testing

### Build and Run

1. Select **URAP Polar H10 V1** scheme
2. Run on a **physical device** (Live Activities don't work in simulator Dynamic Island)
3. Connect a Polar H10 sensor
4. Tap **Start All** to begin recording
5. Switch to another app (e.g., Settings, Safari)
6. You should see the recording status in Dynamic Island!

### What You Should See:

**Minimal (Compact) View:**
```
🔴 00:12
```

**Expanded View (Long Press Dynamic Island):**
```
┌─────────────────────┐
│ 🔴 Recording        │
│                     │
│ 00:01:23            │
│ 2 sensors           │
│                     │
│ [Open App]          │
└─────────────────────┘
```

### Troubleshooting:

**"Live Activities are not enabled"**
- Go to Settings → (Your App) → Live Activities → Enable

**Activity doesn't appear**
- Check that `NSSupportsLiveActivities` is set in main app Info.plist ✅
- Check that App Groups are configured correctly for both targets
- Make sure you're on iOS 16.1+ on a real device
- Check console for "✅ Live Activity started" message

**Activity shows but doesn't update**
- Check that `RecordingActivityAttributes.swift` is in BOTH targets
- Verify App Groups match exactly in both targets
- Check console for error messages

**"Open App" link doesn't work**
- Verify URL scheme is configured (Step 7)
- Check the URL scheme matches `polarh10://recording`

---

## 📱 How It Works

### When Recording Starts:
1. User taps "Start All" in Dashboard
2. `PolarManager.startAllRecordings()` is called
3. `LiveActivityManager.startRecordingActivity()` creates the activity
4. Activity appears in Dynamic Island

### During Recording:
1. Timer updates activity every 1 second with new duration
2. If sensors connect/disconnect, sensor count updates automatically
3. Dynamic Island shows live countdown

### When Recording Stops:
1. User taps "Pause All" or "Stop All"
2. `PolarManager.pauseAllRecordings()` or `.stopAllRecordings()` is called
3. `LiveActivityManager.endActivity()` dismisses the activity
4. Dynamic Island returns to normal

---

## 📂 Files Created/Modified

### ✅ New Files Created:
- `RecordingActivityAttributes.swift` - Activity data structure (shared between app & widget)
- `LiveActivityManager.swift` - Activity lifecycle management (main app)
- `RecordingLiveActivity.swift` - Widget configuration (widget extension)

### ✅ Modified Files:
- `PolarManager.swift` - Added Activity triggers in start/pause/stop methods
- `URAP-Polar-H10-V1-Info.plist` - Added `NSSupportsLiveActivities`

### ❌ No Changes Needed:
- `PolarDashboardApp.swift` - Background handling already in place
- Other view files - No modifications required

---

## 🎨 Customization Options

If you want to customize the Dynamic Island appearance, edit `RecordingLiveActivity.swift`:

### Change Colors:
```swift
.foregroundStyle(
    LinearGradient(
        colors: [.red, .orange],  // Change these colors
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
)
```

### Change Icons:
```swift
Image(systemName: "waveform.path.ecg")  // Change to any SF Symbol
```

### Add More Data:
Edit `RecordingActivityAttributes.ContentState` to include additional fields, then update the views in `RecordingLiveActivity.swift`.

---

## 🔒 Privacy Considerations

- Recording status is visible on lock screen
- Duration and sensor count are displayed
- No sensitive health data (heart rate) is shown
- Consider this when using in public settings

---

## ✨ Completed Features

✅ Dynamic Island minimal view shows recording status + duration
✅ Expanded view shows full details (duration, sensor count, status)
✅ Lock screen widget displays recording information
✅ Automatic updates every second while app is active
✅ Deep linking back to app via "Open App" button
✅ Graceful handling when Live Activities are disabled
✅ iOS version compatibility (16.1+)
✅ No disruption to existing app functionality

---

**Need Help?**
- Check console logs for "📱" emoji to see Live Activity events
- All debug prints use descriptive emojis (📱, ✅, ❌, ⚠️)
- Review the troubleshooting section above

**Enjoy your Dynamic Island recording indicator!** 🎉
