import AppKit
import CoreGraphics
import Combine
import os

/// Blocks keyboard and pointer input system-wide so the machine can be wiped
/// down, and guarantees a way back out.
///
/// Safety model — three independent exits, any one of which is sufficient:
///   1. A hard auto-exit timer that always fires, even if nothing else works.
///   2. A deliberate hold on the on-screen exit button (the one gesture the
///      event tap lets through).
///   3. Automatic teardown if the tap dies or Accessibility is revoked.
@MainActor
final class CleaningModeManager: ObservableObject {

    private static let log = Logger(subsystem: "zw.co.munyaradzichigangawa.Vigil", category: "CleaningMode")

    @Published private(set) var isActive = false
    /// Seconds left before the automatic exit.
    @Published private(set) var remaining: TimeInterval = 0
    /// 0...1 progress of the hold-to-exit gesture.
    @Published private(set) var holdProgress: Double = 0
    @Published private(set) var blockedEventCount: Int = 0

    enum ExitCause {
        case userGesture
        case timerExpired
        case permissionRevoked
        case tapFailed
        case programmatic
    }

    /// Called after teardown completes.
    var onDeactivated: ((ExitCause) -> Void)?
    /// Called when activation cannot proceed.
    var onActivationFailed: ((String) -> Void)?

    private let keepAwake: KeepAwakeManager
    private let permission: AccessibilityPermission
    private let overlay = CleaningOverlayController()
    private let bridge = CleaningTapBridge()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var deadline: Date?
    private var tick: Timer?
    private var tapDisableRecoveries = 0

    init(keepAwake: KeepAwakeManager, permission: AccessibilityPermission) {
        self.keepAwake = keepAwake
        self.permission = permission
    }

    // MARK: - Activation

    func activate() {
        guard !isActive else { return }

        guard permission.refresh() else {
            Self.log.error("Cleaning Mode blocked: no Accessibility permission")
            onActivationFailed?("Vigil needs Accessibility permission to block input.")
            return
        }

        bridge.reset()
        tapDisableRecoveries = 0

        guard installEventTap() else {
            onActivationFailed?("Vigil couldn't install the input tap. Try toggling its Accessibility permission off and on.")
            return
        }

        // Cleaning Mode always keeps the display lit, independent of whatever
        // the user's own Keep Awake toggle is set to.
        keepAwake.acquire(.cleaningMode, keepDisplayOn: true)
        permission.setHeightenedWatch(true)

        let duration = Preferences.shared.cleaningAutoExitSeconds
        deadline = Date().addingTimeInterval(duration)
        remaining = duration
        holdProgress = 0
        isActive = true

        overlay.show(bridge: bridge)
        startTicking()

        Self.log.info("Cleaning Mode active for \(duration, privacy: .public)s")
    }

    func deactivate(cause: ExitCause = .programmatic) {
        guard isActive else { return }
        isActive = false

        tick?.invalidate()
        tick = nil
        deadline = nil
        holdProgress = 0

        removeEventTap()
        overlay.hide()
        keepAwake.release(.cleaningMode)
        permission.setHeightenedWatch(false)
        bridge.reset()

        Self.log.info("Cleaning Mode ended (\(String(describing: cause), privacy: .public))")
        onDeactivated?(cause)
    }

    func toggle() {
        isActive ? deactivate(cause: .userGesture) : activate()
    }

    // MARK: - Event tap

    private func installEventTap() -> Bool {
        let mask = Self.eventMask
        let pointer = Unmanaged.passUnretained(bridge).toOpaque()

        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: cleaningTapCallback,
                                          userInfo: pointer)
        else {
            Self.log.error("CGEvent.tapCreate returned nil")
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            Self.log.error("CFMachPortCreateRunLoopSource returned nil")
            return false
        }

