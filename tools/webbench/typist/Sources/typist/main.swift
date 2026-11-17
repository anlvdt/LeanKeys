import AppKit
import ApplicationServices
import Carbon
import CoreGraphics
import Foundation
import TypistCore

// Exit codes: 0 typed (or --check passed), 1 usage or event failure, 2 no Accessibility,
// Input Monitoring (the tap) or US layout, 3 guard refused, 4 interrupted by real input,
// 5 unmappable character, 6 page not ready (timeout or error title; nothing posted).
// --watch <s> exits 0 when no real input arrived in that time, 4 when some did (posts nothing).

let ownMarker = InputSource.ownMarker

func fail(_ code: Int32, _ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

func usage() -> Never {
    fail(1, "usage: typist --keys <string> --speed human|fast|burst --seed <n> --bundle <id> --token <t> [--ready-timeout <s>]\n       typist --check\n       typist --watch <seconds>")
}

func currentLayoutID() -> String {
    guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
          let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "" }
    return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
}

/// Title of the frontmost app's window with the given AX attribute (focused or main).
func windowTitle(_ attribute: String) -> String? {
    guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
    let axApp = AXUIElementCreateApplication(app.processIdentifier)
    var windowRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(axApp, attribute as CFString, &windowRef) == .success,
          let windowRef else { return nil }
    let window = windowRef as! AXUIElement
    var titleRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success else {
        return nil
    }
    return titleRef as? String
}

func frontWindowTitle() -> String? { windowTitle(kAXFocusedWindowAttribute as String) }

/// A listen-only tap for real keyboard and mouse input. Nil when the terminal lacks
/// Accessibility or Input Monitoring.
func makeListenTap(refcon: UnsafeMutableRawPointer?, callback: @escaping CGEventTapCallBack) -> CFMachPort? {
    let mask: CGEventMask =
        (1 << CGEventType.keyDown.rawValue)
        | (1 << CGEventType.mouseMoved.rawValue)
        | (1 << CGEventType.leftMouseDown.rawValue)
    return CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                             options: .listenOnly, eventsOfInterest: mask,
                             callback: callback, userInfo: refcon)
}

// MARK: - --watch <seconds> (posts nothing: exit 4 if real input arrives in the window)

if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--watch" {
    guard let seconds = Double(CommandLine.arguments[2]), seconds >= 0 else { usage() }
    final class WatchState {
        var sawRealInput = false
    }
    let watchState = WatchState()
    guard let watchTap = makeListenTap(refcon: Unmanaged.passUnretained(watchState).toOpaque(),
                                       callback: { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let st = Unmanaged<WatchState>.fromOpaque(refcon).takeUnretainedValue()
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput
            || InputSource.isForeign(marker: event.getIntegerValueField(.eventSourceUserData)) {
            st.sawRealInput = true
        }
        return Unmanaged.passUnretained(event)
    }) else {
        fail(2, Preflight.problem(accessibilityTrusted: AXIsProcessTrusted(), tapCreated: false,
                                  layoutID: Guard.requiredLayoutID) ?? "")
    }
    CFRunLoopAddSource(CFRunLoopGetCurrent(),
                       CFMachPortCreateRunLoopSource(kCFAllocatorDefault, watchTap, 0), .commonModes)
    let watchEnd = Date().addingTimeInterval(seconds)
    repeat {
        CFRunLoopRunInMode(.defaultMode, max(watchEnd.timeIntervalSinceNow, 0), false)
    } while Date() < watchEnd
    if watchState.sawRealInput {
        fail(4, "typist: real keyboard or mouse input during the watch")
    }
    exit(0)
}

// MARK: - --check (preflight: posts nothing, changes nothing)

if CommandLine.arguments.count == 2 && CommandLine.arguments[1] == "--check" {
    let probe = makeListenTap(refcon: nil) { _, _, event, _ in Unmanaged.passUnretained(event) }
    if let probe { CFMachPortInvalidate(probe) }
    if let message = Preflight.problem(accessibilityTrusted: AXIsProcessTrusted(),
                                       tapCreated: probe != nil,
                                       layoutID: currentLayoutID()) {
        fail(2, message)
    }
    print("typist: Accessibility, Input Monitoring and the US layout are ready.")
    exit(0)
}

// MARK: - Arguments

let known: Set<String> = ["--keys", "--speed", "--seed", "--bundle", "--token", "--ready-timeout"]
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

let readyTimeout: Double
if let raw = values["--ready-timeout"] {
    guard let parsed = Double(raw), parsed > 0 else { usage() }
    readyTimeout = parsed
} else {
    readyTimeout = 15
}

// MARK: - Accessibility (checked before any event is created)

guard AXIsProcessTrusted() else {
    fail(2, Preflight.problem(accessibilityTrusted: false, tapCreated: true,
                              layoutID: Guard.requiredLayoutID) ?? "")
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

func guardAllows() -> Bool {
    Guard.mayType(
        frontBundle: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
        windowTitle: frontWindowTitle(),
        alternateTitle: windowTitle(kAXMainWindowAttribute as String),
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

let tapCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let state = Unmanaged<InterruptState>.fromOpaque(refcon).takeUnretainedValue()
    // A disabled tap means we can no longer see real input: stop rather than guess.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        state.interrupted = true
        return Unmanaged.passUnretained(event)
    }
    if InputSource.isForeign(marker: event.getIntegerValueField(.eventSourceUserData)) {
        state.interrupted = true
    }
    return Unmanaged.passUnretained(event)
}

guard let tap = makeListenTap(refcon: Unmanaged.passUnretained(interrupt).toOpaque(),
                              callback: tapCallback) else {
    fail(2, Preflight.problem(accessibilityTrusted: true, tapCreated: false,
                              layoutID: Guard.requiredLayoutID) ?? "")
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

// MARK: - Page ready (same window and bundle contract as the guard)

let readyDeadline = Date().addingTimeInterval(readyTimeout)
var lastTitle = ""
while true {
    if interrupt.interrupted {
        fail(4, "typist: interrupted by real input while waiting for the page")
    }
    if guardAllows() { break }
    let title = frontWindowTitle() ?? ""
    lastTitle = title
    if PageState.of(title: title, token: token) == .error {
        fail(6, "typist: the bench page reported an error (title: \(title))")
    }
    if Date() >= readyDeadline {
        fail(6, "typist: the bench page was not ready within \(Int(readyTimeout)) s; "
             + "front window title: \"\(lastTitle)\". Is \(expectedBundle) frontmost on the bench tab, with the US layout?")
    }
    waitPumping(0.1)
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
