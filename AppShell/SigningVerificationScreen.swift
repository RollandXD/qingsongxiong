import BearDesignSystem
import BearPlatform
import SwiftUI
import WidgetKit

struct SigningVerificationScreen: View {
    @State private var report = SigningProbe.configured().inspect()
    @State private var message: String?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    BearMark().frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("先把地基验证好").font(.headline)
                        Text("这里只使用无敏感信息的测试标记。")
                            .font(.footnote).foregroundStyle(BearTheme.secondaryText(scheme))
                    }
                }.padding(.vertical, 8)
            }
            Section("本机检查") {
                BearStatusRow("共享容器", passed: report.sharedContainerAvailable)
                BearStatusRow("共享快照", passed: report.record != nil && !report.storageFailed)
                BearStatusRow("共享钥匙串", passed: report.sharedKeychainReadable)
                if let record = report.record {
                    LabeledContent("验证编号", value: "\(record.revision)")
                        .accessibilityIdentifier("probe-revision")
                    LabeledContent("写入时间", value: record.updatedAt.formatted(date: .abbreviated, time: .shortened))
                }
                if let status = report.keychainStatus {
                    LabeledContent("钥匙串状态码", value: "\(status)")
                }
            }
            Section {
                Button("写入验证数据") {
                    do {
                        try SigningProbe.configured().write()
                        message = "已写入。请在桌面添加轻松熊组件，核对验证编号和钥匙串状态。"
                        WidgetCenter.shared.reloadAllTimelines()
                    } catch {
                        message = "写入未完成。请保留下面的状态，先检查重签时的共享权限。"
                    }
                    refresh()
                }.accessibilityIdentifier("write-probe")
                Button("重新检查") { refresh() }
                if let message { Text(message).font(.footnote).foregroundStyle(BearTheme.secondaryText(scheme)) }
            }
            Section("实机验收") {
                Text("App 中显示通过，还不等于组件已经通过。请核对组件里的相同验证编号和“钥匙串可读”，然后完成一次续签，再确认数据保留。")
                #if targetEnvironment(simulator)
                Text("当前是模拟器：共享 Keychain 的权限行为不能代替真机验收。")
                    .foregroundStyle(BearTheme.warning(scheme))
                #endif
            }.font(.footnote)
        }
        .scrollContentBackground(.hidden)
        .background(BearTheme.background(scheme))
        .navigationTitle("安装验证")
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
    }

    private func refresh() { report = SigningProbe.configured().inspect() }
}
