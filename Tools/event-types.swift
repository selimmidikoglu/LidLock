#!/usr/bin/env swift
//
//  Which event types does a session tap actually see?
//
//  LidLock can only swallow what reaches its tap. If a gesture still escapes
//  the shield, the question is whether the tap never sees it (the window server
//  handled it first) or sees it under a type the mask is missing.
//
//  Run it, then do the gesture in question:
//
//      swift Tools/event-types.swift
//
//  The host terminal needs Accessibility access, not LidLock.
//
import ApplicationServices
import CoreGraphics
import Foundation

let names: [UInt32: String] = [
    1: "leftMouseDown", 2: "leftMouseUp", 3: "rightMouseDown", 4: "rightMouseUp",
    5: "mouseMoved", 6: "leftMouseDragged", 7: "rightMouseDragged",
    10: "keyDown", 11: "keyUp", 12: "flagsChanged", 14: "systemDefined",
    18: "rotate", 19: "beginGesture", 20: "endGesture", 22: "scrollWheel",
    25: "otherMouseDown", 26: "otherMouseUp", 27: "otherMouseDragged",
    29: "gesture", 30: "magnify", 31: "swipe", 32: "smartMagnify",
    34: "pressure", 37: "directTouch", 38: "changeMode",
]

/// Everything a tap could plausibly carry, so nothing is missed by omission.
let mask: CGEventMask = (1...63).reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1)) }

final class Counter { var seen: [UInt32: Int] = [:] }
let counter = Counter()

guard AXIsProcessTrusted() else {
    print("No Accessibility access for this terminal. Grant it in")
    print("System Settings › Privacy & Security › Accessibility, then rerun.")
    exit(1)
}

guard let port = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .tailAppendEventTap,
    options: .listenOnly,
    eventsOfInterest: mask,
    callback: { _, type, event, refcon in
        let counter = Unmanaged<Counter>.fromOpaque(refcon!).takeUnretainedValue()
        counter.seen[type.rawValue, default: 0] += 1
        return Unmanaged.passUnretained(event)
    },
    userInfo: Unmanaged.passUnretained(counter).toOpaque()
) else {
    print("Could not create the tap.")
    exit(1)
}

CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0), .commonModes)
CGEvent.tapEnable(tap: port, enable: true)

let seconds = 15.0
print("Listening for \(Int(seconds))s — do the gesture now (three-finger swipe, pinch, whatever escapes).")
RunLoop.current.run(until: Date().addingTimeInterval(seconds))

print("\nEvent types that reached the tap:")
for (type, count) in counter.seen.sorted(by: { $0.key < $1.key }) {
    let name = names[type] ?? "unknown"
    print(String(format: "  %3d  %-16s %6d", type, (name as NSString).utf8String!, count))
}
if counter.seen.isEmpty {
    print("  (nothing — the tap saw no input at all)")
}