        // Attached to the main run loop, which is what keeps the C callback on
        // the main thread — see CleaningTapBridge.
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        // The tap is owned here, strongly, for exactly as long as Cleaning
        // Mode is active. It is deliberately NOT handed to the bridge: a
        // CFMachPort bridges to NSMachPort, which does not support weak
        // references, so storing it weakly traps with "Cannot form weak
        // reference to instance of class NSMachPort".
        eventTap = tap
        runLoopSource = source
        return true
    }

    private func removeEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    /// Everything Cleaning Mode swallows.
    ///
    /// Deliberately excluded: raw values 29 and 30. Those are `NSEvent`'s
    /// gesture/magnify types, but Quartz reuses the same two numbers for
    /// `tapDisabledByTimeout` / `tapDisabledByUserInput`, so subscribing to them
    /// would make a real tap-disable indistinguishable from a pinch. Pinch and
    /// magnify therefore still reach the system; they cannot activate anything
    /// on their own, and every click and keystroke around them is blocked.
    private static let eventMask: CGEventMask = {
        let cgTypes: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged,
            .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged,
            .mouseMoved, .scrollWheel,
            .tabletPointer, .tabletProximity,
        ]
        var mask: CGEventMask = cgTypes.reduce(0) { $0 | (1 << UInt64($1.rawValue)) }

        // NSEvent types with no CGEventType collision: rotate (18),
        // beginGesture (19), endGesture (20), smartMagnify (32), pressure (34).
        for raw: UInt64 in [18, 19, 20, 32, 34] {
            mask |= (1 << raw)
        }
        return mask
    }()

    // MARK: - Ticking, hold-to-exit, and the safety net

    private func startTicking() {
        tick?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.onTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tick = timer
    }

    private func onTick() {
        guard isActive else { return }

        blockedEventCount = bridge.blockedEventCount

        // 1. Hard deadline — the exit that always works.
        if let deadline {
            remaining = max(0, deadline.timeIntervalSinceNow)
            if remaining <= 0 {
                deactivate(cause: .timerExpired)
                return
            }
        }

        // 2. Accessibility revoked mid-session.
        if !permission.isTrusted {
            deactivate(cause: .permissionRevoked)
            return
        }

        // 3. The tap was disabled by the system — try once to bring it back,
        //    then give up rather than pretend input is still blocked.
        if bridge.tapWasDisabled {
            bridge.tapWasDisabled = false
            tapDisableRecoveries += 1
            if tapDisableRecoveries > 3 {
                Self.log.error("Event tap kept being disabled; exiting Cleaning Mode")
                deactivate(cause: .tapFailed)
                return
            }
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                Self.log.notice("Re-enabled event tap (attempt \(self.tapDisableRecoveries, privacy: .public))")
            }
        }

        // 4. Hold-to-exit progress.
        let holdTarget = Preferences.shared.cleaningExitHoldSeconds
        if let started = bridge.holdStartedAt {
            let elapsed = CFAbsoluteTimeGetCurrent() - started
            holdProgress = min(1, elapsed / holdTarget)
            if holdProgress >= 1 {
                deactivate(cause: .userGesture)
                return
            }
        } else if holdProgress != 0 {
            holdProgress = 0
        }

        overlay.update(remaining: remaining, holdProgress: holdProgress, blocked: blockedEventCount)
    }

    #if DEBUG
    /// Read-only views of tap state, for the end-to-end harness in Tests/.
    var debugHotZones: [CGRect] { bridge.exitHotZones }
    var debugHoldStarted: Bool { bridge.holdStartedAt != nil }
    #endif

    /// Unconditional teardown for quit / sleep paths.
    func emergencyTeardown() {
        tick?.invalidate()
        tick = nil
        removeEventTap()
        overlay.hide()
        isActive = false
    }
}

/// The `CGEventTap` callback.
///
/// Runs on the main thread (its run loop source is on the main run loop) and
/// must return synchronously: the returned event is what the rest of the system
/// sees, and `nil` means the event is discarded.
private func cleaningTapCallback(proxy: CGEventTapProxy,
                                 type: CGEventType,
                                 event: CGEvent,
                                 userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let bridge = Unmanaged<CleaningTapBridge>.fromOpaque(userInfo).takeUnretainedValue()

    // All policy lives in CleaningTapBridge.decide so it can be tested without
    // a live tap; this callback only translates the answer for Quartz.
    switch bridge.decide(type: type,
                         location: event.location,
                         now: CFAbsoluteTimeGetCurrent()) {
    case .pass:
        return Unmanaged.passUnretained(event)
    case .swallow:
        return nil
    }
}
