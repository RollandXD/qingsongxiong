import AIUsageDomain
import BearDesignSystem
import Foundation
import SwiftUI

struct APIKeySheet: View {
    @Environment(\.colorScheme) private var scheme
    @Bindable var model: AIUsageModel
    @State private var key = ""
    @State private var request: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    keyField.autocorrectionDisabled()
                        .privacySensitive().accessibilityIdentifier("deepseek-api-key")
                    Text("仅向 DeepSeek 官方余额接口验证，保存于手机钥匙串。").font(.footnote).foregroundStyle(BearTheme.secondaryText(scheme))
                    Link("打开 DeepSeek 密钥管理", destination: URL(string: "https://platform.deepseek.com/api_keys")!)
                }
                Section {
                    Button(model.connecting.contains(.deepseek) ? "正在连接…" : "连接并读取余额") {
                        let submitted = key
                        request = Task { if await model.connect(.deepseek, key: submitted) { key = ""; dismiss() } }
                    }.disabled(key.isEmpty || model.connecting.contains(.deepseek))
                }
                if let message = model.message { Text(message).font(.footnote).foregroundStyle(BearTheme.secondaryText(scheme)) }
            }
            .navigationTitle("连接 DeepSeek")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { request?.cancel(); dismiss() } } }
        }
        .onDisappear { request?.cancel(); key = "" }
    }

    @ViewBuilder private var keyField: some View {
        #if os(iOS)
        SecureField("DeepSeek API Key", text: $key).textInputAutocapitalization(.never)
        #else
        SecureField("DeepSeek API Key", text: $key)
        #endif
    }
}
