import ManagedSettings
import ManagedSettingsUI
import UIKit
import BlockrCore
final class Configuration: ShieldConfigurationDataSource {
    private func configuration(web: Bool = false) -> ShieldConfiguration {
        let locks = (try? Storage.read())?.replica.liveLocks(at: Date()) ?? []
        let lock = locks.last
        let title = lock?.group.name ?? "Locked"
        let subtitle = lock.map { "\(Durations.label(max(60, Int($0.remaining(at: Date()))))) left · until \($0.end.formatted(date: .omitted, time: .shortened))" } ?? "Time unavailable"
        return ShieldConfiguration(backgroundBlurStyle: .systemUltraThinMaterialDark, backgroundColor: .black,
            icon: UIImage(systemName: "lock.fill"), title: .init(text: title, color: .white),
            subtitle: .init(text: subtitle, color: .lightGray), primaryButtonLabel: .init(text: lock == nil ? "OK" : web ? "Close website" : "Close app", color: .black), primaryButtonBackgroundColor: .white)
    }
    override func configuration(shielding application: Application) -> ShieldConfiguration { configuration() }
    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration { configuration() }
    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration { configuration(web: true) }
    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration { configuration(web: true) }
}
