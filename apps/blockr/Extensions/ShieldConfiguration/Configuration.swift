import Foundation
import ManagedSettings
import ManagedSettingsUI
import FamilyControls
import UIKit
import BlockrCore
import os

final class Configuration: ShieldConfigurationDataSource {
    private let logger = Logger(subsystem: "com.calumwebb.blockr", category: "shield")

    private func entries(now: Date) -> [ShieldInfo] {
        if let defaults = UserDefaults(suiteName: Storage.appGroup) {
            do {
                if let entries = try ShieldInfo.read(from: defaults),
                   entries.contains(where: { $0.end > now }) { return entries }
                logger.debug("Compact shield metadata missing or expired; trying shared state")
            } catch {
                logger.error("Compact shield metadata decode failed")
            }
        } else {
            logger.error("App Group defaults unavailable")
        }
        do {
            let state = try Storage.read()
            return state.replica.liveLocks(at: now).compactMap { lock in
                guard state.receipts.contains(where: { $0.lockID == lock.id && $0.hasInstalledCoverage }),
                      let selection = state.snapshots[lock.id.uuidString] else { return nil }
                return ShieldInfo(lockID: lock.id, groupName: lock.group.name, end: lock.end,
                                  selection: selection, domains: lock.group.domains)
            }
        } catch {
            // Never log errors' descriptions: they may contain paths or private selections.
            if error is DecodingError {
                logger.error("Shared shield state decode failed")
            } else {
                let code = (error as NSError).code
                logger.error("Shared shield state unavailable; error code \(code)")
            }
            return []
        }
    }

    private func configuration(domain: String? = nil, matches: (FamilyActivitySelection) -> Bool) -> ShieldConfiguration {
        let now = Date()
        let info = ShieldInfo.pick(entries(now: now), now: now) { info in
            if let domain, info.domains.contains(where: { Validation.matches(host: domain.lowercased(), domain: $0) }) { return true }
            do {
                return matches(try JSONDecoder().decode(FamilyActivitySelection.self, from: info.selection))
            } catch {
                logger.error("Shield selection decode failed")
                return false
            }
        }
        if info == nil { logger.debug("No live installed shield metadata") }
        return ShieldConfiguration(backgroundBlurStyle: .systemUltraThinMaterialDark, backgroundColor: .black,
            icon: UIImage(systemName: "lock.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 64))?
                .withTintColor(.white, renderingMode: .alwaysOriginal),
            title: .init(text: info?.title(now: now) ?? "Locked", color: .white),
            subtitle: info.map { .init(text: $0.subtitle(), color: .lightGray) },
            primaryButtonLabel: .init(text: "Close", color: .black), primaryButtonBackgroundColor: .white)
    }

    override func configuration(shielding application: Application) -> ShieldConfiguration { configuration { picks in application.token.map { picks.applicationTokens.contains($0) } ?? false } }
    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration { configuration { picks in
        (application.token.map { picks.applicationTokens.contains($0) } ?? false) || (category.token.map { picks.categoryTokens.contains($0) } ?? false)
    } }
    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration { configuration(domain: webDomain.domain) { picks in webDomain.token.map { picks.webDomainTokens.contains($0) } ?? false } }
    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration { configuration(domain: webDomain.domain) { picks in
        (webDomain.token.map { picks.webDomainTokens.contains($0) } ?? false) || (category.token.map { picks.categoryTokens.contains($0) } ?? false)
    } }
}
