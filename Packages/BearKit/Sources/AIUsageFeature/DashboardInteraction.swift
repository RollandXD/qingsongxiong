import AIUsageDomain
import Foundation
import Observation

@MainActor @Observable
public final class DashboardInteraction {
    public private(set) var expandedProvider: ProviderID?
    public private(set) var focusedWindows: [ProviderID: String] = [:]
    private var sessions: [ProviderID: UUID] = [:]
    public init() {}
    public func toggle(_ provider: ProviderID) {
        if let previous = expandedProvider, previous != provider { focusedWindows[previous] = nil }
        expandedProvider = expandedProvider == provider ? nil : provider
        if expandedProvider != provider { focusedWindows[provider] = nil }
    }
    public func focus(_ id: String, for provider: ProviderID) { focusedWindows[provider] = id }
    public func reconcile(_ states: [ProviderID: ProviderState]) {
        for provider in ProviderID.allCases {
            let next = states[provider]?.sessionID
            if sessions[provider] != next {
                focusedWindows[provider] = nil
                if expandedProvider == provider { expandedProvider = nil }
            }
            sessions[provider] = next
            if let selected = focusedWindows[provider],
               states[provider]?.snapshot?.windows.contains(where: { $0.id == selected }) != true {
                focusedWindows[provider] = nil
            }
        }
    }
}
