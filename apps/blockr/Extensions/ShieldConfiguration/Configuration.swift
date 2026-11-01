import ManagedSettings
import ManagedSettingsUI
import FamilyControls
import UIKit
import BlockrCore
final class Configuration: ShieldConfigurationDataSource {
    private func configuration(web: Bool = false, matches: (FamilyActivitySelection) -> Bool) -> ShieldConfiguration {
        let state = try? Storage.read()
        let locks = state?.replica.liveLocks(at: Date()) ?? []
        // Concurrent groups can expire independently. Show the session shielding this item,
        // never an unrelated remote lock with a later end time.
        let lock = locks.last { lock in
            guard let snapshot = state?.snapshots[lock.id.uuidString] else { return false }
            return matches(Enforcement.selection(snapshot))
        }
        let title = lock?.group.name ?? "Locked"
        let subtitle = lock.map { "\(Durations.label(max(60, Int($0.remaining(at: Date()))))) left · until \($0.end.formatted(date: .omitted, time: .shortened))" } ?? "Time unavailable"
        return ShieldConfiguration(backgroundBlurStyle: .systemUltraThinMaterialDark, backgroundColor: .black,
            icon: UIImage(systemName: "lock.fill")?.withTintColor(.white, renderingMode: .alwaysOriginal), title: .init(text: title, color: .white),
            subtitle: .init(text: subtitle, color: .lightGray), primaryButtonLabel: .init(text: lock == nil ? "OK" : web ? "Close website" : "Close app", color: .black), primaryButtonBackgroundColor: .white)
    }
    override func configuration(shielding application: Application) -> ShieldConfiguration { configuration { picks in application.token.map { picks.applicationTokens.contains($0) } ?? false } }
    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration { configuration { picks in
        (application.token.map { picks.applicationTokens.contains($0) } ?? false) || (category.token.map { picks.categoryTokens.contains($0) } ?? false)
    } }
    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration { configuration(web: true) { picks in webDomain.token.map { picks.webDomainTokens.contains($0) } ?? false } }
    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration { configuration(web: true) { picks in
        (webDomain.token.map { picks.webDomainTokens.contains($0) } ?? false) || (category.token.map { picks.categoryTokens.contains($0) } ?? false)
    } }
}
