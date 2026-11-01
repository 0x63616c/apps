import ManagedSettings
import Foundation
final class Action: ShieldActionDelegate {
    private func close(_ completion: @escaping (ShieldActionResponse) -> Void) {
        try? Storage.update { state in
            state.attempts.append(Attempt(lockIDs: state.replica.liveLocks(at: Date()).map(\.id)))
        }
        completion(.close)
    }
    override func handle(action: ShieldAction, for application: ApplicationToken, completionHandler: @escaping (ShieldActionResponse) -> Void) { close(completionHandler) }
    override func handle(action: ShieldAction, for webDomain: WebDomainToken, completionHandler: @escaping (ShieldActionResponse) -> Void) { close(completionHandler) }
    override func handle(action: ShieldAction, for category: ActivityCategoryToken, completionHandler: @escaping (ShieldActionResponse) -> Void) { close(completionHandler) }
}
