import BackgroundTasks
import Foundation
import Observation
import UIKit

/// A user-requested, single scan session, not a background Photos observer.
/// The store owns scanning and checkpointing; this object owns the OS allowance.
@Observable @MainActor
final class BackgroundScanCoordinator {
    static let shared = BackgroundScanCoordinator()
    // Register a concrete identifier rather than relying on wildcard launch matching.
    // Only one scan can be submitted at a time, so a stable identifier is sufficient.
    static let taskIdentifier = "com.calum.shots.scan.current"

    private(set) var hasRequest = false
    private(set) var isConfigured = false
    private(set) var status = "Scans normally pause when you leave Shots."

    var allowsBackgroundScanning: Bool { task != nil && !isStopping && !hasEnded }

    @ObservationIgnored private var registered = false
    @ObservationIgnored private var registrationAttempted = false
    @ObservationIgnored private var task: BGContinuedProcessingTask?
    @ObservationIgnored private var onStart: (@MainActor () -> Bool)?
    @ObservationIgnored private var onStop: (@MainActor () async -> Void)?
    @ObservationIgnored private var isSubmitting = false
    @ObservationIgnored private var isStopping = false
    @ObservationIgnored private var hasEnded = false
    @ObservationIgnored private var completed = 0
    @ObservationIgnored private var total = 0
    @ObservationIgnored private var phaseTitle = "Scanning screenshots"

    private init() {}

    /// Call from application(_:didFinishLaunchingWithOptions:), once per process.
    func register() {
        guard !registrationAttempted else { return }
        registrationAttempted = true
        registered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier, using: .main
        ) { [weak self] received in
            // The scheduler delivers this handler on the requested main queue.
            MainActor.assumeIsolated {
                guard let self, let continued = received as? BGContinuedProcessingTask else {
                    received.setTaskCompleted(success: false)
                    return
                }
                self.begin(continued)
            }
        }
        if !registered { status = "Background scanning is unavailable. Keep Shots open to scan." }
    }

    /// Start returns false if the library cannot scan. Stop must cancel the scan,
    /// await its exit, and checkpoint, without changing the user's pause preference.
    func install(onStart: @escaping @MainActor () -> Bool,
                 onStop: @escaping @MainActor () async -> Void) {
        self.onStart = onStart
        self.onStop = onStop
        isConfigured = true
    }

    /// Invoke only from an explicit foreground button, never on automatic launch,
    /// a Photos change, or a scene transition. Permission is not persisted.
    func requestContinuation(completed: Int, total: Int) async {
        guard !hasRequest else { return }
        guard registered, isConfigured else {
            status = "Background scanning is unavailable. Keep Shots open to scan."
            return
        }
        guard UIApplication.shared.applicationState == .active else {
            status = "Open Shots and try again to start a background scan."
            return
        }
        guard total > completed else {
            status = "There are no remaining screenshots to scan."
            return
        }
        self.completed = completed
        self.total = total
        hasRequest = true
        hasEnded = false
        isSubmitting = true
        status = "Requesting background time…"
        let request = BGContinuedProcessingTaskRequest(
            identifier: Self.taskIdentifier,
            title: "Scanning screenshots",
            subtitle: progressDescription
        )
        // Reject immediately rather than leave an invisible, deferred request.
        request.strategy = .fail
        // CPU/network only. Background GPU access requires a separate capability;
        // the scan pipeline must use CPU Vision and defer on-device AI while away.
        request.requiredResources = []
        do {
            try await Self.submit(request)
        } catch {
            if !hasEnded && !isStopping {
                let message = "iOS couldn’t start background scanning. Keep Shots open, or try again later."
                if task != nil {
                    // A launch can race the iOS 27 submission completion. Even
                    // an error in that case must stop/checkpoint an active scan.
                    await stop(message: message)
                } else {
                    status = message
                    hasEnded = true
                }
            }
        }
        isSubmitting = false
        // A user may have stopped while an iOS 27 asynchronous submission was
        // still in flight. Cancel again, and block another request until settled.
        if hasEnded || isStopping {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
            if !isStopping { hasRequest = false }
        } else if task == nil {
            status = "Waiting for iOS to start the scan…"
        }
    }

    /// The iOS 27 submission API must not execute on the main thread. The generic
    /// executor also keeps the synchronous iOS 26 submission off the UI thread.
    private nonisolated static func submit(_ request: BGContinuedProcessingTaskRequest) async throws {
        if #available(iOS 27.0, *) {
            try await BGTaskScheduler.shared.submitTaskRequest(request)
        } else {
            try BGTaskScheduler.shared.submit(request)
        }
    }

    private func begin(_ continued: BGContinuedProcessingTask) {
        guard hasRequest, !hasEnded, !isStopping, task == nil, onStart != nil else {
            continued.setTaskCompleted(success: false)
            return
        }
        task = continued
        continued.expirationHandler = { [weak self, weak continued] in
            Task { @MainActor in
                guard let self, let continued, self.task === continued else { return }
                await self.stop(message: "Background scan stopped by iOS or cancelled. Saved progress is kept.")
            }
        }
        updateProgress(completed: completed, total: total, title: phaseTitle)
        status = "Background continuation is active for this scan."
        if onStart?() != true {
            finish(success: false)
        }
    }

    /// Call directly from the scan loop. SwiftUI rendering is not a reliable
    /// source of progress updates after the app has entered the background.
    func updateProgress(completed: Int, total: Int, title: String = "Scanning screenshots") {
        self.total = max(0, total)
        self.completed = min(max(0, completed), self.total)
        phaseTitle = title
        guard let task, !isStopping, !hasEnded else { return }
        task.progress.totalUnitCount = Int64(max(1, self.total))
        task.progress.completedUnitCount = Int64(self.completed)
        task.updateTitle(phaseTitle, subtitle: progressDescription)
    }

    /// Call only after the final checkpoint, or after the store has stopped for a
    /// user pause/error. Do not finish on a foreground refresh/restart handover.
    func finish(success: Bool) {
        guard hasRequest, !isStopping else { return }
        hasEnded = true
        task?.setTaskCompleted(success: success)
        task = nil
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
        status = success ? "Background scan finished. Saved progress is kept."
            : "Background scan paused. Saved progress is kept."
        if !isSubmitting { hasRequest = false }
    }

    /// Used by the Settings stop button; the system Live Activity cancellation
    /// follows the same path through expirationHandler.
    func stop() async {
        await stop(message: "Background scan stopped. Saved progress is kept.")
    }

    private func stop(message: String) async {
        guard hasRequest, !isStopping, !hasEnded else { return }
        isStopping = true // Revoke allowance before awaiting scanner cancellation.
        status = "Stopping and saving progress…"
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
        await onStop?()
        task?.setTaskCompleted(success: false)
        task = nil
        hasEnded = true
        isStopping = false
        status = message
        if !isSubmitting { hasRequest = false }
    }

    private var progressDescription: String {
        "\(completed.formatted()) of \(total.formatted()) screenshots"
    }
}
