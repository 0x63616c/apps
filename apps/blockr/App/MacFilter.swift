#if os(macOS)
import Foundation
import SwiftUI
import NetworkExtension
import SystemExtensions
import BlockrCore

@MainActor final class MacFilter: NSObject, ObservableObject, OSSystemExtensionRequestDelegate {
    enum Status: Equatable { case unavailable, needsSetup, awaitingApproval, enabled, error(String) }
    @Published var status: Status = .unavailable
    private var request: OSSystemExtensionRequest?
    var configured: Bool { Bundle.main.object(forInfoDictionaryKey: "BlockrFilterEnabled") as? String == "YES" }
    override init() { super.init(); if configured { status = .needsSetup } }
    func setUp() {
        guard configured else { return }
        status = .awaitingApproval
        let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: FilterIdentity.bundleID, queue: .main)
        request.delegate = self
        self.request = request
        OSSystemExtensionManager.shared.submitRequest(request)
    }
    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) { status = .awaitingApproval }
    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) { status = .error(error.localizedDescription) }
    func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties, withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction { .replace }
    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        guard result == .completed else { status = .error("Restart this Mac to finish filter setup."); return }
        Task { await configure() }
    }
    private func configure() async {
        do {
            let manager = NEFilterManager.shared()
            try await manager.loadFromPreferences()
            let configuration = NEFilterProviderConfiguration()
            configuration.filterSockets = true
            configuration.filterBrowsers = true
            configuration.filterDataProviderBundleIdentifier = FilterIdentity.bundleID
            manager.providerConfiguration = configuration
            manager.localizedDescription = "Blockr website protection"
            manager.isEnabled = true
            try await manager.saveToPreferences()
            await refresh()
        } catch { status = .error(error.localizedDescription) }
    }
    func refresh() async {
        guard configured else { status = .unavailable; return }
        do {
            let manager = NEFilterManager.shared()
            try await manager.loadFromPreferences()
            guard manager.isEnabled, manager.providerConfiguration?.filterDataProviderBundleIdentifier == FilterIdentity.bundleID else { status = .needsSetup; return }
            _ = try await acknowledgement()
            status = .enabled
        } catch { status = .error(error.localizedDescription) }
    }
    func confirm(_ id: UUID) async throws {
        guard configured else { throw BlockrError.unavailable("Website protection is unavailable in this build.") }
        let ids = try await acknowledgement()
        guard ids.contains(id.uuidString) else { throw BlockrError.unavailable("The content filter has not acknowledged this lock. Open Settings to retry.") }
    }
    private func acknowledgement() async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            let call = HealthCall(continuation)
            let connection = NSXPCConnection(machServiceName: FilterIdentity.machService)
            call.connection = connection
            connection.remoteObjectInterface = NSXPCInterface(with: FilterHealthProtocol.self)
            connection.invalidationHandler = { call.finish(.failure(BlockrError.unavailable("The content filter stopped. Retry setup."))) }
            connection.resume()
            let proxy = connection.remoteObjectProxyWithErrorHandler { call.finish(.failure($0)) } as? FilterHealthProtocol
            proxy?.health { healthy, ids in
                call.finish(healthy ? .success(ids) : .failure(BlockrError.unavailable("The content filter cannot read Blockr’s policy.")))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { call.finish(.failure(BlockrError.unavailable("The content filter did not respond. Retry setup."))) }
        }
    }
    var label: String {
        switch status {
        case .unavailable: "Unavailable in this build"
        case .needsSetup: "Needs setup"
        case .awaitingApproval: "Needs approval"
        case .enabled: "Enabled"
        case .error: "Error"
        }
    }
}
/// Exactly one continuation completion, including XPC errors and timeouts.
private final class HealthCall: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[String], Error>?
    var connection: NSXPCConnection?
    init(_ continuation: CheckedContinuation<[String], Error>) { self.continuation = continuation }
    func finish(_ result: Result<[String], Error>) {
        lock.lock(); let current = continuation; continuation = nil; lock.unlock()
        guard let current else { return }
        current.resume(with: result)
        connection?.invalidationHandler = nil
        connection?.invalidate()
        connection = nil
    }
}
struct MacFilterSetupView: View {
    @ObservedObject var filter: MacFilter
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Website protection"); Spacer(); Text(filter.label).foregroundStyle(.secondary) }
            if filter.status == .unavailable {
                Text("This build needs signed Mac filter profiles before timed website protection can be enabled.").foregroundStyle(.secondary)
            } else if filter.status != .enabled {
                if case .error(let reason) = filter.status { Text(reason).foregroundStyle(.secondary) }
                Text("Approve Blockr in General → Login Items & Extensions → Network Extensions, then approve website filtering.").foregroundStyle(.secondary)
                Button("Set up website protection") { filter.setUp() }
                Button("Check again") { Task { await filter.refresh() } }
            }
            Text("Mac app blocking is unavailable. The filter covers typed websites where the connection exposes a hostname; encrypted or unknown hosts may not be covered.").foregroundStyle(.secondary)
            Button("Open System Settings") { openSettings() }
        }
    }
}
#endif
