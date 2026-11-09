#if DEBUG && targetEnvironment(simulator)
import BearDesignSystem
import SwiftUI

/// 对照原生审计与材质渲染；仅合成文字，不装配账户、不出现在 Release。
struct DesignContrastProbe: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("系统文字 System text").foregroundStyle(.primary).padding(12).background(.white)
            Text("纯色样式 Solid style").foregroundStyle(BearTheme.secondaryText(.light))
                .padding(12).background(BearTheme.surface(.light))
            Text("纯色属性 Solid color").foregroundColor(BearTheme.secondaryText(.light))
                .padding(12).background(BearTheme.surface(.light))
            Text("渐变文字 Gradient").foregroundStyle(BearTheme.secondaryText(.light))
                .padding(12).background(BearTheme.paper(.light))
            Text("玻璃样式 Glass style").foregroundStyle(BearTheme.secondaryText(.light))
                .padding(12).bearGlassCard(tint: BearTheme.series(0, .light))
            Text("玻璃属性 Glass color").foregroundColor(BearTheme.secondaryText(.light))
                .padding(12).bearGlassCard(tint: BearTheme.series(0, .light))
            Text("纯黑白 Black white").foregroundColor(.black).padding(12).background(.white)
        }
        .font(.body).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BearTheme.background(.light)).preferredColorScheme(.light)
    }
}
#endif
