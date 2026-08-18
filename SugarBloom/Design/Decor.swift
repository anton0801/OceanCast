//
//  Decor.swift
//  Ocean Cast
//
//  Sea decoration: waves and ripples, bubbles, floats, hooks and line, rope and
//  underwater plants, plus simple stylised fish. Everything is drawn from
//  primitives and positioned deterministically, so screens never shimmer
//  between renders and nothing here is borrowed from anyone else's artwork.
//

import SwiftUI

// MARK: - Shapes

/// A bubble: round, with the light coming from the upper left.
struct BubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(ellipseIn: rect)
    }
}

/// A drawn bubble — translucent skin plus the small highlight that makes it
/// read as air in water rather than a flat dot.
struct BubbleMark: View {
    var size: CGFloat = 16
    var tint: Color = Ocean.sky
    var opacity: Double = 0.6

    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(opacity * 0.45))
            Circle().strokeBorder(tint.opacity(opacity), lineWidth: max(1, size * 0.07))
            Circle()
                .fill(Color.white.opacity(opacity))
                .frame(width: size * 0.24, height: size * 0.24)
                .offset(x: -size * 0.18, y: -size * 0.2)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A rolling wave band, used for waterlines and dividers.
struct WaveShape: Shape {
    var amplitude: CGFloat = 16
    var phase: CGFloat = 0
    var cycles: CGFloat = 1

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        var x = rect.minX
        while x <= rect.maxX {
            let relative = x / max(rect.width, 1)
            let y = rect.midY + sin(relative * .pi * 2 * cycles + phase) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
            x += 3
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Simple side-on fish: body, tail fin, dorsal fin.
struct FishShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        let bodyEnd = rect.minX + w * 0.72

        // Body
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addQuadCurve(to: CGPoint(x: bodyEnd, y: rect.midY - h * 0.02),
                          control: CGPoint(x: rect.minX + w * 0.34, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.midY),
                          control: CGPoint(x: rect.minX + w * 0.34, y: rect.maxY))
        path.closeSubpath()

        // Tail
        path.move(to: CGPoint(x: bodyEnd, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY - h * 0.42))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY + h * 0.42))
        path.closeSubpath()

        // Dorsal fin
        path.move(to: CGPoint(x: rect.minX + w * 0.30, y: rect.minY + h * 0.20))
        path.addQuadCurve(to: CGPoint(x: rect.minX + w * 0.58, y: rect.minY + h * 0.26),
                          control: CGPoint(x: rect.minX + w * 0.44, y: rect.minY - h * 0.16))
        path.closeSubpath()

        return path
    }
}

/// A fishing float: rounded body with a slim antenna on top.
struct FloatShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let bodyTop = rect.minY + rect.height * 0.28
        let body = CGRect(x: rect.minX, y: bodyTop, width: rect.width, height: rect.height - (bodyTop - rect.minY))
        path.addEllipse(in: body)

        let stemWidth = max(rect.width * 0.12, 1.5)
        path.addRoundedRect(
            in: CGRect(x: rect.midX - stemWidth / 2, y: rect.minY, width: stemWidth, height: rect.height * 0.34),
            cornerSize: CGSize(width: stemWidth / 2, height: stemWidth / 2)
        )
        return path
    }
}

/// A fish hook hanging from a line.
struct HookShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let shankX = rect.midX + rect.width * 0.12

        // Eye
        path.addEllipse(in: CGRect(x: shankX - rect.width * 0.11, y: rect.minY,
                                   width: rect.width * 0.22, height: rect.width * 0.22))
        // Shank
        path.move(to: CGPoint(x: shankX, y: rect.minY + rect.width * 0.20))
        path.addLine(to: CGPoint(x: shankX, y: rect.maxY - rect.height * 0.30))
        // Bend
        path.addQuadCurve(to: CGPoint(x: rect.minX + rect.width * 0.14, y: rect.maxY - rect.height * 0.28),
                          control: CGPoint(x: rect.midX - rect.width * 0.05, y: rect.maxY + rect.height * 0.12))
        // Point
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.30, y: rect.maxY - rect.height * 0.52))
        return path
    }
}

/// A twisted rope, drawn as a run of small arcs.
struct RopeShape: Shape {
    var twists: Int = 8

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step = rect.width / CGFloat(max(twists, 1))
        var x = rect.minX
        var up = true
        while x < rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.midY))
            path.addQuadCurve(
                to: CGPoint(x: min(x + step, rect.maxX), y: rect.midY),
                control: CGPoint(x: x + step / 2, y: up ? rect.minY : rect.maxY)
            )
            x += step
            up.toggle()
        }
        return path
    }
}

