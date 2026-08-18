//
//  Components.swift
//  Ocean Cast
//
//  Shared building blocks: cards, buttons, chips, form fields, state views.
//

import SwiftUI

// MARK: - Surfaces

struct WaveCard<Content: View>: View {
    var tint: Color = Ocean.deep
    var padding: CGFloat = 18
    var radius: CGFloat = OceanRadius.card
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WaterPanel(tint: tint, radius: radius))
            .waterShadow(tint)
    }
}

/// The glossy water panel every surface in the app is made of: a lit sheen on
/// the upper edge, a soft waterline ripple, and colour bleeding up from below.
struct WaterPanel: View {
    var tint: Color = Ocean.blue
    var radius: CGFloat = OceanRadius.card

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            shape.fill(Ocean.surface)
            shape.fill(
                LinearGradient(colors: [tint.opacity(0.11), Ocean.sky.opacity(0.05), tint.opacity(0.03)],
                               startPoint: .top, endPoint: .bottom)
            )
            WaveShape(amplitude: 3, phase: 0.9, cycles: 2.4)
                .fill(tint.opacity(0.09))
                .frame(height: 30)
                .frame(maxHeight: .infinity, alignment: .top)
                .clipShape(shape)
            shape.fill(
                LinearGradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0.0)],
                               startPoint: .top, endPoint: .center)
            )
            shape.strokeBorder(tint.opacity(0.26), lineWidth: 1.4)
        }
    }
}

/// Card with a title row and optional trailing accessory.
struct SectionCard<Content: View, Accessory: View>: View {
    var title: String
    var symbol: String
    var tint: Color = Ocean.deep
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        WaveCard(tint: tint) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    FloatDisc(symbol: symbol, tint: tint, size: 38)
                    Text(title)
                        .font(OceanFont.title(18))
                        .foregroundStyle(Ocean.ink)
                    Spacer(minLength: 8)
                    accessory
                }
                content
            }
        }
    }
}

extension SectionCard where Accessory == EmptyView {
    init(title: String, symbol: String, tint: Color = Ocean.deep, @ViewBuilder content: () -> Content) {
        self.init(title: title, symbol: symbol, tint: tint, accessory: { EmptyView() }, content: content)
    }
}

// MARK: - Buttons

struct OceanButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, ghost, danger }

    var kind: Kind = .primary
    var tint: Color = Ocean.deep
    var fullWidth: Bool = true
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let vertical: CGFloat = compact ? 10 : 15
        let horizontal: CGFloat = compact ? 14 : 20

        return configuration.label
            .font(OceanFont.headline(compact ? 14 : 17))
            .foregroundStyle(foreground)
            .padding(.vertical, vertical)
            .padding(.horizontal, horizontal)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(background)
            .overlay(
                Capsule().strokeBorder(strokeColor, lineWidth: kind == .ghost ? 1.5 : 1.2)
            )
            .clipShape(Capsule())
            .shadow(color: shadowColor, radius: configuration.isPressed ? 4 : 12,
                    x: 0, y: configuration.isPressed ? 2 : 6)
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .animation(OceanMotion.quick, value: configuration.isPressed)
            .contentShape(Capsule())
    }

    @ViewBuilder private var background: some View {
        switch kind {
        case .primary:
            // Turquoise-to-ocean water with the sun glinting across it.
            Capsule()
                .fill(OceanGradient.cta)
                .overlay(
                    Capsule()
                        .fill(OceanGradient.sunGlint)
                        .blendMode(.plusLighter)
                )
                .overlay(
                    Capsule()
                        .fill(LinearGradient(colors: [Color.white.opacity(0.35), .clear],
                                             startPoint: .top, endPoint: .center))
                )
        case .secondary: Capsule().fill(tint.opacity(0.16))
        case .ghost: Capsule().fill(Ocean.surface.opacity(0.9))
        case .danger: Capsule().fill(Ocean.coral.opacity(0.18))
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary: return Ocean.ink
        case .secondary: return tint
        case .ghost: return Ocean.ink
        case .danger: return Color(hex: 0xB2321A)
        }
    }

    private var strokeColor: Color {
        switch kind {
        case .primary: return Color.white.opacity(0.55)
        case .secondary: return tint.opacity(0.30)
        case .ghost: return Ocean.hairline
        case .danger: return Ocean.coral.opacity(0.45)
        }
    }

    private var shadowColor: Color {
        switch kind {
        case .primary: return Ocean.blue.opacity(0.32)
        case .secondary: return tint.opacity(0.18)
        case .ghost: return Ocean.ink.opacity(0.08)
        case .danger: return Ocean.coral.opacity(0.20)
        }
    }
}

