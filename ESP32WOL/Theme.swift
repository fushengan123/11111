//
//  Theme.swift
//  配色、卡片样式、触感反馈
//

import SwiftUI
import UIKit

enum Palette {
    static let bg      = Color(red: 0.043, green: 0.055, blue: 0.078)
    static let card    = Color(red: 0.086, green: 0.106, blue: 0.145)
    static let stroke  = Color.white.opacity(0.07)
    static let accent  = Color(red: 0.22, green: 0.85, blue: 0.96)
    static let text    = Color(red: 0.93, green: 0.95, blue: 0.98)
    static let sub     = Color(red: 0.56, green: 0.61, blue: 0.70)
    static let good    = Color(red: 0.32, green: 0.92, blue: 0.58)
    static let bad     = Color(red: 1.00, green: 0.42, blue: 0.42)
    static let ink     = Color(red: 0.03, green: 0.07, blue: 0.09)
}

enum Haptics {
    static func tap()     { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error()   { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}

private struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Palette.stroke, lineWidth: 1)
            )
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }

    /// 输入框外壳（和 FieldRow 里面那层一致）
    func inputShell() -> some View {
        self
            .font(.system(size: 14, weight: .medium, design: .monospaced))
            .foregroundStyle(Palette.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Palette.bg)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// 设置页的输入框样式
struct FieldRow: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var mono: Bool = true
    var secure: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.sub)
            Group {
                if secure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .keyboardType(keyboard)
            .autocorrectionDisabled(true)
            .textInputAutocapitalization(.never)
            .font(.system(size: 15, weight: .medium, design: mono ? .monospaced : .default))
            .foregroundStyle(Palette.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Palette.bg)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}