/// Underwater plant: a few blades rising from the sea floor.
struct SeaweedShape: Shape {
    var blades: Int = 3

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spacing = rect.width / CGFloat(max(blades, 1))
        for index in 0..<max(blades, 1) {
            let baseX = rect.minX + spacing * (CGFloat(index) + 0.5)
            let height = rect.height * (index % 2 == 0 ? 1.0 : 0.72)
            let sway = spacing * (index % 2 == 0 ? 0.55 : -0.45)
            path.move(to: CGPoint(x: baseX, y: rect.maxY))
            path.addCurve(
                to: CGPoint(x: baseX + sway * 0.4, y: rect.maxY - height),
                control1: CGPoint(x: baseX + sway, y: rect.maxY - height * 0.35),
                control2: CGPoint(x: baseX - sway, y: rect.maxY - height * 0.7)
            )
        }
        return path
    }
}

// MARK: - Background

/// Full-screen backdrop: foam water, soft depth glow, drifting bubbles, a
/// couple of small fish, a cast line with its float, and weed on the floor.
struct OceanBackground: View {
    var tint: Color = Ocean.blue

    private struct Blob {
        let color: Color
        let size: CGFloat
        let x: CGFloat
        let y: CGFloat
        let opacity: Double
    }

    private var blobs: [Blob] {
        [
            Blob(color: Ocean.sky,       size: 300, x: 0.86, y: 0.00, opacity: 0.42),
            Blob(color: Ocean.turquoise, size: 260, x: 0.04, y: 0.10, opacity: 0.20),
            Blob(color: tint,            size: 300, x: 0.98, y: 0.56, opacity: 0.16),
            Blob(color: Ocean.blue,      size: 260, x: -0.06, y: 0.74, opacity: 0.14),
            Blob(color: Ocean.coral,     size: 200, x: 0.70, y: 0.99, opacity: 0.10),
        ]
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height

            ZStack(alignment: .topLeading) {
                OceanGradient.screen.ignoresSafeArea()

                ForEach(Array(blobs.enumerated()), id: \.offset) { _, blob in
                    Circle()
                        .fill(blob.color.opacity(blob.opacity))
                        .frame(width: blob.size, height: blob.size)
                        .blur(radius: 75)
                        .offset(x: width * blob.x - blob.size / 2, y: height * blob.y - blob.size / 2)
                }

                // Surface swell near the top, fading downwards so the band has no
                // hard edge cutting across the screen.
                WaveShape(amplitude: 10, phase: 0.4, cycles: 1.6)
                    .fill(LinearGradient(colors: [Ocean.sky.opacity(0.30), Ocean.sky.opacity(0.0)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: width * 1.2, height: 120)
                    .offset(x: -width * 0.1, y: height * 0.05)
                WaveShape(amplitude: 7, phase: 2.1, cycles: 1.2)
                    .fill(LinearGradient(colors: [Ocean.turquoise.opacity(0.20), Ocean.turquoise.opacity(0.0)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: width * 1.2, height: 90)
                    .offset(x: -width * 0.1, y: height * 0.09)

                // A cast line with its float. It hangs below the navigation bar so
                // decoration never sits under a toolbar button.
                Path { path in
                    path.move(to: CGPoint(x: width * 0.94, y: height * 0.02))
                    path.addQuadCurve(to: CGPoint(x: width * 0.86, y: height * 0.215),
                                      control: CGPoint(x: width * 0.99, y: height * 0.13))
                }
                .stroke(Ocean.deep.opacity(0.16), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))

                FloatShape()
                    .fill(Ocean.coral.opacity(0.45))
                    .frame(width: 13, height: 22)
                    .offset(x: width * 0.86 - 6.5, y: height * 0.215)

                // Hook and rope, lower left.
                HookShape()
                    .stroke(Ocean.deep.opacity(0.14), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .frame(width: 26, height: 40)
                    .offset(x: width * 0.09, y: height * 0.44)

                RopeShape(twists: 7)
                    .stroke(Ocean.deep.opacity(0.10), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 88, height: 12)
                    .offset(x: width * 0.62, y: height * 0.28)

                // Small fish, kept sparse so they never fight the content.
                FishShape()
                    .fill(Ocean.turquoise.opacity(0.30))
                    .frame(width: 34, height: 18)
                    .offset(x: width * 0.16, y: height * 0.63)
                FishShape()
                    .fill(Ocean.blue.opacity(0.22))
                    .frame(width: 24, height: 13)
                    .offset(x: width * 0.28, y: height * 0.69)
                FishShape()
                    .fill(Ocean.coral.opacity(0.24))
                    .frame(width: 20, height: 11)
                    .scaleEffect(x: -1, y: 1)
                    .offset(x: width * 0.82, y: height * 0.78)

                // Rising bubbles.
                Group {
                    bubble(size: 12, opacity: 0.35).offset(x: width * 0.34, y: height * 0.24)
                    bubble(size: 7, opacity: 0.30).offset(x: width * 0.39, y: height * 0.30)
                    bubble(size: 9, opacity: 0.26).offset(x: width * 0.72, y: height * 0.47)
                    bubble(size: 5, opacity: 0.28).offset(x: width * 0.76, y: height * 0.52)
                    bubble(size: 14, opacity: 0.22).offset(x: width * 0.12, y: height * 0.86)
                }

                // Weed along the sea floor.
                SeaweedShape(blades: 4)
                    .stroke(Ocean.turquoise.opacity(0.26), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 70, height: 74)
                    .offset(x: width * 0.02, y: height - 78)
                SeaweedShape(blades: 3)
                    .stroke(Ocean.blue.opacity(0.20), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 54, height: 54)
                    .offset(x: width * 0.84, y: height - 58)
            }
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
    }

    private func bubble(size: CGFloat, opacity: Double) -> some View {
        Circle()
            .strokeBorder(Ocean.blue.opacity(opacity), lineWidth: 1.2)
            .background(Circle().fill(Color.white.opacity(opacity * 0.5)))
            .frame(width: size, height: size)
    }
}

/// Small decorative ripple used as a section divider.
struct WaveDivider: View {
    var tint: Color = Ocean.turquoise

    var body: some View {
        WaveShape(amplitude: 4, phase: 0.6, cycles: 2)
            .fill(LinearGradient(colors: [tint.opacity(0.45), tint.opacity(0.06)],
                                 startPoint: .leading, endPoint: .trailing))
            .frame(height: 14)
            .clipShape(Capsule())
            .accessibilityHidden(true)
    }
}

// MARK: - Float disc

/// The round glossy marker used for icons all over the app — a float bobbing on
/// the surface, lit from above with a highlight and a waterline shadow.
struct FloatDisc: View {
    var symbol: String
    var tint: Color = Ocean.blue
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle()
                .fill(OceanGradient.token(tint))
            Circle()
                .fill(OceanGradient.glossyDisc(tint))
                .scaleEffect(0.98)
            // Waterline: the lower half sits a touch deeper.
            Circle()
                .fill(LinearGradient(colors: [.clear, Ocean.deep.opacity(0.16)],
                                     startPoint: .center, endPoint: .bottom))
            Circle()
                .strokeBorder(Color.white.opacity(0.6), lineWidth: 1.2)
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: Ocean.deep.opacity(0.35), radius: 2, y: 1)
        }
        .frame(width: size, height: size)
        .waterShadow(tint, strength: 0.7)
        .accessibilityHidden(true)
    }
}

/// Circular stock indicator drawn as a float ring with a bubble trail.
struct StockRing: View {
    /// `nil` means the value is genuinely unknown — never draw it as zero.
    var progress: Double?
    var tint: Color = Ocean.turquoise
    var size: CGFloat = 56
    var lineWidth: CGFloat = 8
    var centerText: String?

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.55))
            Circle()
                .stroke(tint.opacity(0.16), lineWidth: lineWidth)

            if let progress {
                Circle()
                    .trim(from: 0, to: max(0.02, min(1, progress)))
                    .stroke(
                        AngularGradient(colors: [tint.opacity(0.75), tint, Ocean.sky, tint.opacity(0.75)],
                                        center: .center),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                // Bubble highlight riding the top of the ring.
                Circle()
                    .fill(Color.white.opacity(0.75))
                    .frame(width: lineWidth * 0.42, height: lineWidth * 0.42)
                    .offset(y: -size / 2 + lineWidth / 2)
                    .rotationEffect(.degrees(360 * min(1, max(0.02, progress))))
            } else {
                Circle()
                    .trim(from: 0, to: 1)
                    .stroke(tint.opacity(0.28),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: [3, 6]))
            }

            if let centerText {
                Text(centerText)
                    .font(.system(size: size * 0.26, weight: .heavy, design: .rounded))
                    .foregroundStyle(Ocean.ink)
                    .minimumScaleFactor(0.5)
                    .padding(size * 0.18)
            }
        }
        .frame(width: size, height: size)
    }
}
