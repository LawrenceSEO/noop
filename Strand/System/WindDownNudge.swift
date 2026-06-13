import Foundation
import UserNotifications

/// The wind-down nudge (#207) — a gentle, NON-critical evening local notification suggesting it's
/// time to start winding down so the user can reach their usual wake time well-rested.
///
/// Cross-platform (macOS + iOS): a sideloaded backgrounded app can't fire a dependable LOUD wake
/// alarm (no critical-alert entitlement), but it CAN post a calm daily reminder. The nudge fires on a
/// repeating calendar trigger at a time DERIVED from the user's earliest wake time minus their usual
/// sleep need minus a short lead. State is its own UserDefaults-backed store so it doesn't couple to
/// the shared BehaviorStore. On-device only; nothing is sent anywhere.
@MainActor
enum WindDownNudge {

    private static let requestId = "wind-down-nudge"

    // MARK: - Persisted settings (own keys; default OFF, opt-in like every automation)

    private enum K {
        static let enabled = "windDown.enabled"
        static let sleepNeed = "windDown.sleepNeedMinutes"   // default 8h
        static let lead = "windDown.leadMinutes"             // default 30m
        static let wake = "windDown.wakeMinutes"             // earliest wake, minutes since midnight
    }

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: K.enabled) }

    static var sleepNeedMinutes: Int {
        let v = UserDefaults.standard.object(forKey: K.sleepNeed) as? Int ?? 8 * 60
        return min(max(v, 5 * 60), 11 * 60)
    }

    static var leadMinutes: Int {
        let v = UserDefaults.standard.object(forKey: K.lead) as? Int ?? 30
        return min(max(v, 0), 120)
    }

    static var wakeMinutes: Int {
        let v = UserDefaults.standard.object(forKey: K.wake) as? Int ?? 7 * 60   // 07:00
        return min(max(v, 0), 24 * 60 - 1)
    }

    // MARK: - Public API

    /// Ask up front (when the user enables the nudge) so the system dialog appears at a predictable
    /// moment rather than silently failing the first night.
    static func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Enable/disable and (re)schedule. Enabling requests authorization and schedules the repeating
    /// nudge; disabling removes it.
    static func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: K.enabled)
        if on {
            requestAuthorization()
            schedule()
        } else {
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: [requestId])
        }
    }

    /// Update the earliest wake time the nudge is derived from, rescheduling if enabled.
    static func setWakeMinutes(_ minutes: Int) {
        UserDefaults.standard.set(min(max(minutes, 0), 24 * 60 - 1), forKey: K.wake)
        if isEnabled { schedule() }
    }

    /// The minute-of-day the nudge fires: wake − sleepNeed − lead, wrapped into [0, 1440).
    static func nudgeMinuteOfDay() -> Int {
        let raw = wakeMinutes - sleepNeedMinutes - leadMinutes
        let day = 24 * 60
        return ((raw % day) + day) % day
    }

    // MARK: - Scheduling

    private static func schedule() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [requestId])

        let content = UNMutableNotificationContent()
        content.title = "Time to wind down"
        content.body = "A calm hour now helps you hit your wake time well-rested."
        content.sound = .default

        let minute = nudgeMinuteOfDay()
        var comps = DateComponents()
        comps.hour = minute / 60
        comps.minute = minute % 60
        // repeats: true → a daily calendar trigger; survives relaunch (it lives in the notification
        // center, not the process), so the nudge keeps firing each evening without the app running.
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        center.add(UNNotificationRequest(identifier: requestId, content: content, trigger: trigger))
    }
}
