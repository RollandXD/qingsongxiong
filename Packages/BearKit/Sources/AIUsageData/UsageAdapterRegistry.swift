import AIUsageDomain
import BearFoundation
import BearPlatform

public enum UsageAdapterRegistry {
    public static func make(client: any HTTPClient, clock: any BearClock = SystemBearClock()) -> [ProviderID: any UsageFetching] {
        [.deepseek: DeepSeekAdapter(client: client, clock: clock),
         .codex: SubscriptionUsageAdapter(provider: .codex, client: client, clock: clock),
         .claude: SubscriptionUsageAdapter(provider: .claude, client: client, clock: clock)]
    }
}
