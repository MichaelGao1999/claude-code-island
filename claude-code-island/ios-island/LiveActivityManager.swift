import Foundation
import ActivityKit
import SwiftUI

// MARK: - Live Activity Attributes

@available(iOS 16.1, *)
public struct ApprovalActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var status: String
        var progress: Double
        var emoji: String
    }

    var taskName: String
}

// MARK: - Live Activity Manager

@MainActor
final class LiveActivityManager: ObservableObject {
    @Published private(set) var isActivityActive: Bool = false
    @Published private(set) var activityId: String?

    private var currentActivity: Activity<ApprovalActivityAttributes>?

    // MARK: - Status Emoji Mapping

    private func emojiForStatus(_ status: String) -> String {
        switch status.lowercased() {
        case "pending", "waiting":
            return "⏳"
        case "approved", "success":
            return "✅"
        case "rejected", "denied", "failed":
            return "❌"
        case "processing", "running", "executing":
            return "🔄"
        case "error", "exception":
            return "⚠️"
        default:
            return "📋"
        }
    }

    // MARK: - Start Activity

    func startActivity(task: String, status: String) {
        guard #available(iOS 16.1, *) else {
            print("[LiveActivityManager] Warning: Live Activity requires iOS 16.1+")
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("[LiveActivityManager] Warning: Live Activities are not enabled")
            return
        }

        let emoji = emojiForStatus(status)
        let attributes = ApprovalActivityAttributes(taskName: task)
        let contentState = ApprovalActivityAttributes.ContentState(
            status: status,
            progress: 0.0,
            emoji: emoji
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: contentState, staleDate: nil),
                pushType: nil
            )
            currentActivity = activity
            activityId = activity.id
            isActivityActive = true
            print("[LiveActivityManager] Started activity: \(activity.id)")
        } catch {
            print("[LiveActivityManager] Error starting activity: \(error.localizedDescription)")
        }
    }

    // MARK: - Update Activity

    func updateActivity(status: String, progress: Double) {
        guard #available(iOS 16.1, *) else {
            print("[LiveActivityManager] Warning: Live Activity requires iOS 16.1+")
            return
        }

        guard let activity = currentActivity else {
            print("[LiveActivityManager] Warning: No active Live Activity to update")
            return
        }

        let emoji = emojiForStatus(status)
        let contentState = ApprovalActivityAttributes.ContentState(
            status: status,
            progress: min(max(progress, 0.0), 1.0),
            emoji: emoji
        )

        Task {
            await activity.update(
                ActivityContent(state: contentState, staleDate: nil)
            )
            print("[LiveActivityManager] Updated activity to status: \(status), progress: \(progress)")
        }
    }

    // MARK: - End Activity

    func endActivity() {
        guard #available(iOS 16.1, *) else {
            print("[LiveActivityManager] Warning: Live Activity requires iOS 16.1+")
            return
        }

        guard let activity = currentActivity else {
            print("[LiveActivityManager] Warning: No active Live Activity to end")
            return
        }

        let finalState = ApprovalActivityAttributes.ContentState(
            status: "Completed",
            progress: 1.0,
            emoji: "✅"
        )

        Task {
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .default
            )
            print("[LiveActivityManager] Ended activity: \(activity.id)")
        }

        currentActivity = nil
        activityId = nil
        isActivityActive = false
    }

    // MARK: - End All Activities

    func endAllActivities() {
        guard #available(iOS 16.1, *) else {
            print("[LiveActivityManager] Warning: Live Activity requires iOS 16.1+")
            return
        }

        Task {
            for activity in Activity<ApprovalActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            print("[LiveActivityManager] Ended all activities")
        }

        currentActivity = nil
        activityId = nil
        isActivityActive = false
    }
}

// MARK: - Fallback for iOS < 16.1

@MainActor
final class LiveActivityManagerFallback: ObservableObject {
    @Published private(set) var isActivityActive: Bool = false

    func startActivity(task: String, status: String) {
        print("[LiveActivityManager] Warning: Live Activity not supported on iOS < 16.1")
        print("[LiveActivityManager] Would start activity for task: \(task), status: \(status)")
    }

    func updateActivity(status: String, progress: Double) {
        print("[LiveActivityManager] Warning: Live Activity not supported on iOS < 16.1")
    }

    func endActivity() {
        print("[LiveActivityManager] Warning: Live Activity not supported on iOS < 16.1")
    }
}
