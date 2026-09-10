import Foundation
import CoreGraphics

var failures = 0, passes = 0
func check(_ label: String, _ actual: Any, _ expected: Any) {
    let ok = "\(actual)" == "\(expected)"
    if ok { passes += 1; print("  PASS  \(label)") }
    else { failures += 1; print("  FAIL  \(label)  -> got \(actual), expected \(expected)") }
}

// Hot zone as the overlay registers it: a 460x72 button, padded by 12.
let zone = CGRect(x: 500, y: 400, width: 460, height: 72).insetBy(dx: -12, dy: -12)
let inside = CGPoint(x: 730, y: 436)
let outside = CGPoint(x: 100, y: 100)

func newBridge() -> CleaningTapBridge {
    let b = CleaningTapBridge()
    b.exitHotZones = [zone]
    return b
}
let T: CFAbsoluteTime = 1000

print("\n--- everything that must be blocked ---")
do {
    let b = newBridge()
    for (name, type) in [("keyDown", CGEventType.keyDown), ("keyUp", .keyUp),
                         ("flagsChanged", .flagsChanged), ("scrollWheel", .scrollWheel),
                         ("rightMouseDown", .rightMouseDown), ("otherMouseDown", .otherMouseDown)] {
        check("\(name) inside hot zone is swallowed", b.decide(type: type, location: inside, now: T), CleaningTapBridge.Decision.swallow)
    }
    check("leftMouseDown outside is swallowed", b.decide(type: .leftMouseDown, location: outside, now: T), CleaningTapBridge.Decision.swallow)
    check("  ...and starts no hold", b.holdStartedAt == nil, true)
}

print("\n--- the cursor must still be able to reach the exit ---")
do {
    let b = newBridge()
    check("mouseMoved outside passes", b.decide(type: .mouseMoved, location: outside, now: T), CleaningTapBridge.Decision.pass)
    check("mouseMoved inside passes", b.decide(type: .mouseMoved, location: inside, now: T), CleaningTapBridge.Decision.pass)
    check("moving does not start a hold", b.holdStartedAt == nil, true)
}

print("\n--- the hold-to-exit gesture ---")
do {
    let b = newBridge()
    check("press inside passes", b.decide(type: .leftMouseDown, location: inside, now: T), CleaningTapBridge.Decision.pass)
    check("press inside starts hold", b.holdStartedAt ?? -1, T)
    _ = b.decide(type: .leftMouseDragged, location: inside, now: T + 0.5)
    check("dragging within zone keeps original start", b.holdStartedAt ?? -1, T)
}

// Regression: with "tap to click" on (the laptop default) a tap arrives as
// down+up ~60ms apart. Cancelling on release made the exit gesture impossible.
print("\n--- tap-to-click: a tap must not kill the hold ---")
do {
    let b = newBridge()
    _ = b.decide(type: .leftMouseDown, location: inside, now: T)
    _ = b.decide(type: .leftMouseUp, location: inside, now: T + 0.06)
    check("hold survives a tap's immediate release", b.holdStartedAt ?? -1, T)
    _ = b.decide(type: .mouseMoved, location: inside, now: T + 0.5)
    check("resting the pointer keeps the hold running", b.holdStartedAt ?? -1, T)
}

print("\n--- leaving the button is what cancels ---")
do {
    let b = newBridge()
    _ = b.decide(type: .leftMouseDown, location: inside, now: T)
    _ = b.decide(type: .leftMouseUp, location: inside, now: T + 0.06)
    _ = b.decide(type: .mouseMoved, location: outside, now: T + 0.3)
    check("moving the pointer off the button cancels", b.holdStartedAt == nil, true)

    let b2 = newBridge()
    _ = b2.decide(type: .leftMouseDown, location: inside, now: T)
    _ = b2.decide(type: .leftMouseUp, location: outside, now: T + 0.2)
    check("releasing outside cancels", b2.holdStartedAt == nil, true)
}

print("\n--- accidental wipe must not exit ---")
do {
    let b = newBridge()
    _ = b.decide(type: .leftMouseDown, location: inside, now: T)
    _ = b.decide(type: .leftMouseDragged, location: outside, now: T + 0.2)
    check("dragging off the button cancels the hold", b.holdStartedAt == nil, true)
    check("drag outside is swallowed", b.decide(type: .leftMouseDragged, location: outside, now: T + 0.3), CleaningTapBridge.Decision.swallow)
}

print("\n--- sliding back on resumes ---")
do {
    let b = newBridge()
    _ = b.decide(type: .leftMouseDown, location: inside, now: T)
    _ = b.decide(type: .leftMouseDragged, location: outside, now: T + 0.2)
    _ = b.decide(type: .leftMouseDragged, location: inside, now: T + 0.4)
    check("re-entering restarts the hold clock", b.holdStartedAt ?? -1, T + 0.4)
}

print("\n--- a wipe dragging across the button must not exit ---")
do {
    let b = newBridge()
    for (i, pt) in [outside, inside, outside].enumerated() {
        _ = b.decide(type: .mouseMoved, location: pt, now: T + Double(i) * 0.05)
    }
    check("passing over the button without clicking starts nothing", b.holdStartedAt == nil, true)
}

print("\n--- tap-disable notifications must never be swallowed ---")
do {
    let b = newBridge()
    check("tapDisabledByTimeout passes", b.decide(type: .tapDisabledByTimeout, location: outside, now: T), CleaningTapBridge.Decision.pass)
    check("  ...and is flagged for recovery", b.tapWasDisabled, true)
    let b2 = newBridge()
    check("tapDisabledByUserInput passes", b2.decide(type: .tapDisabledByUserInput, location: outside, now: T), CleaningTapBridge.Decision.pass)
    check("  ...and is flagged for recovery", b2.tapWasDisabled, true)
}

print("\n--- before the overlay reports its button (no hot zones yet) ---")
do {
    let b = CleaningTapBridge()   // exitHotZones empty
    check("press is swallowed with no zone", b.decide(type: .leftMouseDown, location: inside, now: T), CleaningTapBridge.Decision.swallow)
    check("cursor can still move", b.decide(type: .mouseMoved, location: inside, now: T), CleaningTapBridge.Decision.pass)
}

print("\n--- multi-display: a zone per screen ---")
do {
    let b = CleaningTapBridge()
    b.exitHotZones = [zone, CGRect(x: -1400, y: 300, width: 460, height: 72)]
    check("press on second display passes", b.decide(type: .leftMouseDown, location: CGPoint(x: -1200, y: 330), now: T), CleaningTapBridge.Decision.pass)
}

print("\n=== \(passes) passed, \(failures) failed ===")
exit(failures == 0 ? 0 : 1)
