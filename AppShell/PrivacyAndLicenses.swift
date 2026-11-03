import Foundation
import BearDesignSystem
import SwiftUI
import WidgetKit

private struct LegalResource {
    static func read(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "许可资源暂不可读取，请查看项目源码中的原文。" }
        return text
    }
}

struct PrivacyScreen: View {
    let entries: [AppFeatureEntry]
    @State private var confirm = false
    @State private var clearing = false
    @State private var result: String?
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Form {
            Section("数据如何使用") {
                Text("手机直接连接对应平台读取额度与余额，不经过轻松熊的服务器。")
                Text("凭据保存在本机钥匙串，App 与小组件共享读数及状态。小组件不进行交互式登录或令牌续期。")
                Text("没有广告、分析 SDK 或账户后台。系统浏览器登录由平台处理，Safari 的登录状态由系统管理。")
            }
            Section("清除功能数据") {
                Text("将退出所有已连接平台，取消进行中的请求，并清除凭据与额度缓存。不会删除平台账户或更改 SideStore 签名。")
                Button("退出全部账户并清除数据", role: .destructive) { confirm = true }
                    .disabled(clearing).accessibilityIdentifier("clear-feature-data")
                if clearing { ProgressView("正在清除…") }
                if let result { Text(result).accessibilityIdentifier("clear-data-result") }
            }
        }
        .scrollContentBackground(.hidden)
        .background(BearTheme.background(scheme))
        .navigationTitle("隐私与清除数据")
        .confirmationDialog("清除后需要重新连接账户。", isPresented: $confirm, titleVisibility: .visible) {
            Button("清除功能数据", role: .destructive) {
                clearing = true
                Task { @MainActor in
                    var success = true
                    for entry in entries { if !(await entry.clearLocalData()) { success = false } }
                    WidgetCenter.shared.reloadAllTimelines()
                    result = success ? "功能凭据与额度缓存已清除。" : "部分数据未能清除，请保持手机解锁后重试。"
                    clearing = false
                }
            }
        }
    }
}

struct OpenSourceScreen: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        List {
            Section("轻松熊") {
                Text("Apache License 2.0")
                NavigationLink("阅读完整许可") { LegalTextScreen(title: "Apache 2.0", name: "LICENSE") }
                NavigationLink("项目来源说明") { LegalTextScreen(title: "来源说明", name: "NOTICE") }
            }
            Section("参考项目") {
                Link("AI Usage Limits", destination: URL(string: "https://github.com/stavrop/ai-usage-limits")!)
                NavigationLink("原始 NOTICE") { LegalTextScreen(title: "Upstream NOTICE", name: "UPSTREAM-NOTICE") }
                Text("保留原文与来源；平台标识属于相应权利人。")
            }
        }
        .scrollContentBackground(.hidden)
        .background(BearTheme.background(scheme))
        .navigationTitle("开源许可与来源")
    }
}

private struct LegalTextScreen: View {
    let title: String
    let name: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ScrollView { Text(LegalResource.read(name)).font(.footnote).textSelection(.enabled).padding().frame(maxWidth: .infinity, alignment: .leading) }
            .background(BearTheme.background(scheme))
            .navigationTitle(title)
    }
}
