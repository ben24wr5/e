import SwiftUI

/// Colours taken from the "A · Orbit" mockup.
enum Theme {
    static let background = Color(hex: 0x0E0F12)
    static let text = Color(hex: 0xF2EFEA)
    static let secondary = Color(hex: 0xA7A9B0)
    static let tertiary = Color(hex: 0x8D9098)
    static let chip = Color(hex: 0x181A1F)
    static let chipHover = Color(hex: 0x22252C)
    static let chipLine = Color(hex: 0x2E3038)
    static let ringLine = Color(hex: 0x2A2C33)
    static let ringInner = Color(hex: 0x24262C)
    static let card = Color(hex: 0x181A1F)
    static let cardLine = Color(hex: 0x24262C)
    static let accent = Color(hex: 0xF5A524)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension Font {
    static func orbit(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

/// Small uppercase label used on cards ("NEXT", "LONDON").
struct CapsLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.orbit(11, .medium))
            .tracking(1.2)
            .foregroundStyle(Theme.secondary)
            .lineLimit(1)
    }
}
