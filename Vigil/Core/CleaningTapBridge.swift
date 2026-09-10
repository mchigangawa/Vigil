import CoreGraphics
import Foundation

/// Thread-confined state shared with the `CGEventTap` C callback.
///
/// The tap callback must decide synchronously whether to swallow an event, so
/// it cannot hop actors. The run loop source is attached to the **main** run
/// loop, so in practice every access below happens on the main thread; this
/// type exists to give the C callback something plain to talk to without
/// dragging main-actor isolation into the hot path.
final class CleaningTapBridge: @unchecked Sendable {

    /// Regions (in Quartz global display coordinates, origin top-left) where a
    /// press is allowed through to the overlay's exit button.
    var exitHotZones: [CGRect] = []

    /// Set to the press start time while the pointer is held inside a hot zone.
    /// A main-thread timer reads this to drive the hold-to-exit progress.
    var holdStartedAt: CFAbsoluteTime?

    /// Raised when the system disables the tap (timeout or user input). The
    /// manager re-enables it and, if that keeps happening, bails out.
    var tapWasDisabled = false

    /// Number of events swallowed — surfaced in the overlay purely as feedback
    /// that blocking is really happening.
    var blockedEventCount: Int = 0

    func hotZoneContains(_ point: CGPoint) -> Bool {
        exitHotZones.contains { $0.contains(point) }
    }

    /// What the tap should do with one event.
    enum Decision: Equatable {
        /// Hand it on untouched.
        case pass
        /// Discard it; nothing else in the system sees it.
        case swallow
    }

    /// The whole of Cleaning Mode's input policy, as one pure-ish function.
    ///
    /// Split out of the `CGEventTap` callback deliberately: the callback cannot
    /// run at all without Accessibility permission and a live tap, which makes
    /// the rules that decide whether a user can escape Cleaning Mode the least
    /// testable code in the app. Here they can be exercised directly.
    ///
    /// Mutates hold state as a side effect, and is called on the main thread
    /// only (see the type comment).
    func decide(type: CGEventType, location: CGPoint, now: CFAbsoluteTime) -> Decision {
        // The system disables a tap that is too slow, or when the user forces
        // input through. Flag it for recovery; never swallow these.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            tapWasDisabled = true
            return .pass
        }

        let inHotZone = hotZoneContains(location)

        // Leaving the button is the ONLY thing that cancels a hold.
        //
        // Releasing deliberately does not. With "tap to click" enabled — the
        // default on every Mac laptop — a tap is reported as a mouse-down
        // immediately followed by a mouse-up about 60ms later, so cancelling on
        // release made the exit gesture impossible for anyone who taps rather
        // than physically depressing the trackpad. The gesture is therefore
        // "click here, then keep the pointer still": it needs a press inside
        // the button AND the pointer to stay inside it for the full duration.
        // A wiping hand drags the cursor out almost immediately, which is what
        // keeps the gesture hard to trigger by accident.
        if !inHotZone {
            switch type {
            case .mouseMoved, .leftMouseDragged, .leftMouseUp, .leftMouseDown:
                holdStartedAt = nil
            default:
                break
            }
        }

        switch type {
        case .mouseMoved:
            // Cursor motion is allowed through, and only cursor motion. Without
            // it the pointer would freeze and the exit button would be
            // unreachable — a blocked pointer with no route to the exit is
            // exactly the lockout this feature must never create. Movement on
            // its own starts no hold.
            return .pass

        case .leftMouseDown, .leftMouseDragged:
            if inHotZone {
                if holdStartedAt == nil { holdStartedAt = now }
                return .pass
            }

        case .leftMouseUp:
            // Inside the button, a release leaves the hold running — see above.
            if inHotZone { return .pass }

        default:
            break
        }

        blockedEventCount &+= 1
        return .swallow
    }

    func reset() {
        holdStartedAt = nil
        tapWasDisabled = false
        blockedEventCount = 0
    }
}
