// Closes the bar's popups once the cursor is neither on the bar nor in a
// popup: sketchybar's mouse.exited.global does not fire when the cursor
// leaves straight onto a window above the bar, which left popups
// standing. Polls while a popup is up (sketchybar's popups are its
// windows at layer 101), idles otherwise. sketchybarrc compiles this
// into the cache dir and keeps one instance running.
import CoreGraphics
import Foundation

let closeCmd = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
var missedTicks = 0

func sketchybarWindows() -> [(layer: Int, rect: CGRect)] {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return [] }
    return list.compactMap { w in
        guard (w[kCGWindowOwnerName as String] as? String) == "sketchybar",
              let b = w[kCGWindowBounds as String] as? [String: Double],
              let x = b["X"], let y = b["Y"], let width = b["Width"], let height = b["Height"],
              x > -9000 else { return nil }
        return (w[kCGWindowLayer as String] as? Int ?? 0, CGRect(x: x, y: y, width: width, height: height))
    }
}

while true {
    let wins = sketchybarWindows()
    let popups = wins.filter { $0.layer == 101 }
    if popups.isEmpty {
        missedTicks = 0
        usleep(400_000)
        continue
    }
    let mouse = CGEvent(source: nil)?.location ?? .zero
    // a little slack around every window: the cursor crosses the gap
    // between an item and its popup
    let inside = wins.contains { $0.rect.insetBy(dx: -6, dy: -6).contains(mouse) }
    if inside {
        missedTicks = 0
    } else {
        missedTicks += 1
        if missedTicks >= 2 {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/bash")
            task.arguments = ["-c", closeCmd]
            try? task.run()
            task.waitUntilExit()
            missedTicks = 0
        }
    }
    usleep(150_000)
}