struct OceanButton: View {
    var title: String
    var symbol: String?
    var kind: OceanButtonStyle.Kind = .primary
    var tint: Color = Ocean.deep
    var fullWidth: Bool = true
    var compact: Bool = false
    var isBusy: Bool = false
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView().controlSize(.small).tint(Ocean.ink)
                } else if let symbol {
                    Image(systemName: symbol).font(.system(size: compact ? 13 : 15, weight: .bold))
                }
                Text(title)
            }
        }
        .buttonStyle(OceanButtonStyle(kind: kind, tint: tint, fullWidth: fullWidth, compact: compact))
        .disabled(isBusy)
    }
}

/// Small pill used for filters and quick actions.
struct OceanChip: View {
    var title: String
    var symbol: String?
    var tint: Color = Ocean.deep
    var isOn: Bool = false
    var badge: Int?
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 12, weight: .bold))
                }
                Text(title)
                    .font(OceanFont.caption(13))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(OceanFont.caption(11))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(isOn ? Color.white.opacity(0.35) : tint.opacity(0.22)))
                }
            }
            .foregroundStyle(isOn ? Color.white : Ocean.ink)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(
                Capsule().fill(isOn ? AnyShapeStyle(OceanGradient.token(tint)) : AnyShapeStyle(Ocean.surface))
            )
            .overlay(Capsule().strokeBorder(isOn ? Color.white.opacity(0.5) : tint.opacity(0.28), lineWidth: 1.2))
            .shadow(color: tint.opacity(isOn ? 0.28 : 0.10), radius: isOn ? 8 : 4, y: 3)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stats

struct StatTile: View {
    var value: String
    var label: String
    var symbol: String
    var tint: Color
    /// Shown under the number when the value could not be computed from real records.
    var note: String?
    var action: (() -> Void)?

    var body: some View {
        Button {
            Haptics.tap()
            action?()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    FloatDisc(symbol: symbol, tint: tint, size: 34)
                    Spacer()
                    if action != nil {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(tint.opacity(0.7))
                    }
                }
                Text(value)
                    .font(OceanFont.numeric(26))
                    .foregroundStyle(Ocean.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(label)
                    .font(OceanFont.caption(12))
                    .foregroundStyle(Ocean.inkSoft)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let note {
                    Text(note)
                        .font(OceanFont.caption(10.5))
                        .foregroundStyle(Ocean.readable(tint))
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(WaterPanel(tint: tint, radius: OceanRadius.tile))
            .waterShadow(tint, strength: 0.8)
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}

// MARK: - State views

struct EmptyStateCard: View {
    var symbol: String = "sparkles"
    var title: String
    var message: String
    var actionTitle: String?
    var tint: Color = Ocean.deep
    var action: (() -> Void)?

    var body: some View {
        WaveCard(tint: tint, padding: 22) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    FloatDisc(symbol: symbol, tint: tint, size: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(OceanFont.title(19)).foregroundStyle(Ocean.ink)
                    }
                }
                Text(message)
                    .font(OceanFont.body(14.5))
                    .foregroundStyle(Ocean.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    OceanButton(title: actionTitle, symbol: "arrow.right", tint: tint, action: action)
                }
            }
        }
    }
}

struct LoadingCard: View {
    var message: String
    var tint: Color = Ocean.turquoise

    var body: some View {
        WaveCard(tint: tint) {
            HStack(spacing: 14) {
                ProgressView().tint(tint)
                Text(message).font(OceanFont.body()).foregroundStyle(Ocean.inkSoft)
                Spacer()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct ErrorCard: View {
    var title: String
    var message: String
    var retryTitle: String = "Retry"
    var onRetry: (() -> Void)?
    var onDismiss: (() -> Void)?

    var body: some View {
        WaveCard(tint: Ocean.coral) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    FloatDisc(symbol: "exclamationmark.triangle.fill", tint: Ocean.coral, size: 36)
                    Text(title).font(OceanFont.title(17)).foregroundStyle(Ocean.ink)
                }
                Text(message)
                    .font(OceanFont.body(14))
                    .foregroundStyle(Ocean.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    if let onRetry {
                        OceanButton(title: retryTitle, symbol: "arrow.clockwise", kind: .secondary,
                                    tint: Ocean.coral, fullWidth: false, compact: true, action: onRetry)
                    }
                    if let onDismiss {
                        OceanButton(title: "Dismiss", kind: .ghost, fullWidth: false, compact: true, action: onDismiss)
                    }
                }
            }
        }
    }
}

/// "Source · Last updated" stamp required next to every externally sourced value.
struct SourceStampView: View {
    var source: String
    var updated: Date?
    var isCached: Bool = false
    var url: URL?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isCached ? "wifi.slash" : "checkmark.seal.fill")
                .font(.system(size: 10, weight: .bold))
            VStack(alignment: .leading, spacing: 1) {
                Text("Source: \(source)")
                Text(updated.map { "Last updated \(DateFormat.stamp($0))" } ?? "Last updated: Unknown")
            }
            if let url {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right.square.fill").font(.system(size: 12, weight: .bold))
                }
            }
        }
        .font(OceanFont.caption(10.5))
        .foregroundStyle(isCached ? Ocean.coral : Ocean.inkSoft)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill((isCached ? Ocean.coral : Ocean.turquoise).opacity(0.10)))
    }
}

