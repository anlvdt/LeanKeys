import AppKit
import ApplicationServices
import Carbon
import CoreGraphics
import Foundation
import TypistCore

// Exit codes: 0 typed, 1 usage or event failure, 2 no Accessibility or tap,
// 3 guard refused, 4 interrupted by real input, 5 unmappable character.

let accessibilityPath = "System Settings > Privacy & Security > Accessibility"
let ownMarker: Int64 = 0x5745_4242       // "WEBB": typist's own events
let leanKeysMarker: Int64 = 0x474E_4820  // "GNH ": LeanKeys' reposted events

func fail(_ code: Int32, _ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

func usage() -> Never {
    fail(1, "usage: typist --keys <string> --speed human|fast|burst --seed <n> --bundle <id> --token <t>")
}

// MARK: - Arguments

let known: Set<String> = ["--keys", "--speed", "--seed", "--bundle", "--token"]
var values: [String: String] = [:]
var argIndex = 1
while argIndex < CommandLine.arguments.count {
    let flag = CommandLine.arguments[argIndex]
    guard known.contains(flag), argIndex + 1 < CommandLine.arguments.count else { usage() }
    values[flag] = CommandLine.arguments[argIndex + 1]
    argIndex += 2
}
guard let keys = values["--keys"], !keys.isEmpty,
      let expectedBundle = values["--bundle"], !expectedBundle.isEmpty,
      let token = values["--token"] else { usage() }

let speed: Speed
if let raw = values["--speed"] {
    guard let parsed = Speed(rawValue: raw) else { usage() }
    speed = parsed
} else {
    speed = .human
}

let seed: UInt64
if let raw = values["--seed"] {
    guard let parsed = UInt64(raw) else { usage() }
    seed = parsed
} else {
    seed = 1
}

// MARK: - Accessibility (checked before any event is created)

guard AXIsProcessTrusted() else {
    fail(2, "typist: this terminal is not trusted for Accessibility. Enable it in \(accessibilityPath), then retry.")
}

// MARK: - Key mapping (pure; nothing posted yet)

var strokes: [(keyCode: CGKeyCode, shift: Bool)] = []
for c in keys {
    guard let stroke = KeyMap.stroke(for: c) else {
        fail(5, "typist: character \"\(c)\" cannot be typed on the US layout")
    }
    strokes.append(stroke)
}

// MARK: - Guard inputs

func currentLayoutID() -> String {
    guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
          let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "" }
    return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
}

func frontWindowTitle() -> String? {
    guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
    let axApp = AXUIElementCreateApplication(app.processIdentifier)
    var windowRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
          let windowRef else { return nil }
    let window = windowRef as! AXUIElement
    var titleRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success else {
        return nil
    }
    return titleRef as? String
}

func guardAllows() -> Bool {
    Guard.mayType(
        frontBundle: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
        windowTitle: frontWindowTitle(),
        expectedBundle: expectedBundle,
        token: token,
        layoutID: currentLayoutID()
    )
}

// MARK: - Interrupt detection (listen-only tap)

final class InterruptState {
    var interrupted = false
}

let interrupt = InterruptState()
let eventMask: CGEventMask =
    (1 << CGEventType.keyDown.rawValue)
    | (1 << CGEventType.mouseMoved.rawValue)
    | (1 << CGEventType.leftMouseDown.rawValue)

let tapCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let state = Unmanaged<InterruptState>.fromOpaque(refcon).takeUnretainedValue()
    // A disabled tap means we can no longer see real input: stop rather than guess.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        state.interrupted = true
        return Unmanaged.passUnretained(event)
    }
    let source = event.getIntegerValueField(.eventSourceUserData)
    if source != ownMarker && source != leanKeysMarker {
        state.interrupted = true
    }
    return Unmanaged.passUnretained(event)
}

guard let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .listenOnly,
    eventsOfInterest: eventMask,
    callback: tapCallback,
    userInfo: Unmanaged.passUnretained(interrupt).toOpaque()
) else {
    fail(2, "typist: cannot create an event tap. Enable Accessibility for this terminal in \(accessibilityPath).")
}
let tapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), tapSource, .commonModes)

/// Waits `seconds` while pumping the run loop so the tap callback can fire.
func waitPumping(_ seconds: Double) {
    let end = Date().addingTimeInterval(seconds)
    repeat {
        let remaining = end.timeIntervalSinceNow
        CFRunLoopRunInMode(.defaultMode, max(remaining, 0), false)
    } while Date() < end
}

// MARK: - Posting

/// Builds the key-down and key-up events first, so a failure never leaves a half-posted key.
/// `beforePost` runs once per key just before the first event is posted.
func postKey(_ stroke: (keyCode: CGKeyCode, shift: Bool), beforePost: () -> Void) -> Bool {
    let source = CGEventSource(stateID: .hidSystemState)
    var events: [CGEvent] = []
    for keyDown in [true, false] {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: stroke.keyCode, keyDown: keyDown) else {
            return false
        }
        event.flags = stroke.shift ? .maskShift : []
        event.setIntegerValueField(.eventSourceUserData, value: ownMarker)
        events.append(event)
    }
    beforePost()
    for event in events {
        event.post(tap: .cghidEventTap)
    }
    return true
}

let delays = Schedule.delays(count: strokes.count, speed: speed, seed: seed)
var sent: [Int64] = []

for (index, stroke) in strokes.enumerated() {
    if index % 10 == 0, !guardAllows() {
        fail(3, "typist: guard refused before key \(index); the expected window is not frontmost")
    }
    waitPumping(delays[index])
    if interrupt.interrupted {
        fail(4, "typist: interrupted by real input after \(sent.count) keys")
    }
    var timestamp: Int64 = 0
    let posted = postKey(stroke) {
        timestamp = Int64(Date().timeIntervalSince1970 * 1000)
    }
    guard posted else {
        fail(1, "typist: could not create keyboard event for key \(index)")
    }
    sent.append(timestamp)
}

print("{\"sent\":[" + sent.map(String.init).joined(separator: ",") + "]}")
exit(0)
