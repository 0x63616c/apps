import Foundation
import NetworkExtension
import BlockrCore

final class Provider: NEFilterDataProvider, NSXPCListenerDelegate, FilterHealthProtocol {
    private let policyLock = NSLock()
    private var replica = Replica()
    private var running = false
    private var readable = false
    private var timer: DispatchSourceTimer?
    private var listener: NSXPCListener?

    override func startFilter(completionHandler: @escaping (Error?) -> Void) {
        refreshPolicy()
        let listener = NSXPCListener(machServiceName: FilterIdentity.machService)
        listener.delegate = self
        self.listener = listener
        listener.resume()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "blockr.policy"))
        timer.schedule(deadline: .now(), repeating: 1)
        timer.setEventHandler { [weak self] in self?.refreshPolicy() }
        self.timer = timer
        timer.resume()
        policyLock.lock(); running = true; policyLock.unlock()
        completionHandler(nil)
    }
    override func stopFilter(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        policyLock.lock(); running = false; policyLock.unlock()
        timer?.cancel(); timer = nil
        listener?.invalidate(); listener = nil
        completionHandler()
    }
    private func refreshPolicy() {
        do {
            let snapshot = try Storage.read().replica
            policyLock.lock(); replica = snapshot; readable = true; policyLock.unlock()
        } catch {
            // Retain the last policy with its original absolute expiry; never invent a new end.
            policyLock.lock(); readable = false; policyLock.unlock()
        }
    }
    func health(_ reply: @escaping (Bool, [String]) -> Void) {
        refreshPolicy()
        policyLock.lock()
        let healthy = running && readable
        let ids = replica.liveLocks(at: Date()).filter { !$0.group.domains.isEmpty }.map { $0.id.uuidString }
        policyLock.unlock()
        reply(healthy, ids)
    }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // The sandbox and app-group Mach-service namespace restrict access to the signed group.
        connection.exportedInterface = NSXPCInterface(with: FilterHealthProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }
    private func denied(_ flow: NEFilterFlow) -> Bool {
        let host = (flow.url?.host ?? (flow as? NEFilterSocketFlow)?.remoteHostname)?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard let host else { return false }
        policyLock.lock(); let locks = replica.liveLocks(at: Date()); policyLock.unlock()
        return locks.contains { lock in lock.group.domains.contains { Validation.matches(host: host, domain: $0) } }
    }
    override func handleNewFlow(_ flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        if denied(flow) { return .drop() }
        // Keep known flows observable: locks must also affect connections established before Start.
        return .filterDataVerdict(withFilterInbound: true, peekInboundBytes: 4096, filterOutbound: true, peekOutboundBytes: 4096)
    }
    override func handleInboundData(from flow: NEFilterFlow, readBytesStartOffset offset: Int, readBytes: Data) -> NEFilterDataVerdict {
        denied(flow) ? .drop() : NEFilterDataVerdict(passBytes: readBytes.count, peekBytes: 4096)
    }
    override func handleOutboundData(from flow: NEFilterFlow, readBytesStartOffset offset: Int, readBytes: Data) -> NEFilterDataVerdict {
        denied(flow) ? .drop() : NEFilterDataVerdict(passBytes: readBytes.count, peekBytes: 4096)
    }
}
