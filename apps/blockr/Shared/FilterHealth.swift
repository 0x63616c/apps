#if os(macOS)
import Foundation
/// Only app-owned policy IDs cross XPC; no URLs, network content or traffic metadata.
@objc protocol FilterHealthProtocol {
    func health(_ reply: @escaping (Bool, [String]) -> Void)
}
enum FilterIdentity {
    static let bundleID = "com.calumwebb.blockr.ContentFilter"
    static let machService = "group.com.calumwebb.blockr.filter"
}
#endif
