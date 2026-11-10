import AIUsageDomain
import AIUsagePresentation
import BearDesignSystem
import Foundation
import SwiftUI

extension DashboardOverviewPresentation.Mood {
    var bear: BearMood {
        switch self { case .calm: .calm; case .watchful: .watchful; case .urgent: .urgent; case .asleep: .asleep }
    }
}
