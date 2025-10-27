import Foundation
import EventKit
import EventKitUI
import UIKit

/// Service for presenting EventKit events and reminders in the native iOS UI
final class EventKitUIService: NSObject, Sendable {
    static let shared = EventKitUIService()

    private let eventKitService = EventKitService()

    private override init() {
        super.init()
    }

    // MARK: - Public Methods

    /// Open an event in the Calendar app's native viewer
    /// - Parameters:
    ///   - eventId: The Apple Calendar event identifier
    ///   - from: The presenting view controller
    @MainActor
    func openEvent(eventId: String, from viewController: UIViewController) async throws {
        // Fetch the event from EventKit
        guard let event = try await eventKitService.findEvent(eventId: eventId) else {
            throw EventKitService.CalendarServiceError.eventNotFound(eventId)
        }

        // Create and present the event view controller
        let eventViewController = EKEventViewController()
        eventViewController.event = event
        eventViewController.allowsEditing = true
        eventViewController.allowsCalendarPreview = true
        eventViewController.delegate = self

        let navigationController = UINavigationController(rootViewController: eventViewController)
        viewController.present(navigationController, animated: true)
    }

    /// Open a reminder by opening the Reminders app
    /// - Parameters:
    ///   - reminderId: The Apple Reminders identifier
    ///   - from: The presenting view controller
    @MainActor
    func openReminder(reminderId: String, from viewController: UIViewController) async throws {
        // Fetch the reminder to verify it exists
        guard let _ = try await eventKitService.findReminder(reminderId: reminderId) else {
            throw EventKitService.CalendarServiceError.reminderNotFound(reminderId)
        }

        // Open the Reminders app
        // Note: iOS doesn't support deep linking to specific reminders via URL scheme
        openRemindersApp()
    }

    /// Open the Calendar app at a specific date
    /// - Parameter date: The date to show in the calendar
    @MainActor
    func openCalendarApp(at date: Date) {
        let interval = date.timeIntervalSinceReferenceDate
        if let url = URL(string: "calshow:\(interval)") {
            UIApplication.shared.open(url)
        }
    }

    /// Open the Reminders app
    @MainActor
    func openRemindersApp() {
        if let url = URL(string: "x-apple-reminderkit://") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - EKEventViewDelegate

extension EventKitUIService: EKEventViewDelegate {
    @MainActor
    @objc func eventViewController(_ controller: EKEventViewController, didCompleteWith action: EKEventViewAction) {
        controller.dismiss(animated: true)
    }
}
