//
//  OnboardingView.swift
//  Ocean Cast
//
//  Explains the problem and the chain between sections, then creates the first
//  real record. No demo data is ever written.
//

import SwiftUI

struct OnboardingView: View {
    @Environment(AppStore.self) private var store

    @State private var page = 0
    @AppStorage("draft.householdName") private var householdName = ""
    @AppStorage("draft.currency") private var currency = Locale.current.currency?.identifier ?? "USD"
    @State private var error: String?
    @State private var isSaving = false

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            eyebrow: "Step 1",
            title: "Know What You Already Have",
            body: "Ocean Cast keeps real batches, not a wish list. Every item shows how much is left, where it is stored and the date you entered yourself.",
            symbol: "shippingbox.fill",
            tint: Ocean.turquoise,
            points: ["Separate batches keep different dates and prices apart",
                     "Nothing is ever counted twice",
                     "Unknown stays Unknown — never zero"]
        ),
        OnboardingPage(
            eyebrow: "Step 2",
            title: "Scan Purchases in Seconds",
            body: "Scan a barcode, type an item, or read a receipt photo. External catalogues only pre-fill the form — you confirm every field before it is saved.",
            symbol: "barcode.viewfinder",
            tint: Ocean.blue,
            points: ["Barcode lookup shows its source and time",
                     "Receipt lines start as a draft you review",
                     "Nothing enters Inventory without your confirmation"]
        ),
        OnboardingPage(
            eyebrow: "Step 3",
            title: "Plan Meals from Real Stock",
            body: "A planned meal reserves what it needs. Reserving lowers Available but never touches On Hand, so you always see the truth.",
            symbol: "fork.knife",
            tint: Ocean.tide,
            points: ["Missing amounts go to Shopping only when you confirm",
                     "A confirmed purchase creates a new batch",
                     "Cooking turns reservations into real usage"]
        ),
        OnboardingPage(
            eyebrow: "Step 4",
            title: "Create Your First Household",
            body: "A household holds your storage zones, currency and members. You can change all of it later in Settings.",
            symbol: "house.fill",
            tint: Ocean.coral,
            points: []
        )
    ]

    var body: some View {
        ZStack {
            OceanBackground(tint: pages[min(page, pages.count - 1)].tint)

            VStack(spacing: 0) {
                header

                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 18) {
                                OnboardingCard(page: item)
                                if index == pages.count - 1 { householdForm(tint: item.tint) }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)
                        }
                        .scrollIndicators(.hidden)
                        .tag(index)
                    }
                }
                #if os(iOS)
                .tabViewStyle(.page(indexDisplayMode: .never))
                #endif

                footer
            }
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(0..<pages.count, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? Ocean.ink : Ocean.ink.opacity(0.16))
                        .frame(width: index == page ? 22 : 8, height: 8)
                        .animation(OceanMotion.pop, value: page)
                }
            }
            Spacer()
            if page < pages.count - 1 {
                Button("Skip") { withAnimation(OceanMotion.soft) { page = pages.count - 1 } }
                    .font(OceanFont.caption(13))
                    .foregroundStyle(Ocean.inkSoft)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    private func householdForm(tint: Color) -> some View {
        WaveCard(tint: tint) {
            VStack(alignment: .leading, spacing: 14) {
                OceanTextField(label: "Household name", placeholder: "Our Kitchen",
                               required: true,
                               error: error,
                               text: $householdName)

                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel(text: "Default currency")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(CurrencyOptions.suggested, id: \.self) { code in
                                OceanChip(title: code, tint: tint, isOn: currency == code) { currency = code }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                InfoNote(text: "Your typed name is kept as a local draft until you tap Create. Ocean Cast stores everything on this device — no account is required.",
                         tint: tint)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if page < pages.count - 1 {
                OceanButton(title: "Continue", symbol: "arrow.right") {
                    withAnimation(OceanMotion.soft) { page += 1 }
                }
            } else {
                OceanButton(title: "Create Household", symbol: "sparkles", isBusy: isSaving) {
                    createHousehold()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }

    private func createHousehold() {
        guard !isSaving else { return }
        isSaving = true
        error = nil
        do {
            try store.createHousehold(name: householdName, currency: currency)
            store.completeOnboarding()
            householdName = ""
            Haptics.success()
        } catch {
            self.error = error.localizedDescription
            Haptics.warning()
        }
        isSaving = false
    }
}

struct OnboardingPage {
    var eyebrow: String
    var title: String
    var body: String
    var symbol: String
    var tint: Color
    var points: [String]
}

private struct OnboardingCard: View {
    var page: OnboardingPage

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ZStack {
                Circle()
                    .fill(OceanGradient.token(page.tint))
                    .frame(width: 132, height: 132)
                    .overlay(Circle().fill(OceanGradient.glossyDisc(page.tint)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 2))
                    .waterShadow(page.tint, strength: 1.4)
                Image(systemName: page.symbol)
                    .font(.system(size: 54, weight: .bold))
                    .foregroundStyle(.white)
                // Air escaping the float, so the mark reads as underwater.
                BubbleMark(size: 24, tint: Ocean.sky, opacity: 0.85)
                    .offset(x: 58, y: -46)
                BubbleMark(size: 13, tint: Ocean.sky, opacity: 0.7)
                    .offset(x: 74, y: -68)
                BubbleMark(size: 8, tint: Ocean.turquoise, opacity: 0.6)
                    .offset(x: -62, y: 34)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 10)

            ScreenHeader(eyebrow: page.eyebrow, title: page.title, subtitle: page.body, tint: page.tint)

            if !page.points.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(page.points, id: \.self) { point in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(page.tint)
                            Text(point)
                                .font(OceanFont.body(14.5))
                                .foregroundStyle(Ocean.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: OceanRadius.card, style: .continuous)
                        .fill(Ocean.surface.opacity(0.9))
                        .overlay(RoundedRectangle(cornerRadius: OceanRadius.card, style: .continuous)
                            .strokeBorder(page.tint.opacity(0.2), lineWidth: 1.4))
                )
            }
        }
    }
}

enum CurrencyOptions {
    static let suggested: [String] = {
        var codes = ["USD", "EUR", "GBP", "PLN", "CZK", "SEK", "CAD", "AUD"]
        if let local = Locale.current.currency?.identifier, !codes.contains(local) {
            codes.insert(local, at: 0)
        }
        return codes
    }()
}
