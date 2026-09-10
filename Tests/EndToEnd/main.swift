import AppKit
import CoreGraphics

// End-to-end: real CleaningModeManager, real CGEventTap, real overlay.
// Posts a synthetic press on the real exit hot zone and reports whether the
// hold registers. Input is blocked for ~3s; a hard teardown runs regardless.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

MainActor.assumeIsolated {
    let keepAwake = KeepAwakeManager()
    let permission = AccessibilityPermission()
    let manager = CleaningModeManager(keepAwake: keepAwake, permission: permission)

    manager.onActivationFailed = { print("ACTIVATION FAILED: \($0)") ; NSApp.terminate(nil) }
    manager.onDeactivated = { cause in print("  deactivated, cause = \(cause)") }

    print("AXIsProcessTrusted = \(AXIsProcessTrusted())")
    manager.activate()
    print("isActive after activate() = \(manager.isActive)")

    // Safety net independent of everything under test.
    DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
        MainActor.assumeIsolated {
            manager.emergencyTeardown(); keepAwake.releaseEverything()
            print("!! hard teardown fired"); NSApp.terminate(nil)
        }
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
        MainActor.assumeIsolated {
            guard let zone = manager.debugHotZones.first else {
                print("NO HOT ZONES REGISTERED"); return
            }
            let center = CGPoint(x: zone.midX, y: zone.midY)
            print("posting press at \(center) inside zone \(zone)")

            CGWarpMouseCursorPosition(center)
            let src = CGEventSource(stateID: .combinedSessionState)
            CGEvent(mouseEventSource: src, mouseType: .mouseMoved,
                    mouseCursorPosition: center, mouseButton: .left)?.post(tap: .cghidEventTap)
            CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                    mouseCursorPosition: center, mouseButton: .left)?.post(tap: .cghidEventTap)
            // TAP-TO-CLICK: the release arrives ~60ms later, unprompted.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                        mouseCursorPosition: center, mouseButton: .left)?.post(tap: .cghidEventTap)
                print("  (tap released after 60ms - pointer left resting on button)")
            }
        }
    }

    for t in [1.3, 2.0, 3.2] {
        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            MainActor.assumeIsolated {
                print(String(format: "  t+%.1fs  holdStarted=%@  holdProgress=%.2f  active=%@  blocked=%d",
                             t,
                             manager.debugHoldStarted ? "YES" : "no",
                             manager.holdProgress,
                             manager.isActive ? "YES" : "no",
                             manager.blockedEventCount))
            }
        }
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 3.6) {
        MainActor.assumeIsolated {
            let src = CGEventSource(stateID: .combinedSessionState)
            CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                    mouseCursorPosition: CGPoint(x: 200, y: 200), mouseButton: .left)?.post(tap: .cghidEventTap)
            manager.emergencyTeardown(); keepAwake.releaseEverything()
            print("done"); NSApp.terminate(nil)
        }
    }
}
app.run()
