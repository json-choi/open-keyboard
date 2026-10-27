import UIKit

/// Neutral system-like colors. Keys follow the host's light or dark appearance.
enum Palette {
    static let ink = UIColor.label
    static let secondary = UIColor.secondaryLabel
    static let accent = UIColor.systemBlue
    static let onAccent = UIColor.white
    static let softAccent = UIColor.systemBlue.withAlphaComponent(0.18)
    static let key = color(0xFFFFFF, 0x6B6B6E)
    static let specialKey = color(0xADB3BC, 0x464649)
    private static func color(_ light: UInt32, _ dark: UInt32) -> UIColor {
        UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
        }
    }
}
