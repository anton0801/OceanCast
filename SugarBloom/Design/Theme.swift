//
//  Theme.swift
//  Ocean Cast
//
//  Colour, type and motion tokens for the sea-fishing visual direction.
//

import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

enum Ocean {
    /// Clean ocean blue — the primary colour of the app.
    static let blue      = Color(hex: 0x159DE4)
    /// Bright turquoise — shallow water, used for confirmations and stock.
    static let turquoise = Color(hex: 0x22D3C5)
    /// Deep sea blue — every piece of text, and the darkest accents.
    static let deep      = Color(hex: 0x073B66)
    /// Sky — light reflections, soft fills.
    static let sky       = Color(hex: 0x8EDBFF)
    /// White foam — the background of every screen.
    static let foam      = Color(hex: 0xF4FCFF)
    /// Warm coral-orange — the one warm accent, kept for attention.
    static let coral     = Color(hex: 0xFF8A3D)
    /// Mid-water blue, between sky and ocean; used to vary long lists.
    static let lagoon    = Color(hex: 0x4FBBEE)
    /// Deeper water than `blue`, still saturated enough to tint a panel.
    /// `deep` itself is reserved for text — as a 10% fill it only reads grey.
    static let tide      = Color(hex: 0x1E6FA8)

    static let ink       = deep
    static let inkSoft   = Color(hex: 0x40708F)
    static let inkFaint  = Color(hex: 0x8AAFC6)
    static let surface   = Color.white
    static let hairline  = Color(hex: 0x073B66, alpha: 0.10)

    /// Rotating accent used to keep long lists visually varied but deterministic.
    static let wheel: [Color] = [blue, turquoise, coral, lagoon, deep]

    static func accent(for key: String) -> Color {
        guard !key.isEmpty else { return blue }
        var hash: UInt64 = 5381
        for byte in key.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return wheel[Int(hash % UInt64(wheel.count))]
    }

    /// A tint darkened enough to be read as small text on a white panel.
    /// Light sea colours are for fills; text needs to be pulled towards the deep.
    static func readable(_ tint: Color) -> Color {
        if #available(iOS 18.0, *) {
            tint.mix(with: deep, by: 0.45)
        } else {
            deep
        }
    }
}

enum OceanFont {
    static func display(_ size: CGFloat = 30) -> Font { .system(size: size, weight: .heavy, design: .rounded) }
    static func title(_ size: CGFloat = 21) -> Font { .system(size: size, weight: .bold, design: .rounded) }
    static func headline(_ size: CGFloat = 16) -> Font { .system(size: size, weight: .semibold, design: .rounded) }
    static func body(_ size: CGFloat = 15) -> Font { .system(size: size, weight: .medium, design: .rounded) }
    static func caption(_ size: CGFloat = 12.5) -> Font { .system(size: size, weight: .semibold, design: .rounded) }
    static func numeric(_ size: CGFloat = 26) -> Font { .system(size: size, weight: .heavy, design: .rounded) }
}

enum OceanGradient {
    /// Primary call to action: turquoise shallows into ocean blue.
    /// Text on it stays deep-sea navy, which keeps contrast well above AA.
    static let cta = LinearGradient(
        colors: [Ocean.turquoise, Color(hex: 0x36BEE6), Ocean.blue],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// The sun glint that slides across the water on a CTA.
    static let sunGlint = LinearGradient(
        stops: [
            .init(color: .white.opacity(0.0), location: 0.18),
            .init(color: .white.opacity(0.55), location: 0.42),
            .init(color: .white.opacity(0.0), location: 0.66),
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let ctaMuted = LinearGradient(
        colors: [Ocean.turquoise.opacity(0.55), Ocean.blue.opacity(0.55)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// A float or bubble: lit from above, deeper towards the waterline.
    static func token(_ color: Color) -> LinearGradient {
        LinearGradient(
            colors: [color.opacity(0.95), color.opacity(0.62)],
            startPoint: .top, endPoint: .bottom
        )
    }

    static func glossyDisc(_ color: Color) -> RadialGradient {
        RadialGradient(
            colors: [Color.white.opacity(0.9), color.opacity(0.0)],
            center: UnitPoint(x: 0.32, y: 0.2), startRadius: 1, endRadius: 32
        )
    }

    /// Surface water: foam at the top, shallow sky below.
    static let screen = LinearGradient(
        colors: [Ocean.foam, Color(hex: 0xE6F6FF)],
        startPoint: .top, endPoint: .bottom
    )

    /// The glossy sheen across a water panel.
    static let panelSheen = LinearGradient(
        colors: [Color.white.opacity(0.85), Color.white.opacity(0.15)],
        startPoint: .top, endPoint: .bottom
    )
}

enum OceanMotion {
    static let pop = Animation.spring(response: 0.36, dampingFraction: 0.72)
    static let soft = Animation.spring(response: 0.5, dampingFraction: 0.86)
    static let quick = Animation.easeOut(duration: 0.18)
    /// Slow drift for decorative water motion.
    static let drift = Animation.easeInOut(duration: 6).repeatForever(autoreverses: true)
}

enum OceanRadius {
    static let card: CGFloat = 26
    static let tile: CGFloat = 20
    static let chip: CGFloat = 14
}

extension View {
    /// Soft blue lift used on every raised water surface.
    func waterShadow(_ tint: Color, strength: Double = 1) -> some View {
        shadow(color: tint.opacity(0.16 * strength), radius: 14 * strength, x: 0, y: 8 * strength)
            .shadow(color: Ocean.deep.opacity(0.05 * strength), radius: 3 * strength, x: 0, y: 1)
    }

    /// Leaves room for the floating tab bar.
    func oceanTabInset() -> some View {
        safeAreaInset(edge: .bottom) { Color.clear.frame(height: 86) }
    }
}

#if canImport(UIKit)
import UIKit

enum Haptics {
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
#else
enum Haptics {
    static func success() {}
    static func warning() {}
    static func tap() {}
}
#endif