/// Honest banner shown while the device is offline on screens using external data.
struct OfflineBanner: View {
    var lastUpdated: Date?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash").font(.system(size: 13, weight: .bold))
            VStack(alignment: .leading, spacing: 2) {
                Text("Offline — showing a local snapshot").font(OceanFont.caption(12.5))
                Text(lastUpdated.map { "Snapshot from \(DateFormat.stamp($0))" } ?? "No snapshot stored yet")
                    .font(OceanFont.caption(11))
                    .foregroundStyle(Ocean.inkSoft)
            }
            Spacer()
        }
        .foregroundStyle(Ocean.ink)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: OceanRadius.chip, style: .continuous)
                .fill(Ocean.sky.opacity(0.35))
                .overlay(RoundedRectangle(cornerRadius: OceanRadius.chip, style: .continuous)
                    .strokeBorder(Ocean.sky.opacity(0.7), lineWidth: 1.2))
        )
    }
}

struct InfoNote: View {
    var text: String
    var symbol: String = "info.circle.fill"
    var tint: Color = Ocean.turquoise

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(tint)
            Text(text)
                .font(OceanFont.caption(12))
                .foregroundStyle(Ocean.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tint.opacity(0.10)))
    }
}

/// Value that may legitimately be unknown. Never renders unknown as zero.
struct ValueOrUnknown: View {
    var value: String?
    var unknownLabel: String = "Unknown"
    var font: Font = OceanFont.headline()
    var tint: Color = Ocean.ink

    var body: some View {
        if let value, !value.isEmpty {
            Text(value).font(font).foregroundStyle(tint)
        } else {
            Text(unknownLabel)
                .font(OceanFont.caption(11.5))
                .foregroundStyle(Ocean.coral)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Ocean.coral.opacity(0.14)))
        }
    }
}

// MARK: - Form fields

struct FieldLabel: View {
    var text: String
    var required: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Text(text.uppercased())
                .font(OceanFont.caption(11))
                .foregroundStyle(Ocean.inkSoft)
                .tracking(0.6)
            if required {
                Text("required")
                    .font(OceanFont.caption(9.5))
                    .foregroundStyle(Ocean.blue)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Ocean.blue.opacity(0.14)))
            }
        }
    }
}

struct OceanField<Content: View>: View {
    var label: String
    var required: Bool = false
    var error: String?
    var tint: Color = Ocean.deep
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(text: label, required: required)
            content
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: OceanRadius.chip, style: .continuous)
                        .fill(Ocean.foam.opacity(0.8))
                        .overlay(
                            RoundedRectangle(cornerRadius: OceanRadius.chip, style: .continuous)
                                .strokeBorder(error == nil ? tint.opacity(0.25) : Ocean.coral, lineWidth: 1.4)
                        )
                )
            if let error {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(OceanFont.caption(11.5))
                    .foregroundStyle(Ocean.coral)
            }
        }
    }
}

struct OceanTextField: View {
    var label: String
    var placeholder: String = ""
    var required: Bool = false
    var error: String?
    var keyboard: KeyboardKind = .default
    @Binding var text: String

    enum KeyboardKind { case `default`, number, decimal, email }

    var body: some View {
        OceanField(label: label, required: required, error: error) {
            textField
        }
    }

    @ViewBuilder private var textField: some View {
        let field = TextField(placeholder, text: $text)
            .font(OceanFont.body(15.5))
            .foregroundStyle(Ocean.ink)
            .textFieldStyle(.plain)
        #if os(iOS)
        switch keyboard {
        case .default: field.autocorrectionDisabled(false)
        case .number: field.keyboardType(.numberPad)
        case .decimal: field.keyboardType(.decimalPad)
        case .email: field.keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
        }
        #else
        field
        #endif
    }
}

/// Optional date row: an explicit "not set" state instead of silently defaulting to today.
struct OptionalDateField: View {
    var label: String
    var note: String?
    @Binding var date: Date?
    var tint: Color = Ocean.deep

