// Pushes keyboard layout changes to sketchybar: macOS posts a distributed
// notification on every input source switch, so the bar's keyboard item
// gets an event with the new source instead of polling the HIToolbox
// preferences. sketchybarrc compiles this into the cache dir and keeps
// one instance running (runs until killed).

import Carbon
import Foundation

func currentSource() -> String {
    let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
        return ""
    }
    return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
}

func notify() {
    let sketchybar = Process()
    sketchybar.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    sketchybar.arguments = [
        "sketchybar", "--trigger", "input_source_change",
        "INPUT_SOURCE=\(currentSource())",
    ]
    try? sketchybar.run()
    sketchybar.waitUntilExit()
}

DistributedNotificationCenter.default().addObserver(
    forName: NSNotification.Name("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"),
    object: nil, queue: nil
) { _ in notify() }

notify()
RunLoop.main.run()