    @State private var draft = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(text: label)
            HStack(spacing: 10) {
                if date == nil {
                    Button {
                        date = Calendar.current.startOfDay(for: draft)
                    } label: {
                        Label("Set date", systemImage: "calendar.badge.plus")
                            .font(OceanFont.caption(13))
                    }
                    .buttonStyle(OceanButtonStyle(kind: .secondary, tint: tint, fullWidth: false, compact: true))
                    Text("Not set")
                        .font(OceanFont.caption(11.5))
                        .foregroundStyle(Ocean.coral)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Ocean.coral.opacity(0.14)))
                } else {
                    DatePicker("", selection: Binding(
                        get: { date ?? draft },
                        set: { date = Calendar.current.startOfDay(for: $0) }
                    ), displayedComponents: .date)
                    .labelsHidden()
                    Button {
                        date = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Ocean.inkFaint)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            if let note {
                Text(note).font(OceanFont.caption(11)).foregroundStyle(Ocean.inkSoft)
            }
        }
    }
}

struct QuantityStepperField: View {
    var label: String
    var required: Bool = true
    var error: String?
    @Binding var text: String
    var tint: Color = Ocean.turquoise

    var body: some View {
        OceanField(label: label, required: required, error: error, tint: tint) {
            HStack(spacing: 12) {
                TextField("0", text: $text)
                    .font(OceanFont.headline(16))
                    .foregroundStyle(Ocean.ink)
                    .textFieldStyle(.plain)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                Button { step(-1) } label: {
                    Image(systemName: "minus").font(.system(size: 13, weight: .black))
                }
                .buttonStyle(StepperGlyphStyle(tint: tint))
                Button { step(1) } label: {
                    Image(systemName: "plus").font(.system(size: 13, weight: .black))
                }
                .buttonStyle(StepperGlyphStyle(tint: tint))
            }
        }
    }

    private func step(_ delta: Double) {
        let current = Parse.double(text) ?? 0
        let next = max(0, current + delta)
        text = Format.quantity(next)
        Haptics.tap()
    }
}

private struct StepperGlyphStyle: ButtonStyle {
    var tint: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(Circle().fill(OceanGradient.token(tint)))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(OceanMotion.quick, value: configuration.isPressed)
    }
}

// MARK: - Feedback

struct ToastMessage: Identifiable, Equatable {
    enum Kind: Equatable { case success, warning, info }
    let id = UUID()
    var kind: Kind = .success
    var title: String
    var detail: String?
}

struct ToastView: View {
    var toast: ToastMessage

    private var tint: Color {
        switch toast.kind {
        case .success: return Ocean.turquoise
        case .warning: return Ocean.coral
        case .info: return Ocean.deep
        }
    }

    private var symbol: String {
        switch toast.kind {
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            FloatDisc(symbol: symbol, tint: tint, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title).font(OceanFont.headline(15)).foregroundStyle(Ocean.ink)
                if let detail = toast.detail {
                    Text(detail).font(OceanFont.caption(12)).foregroundStyle(Ocean.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Ocean.surface)
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(tint.opacity(0.3), lineWidth: 1.4))
                .shadow(color: Ocean.ink.opacity(0.16), radius: 18, y: 8)
        )
        .padding(.horizontal, 16)
    }
}

struct ToastHost: ViewModifier {
    @Binding var toast: ToastMessage?

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let toast {
                ToastView(toast: toast)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: toast.id) {
                        try? await Task.sleep(nanoseconds: 2_600_000_000)
                        withAnimation(OceanMotion.soft) { self.toast = nil }
                    }
                    .zIndex(10)
            }
        }
        .animation(OceanMotion.soft, value: toast)
    }
}

extension View {
    func toastHost(_ toast: Binding<ToastMessage?>) -> some View {
        modifier(ToastHost(toast: toast))
    }

    /// Standard screen chrome: candy background + large rounded title.
    func oceanScreen(_ title: String, tint: Color = Ocean.deep) -> some View {
        self
            .background(OceanBackground(tint: tint))
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
    }
}

// MARK: - Headers

struct ScreenHeader: View {
    var eyebrow: String
    var title: String
    var subtitle: String?
    var tint: Color = Ocean.deep

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow.uppercased())
                .font(OceanFont.caption(11))
                .tracking(1.2)
                .foregroundStyle(tint)
            Text(title)
                .font(OceanFont.display(30))
                .foregroundStyle(Ocean.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(OceanFont.body(14.5))
                    .foregroundStyle(Ocean.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RowChevron: View {
    var tint: Color = Ocean.inkFaint
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(tint)
    }
}
