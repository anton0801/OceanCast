//
//  ExpiryReviewView.swift
//  Ocean Cast
//
//  SCREEN 7 — A queue built from the user's own dates. The app helps sort the
//  shelf; it never judges whether food is safe.
//

import SwiftUI

struct ExpiryReviewView: View {
    @Environment(AppStore.self) private var store
    @Environment(Navigator.self) private var navigator

    @State private var adjustBatchID: UUID?
    @State private var dateEditBatchID: UUID?
    @State private var stillGoodBatchID: UUID?
    @State private var toast: ToastMessage?

    private var queue: [Batch] { store.expiringSoon }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(eyebrow: "Expiry Review",
                             title: queue.isEmpty ? "Nothing waiting" : "\(queue.count) item(s) to sort out",
                             subtitle: "Ordered by the date you entered. Every action below is recorded.",
                             tint: Ocean.coral)

                disclaimer

                if queue.isEmpty {
                    EmptyStateCard(symbol: "checkmark.seal.fill",
                                   title: "No item is inside your window",
                                   message: store.undatedBatches.isEmpty
                                    ? "Nothing has a date within \(store.data.settings.expiryWindowDays) day(s). Add dates to items as you buy them and they will appear here."
                                    : "Nothing has a date within \(store.data.settings.expiryWindowDays) day(s). \(store.undatedBatches.count) batch(es) have no date at all — they stay Unknown until you set one.",
                                   actionTitle: store.undatedBatches.isEmpty ? nil : "Open Inventory",
                                   tint: Ocean.turquoise) {
                        navigator.open(.inventory)
                    }
                } else {
                    ForEach(queue) { batch in
                        ExpiryCard(batch: batch,
                                   onStillGood: { stillGoodBatchID = batch.id },
                                   onUseToday: { adjustBatchID = batch.id },
                                   onFreeze: { freeze(batch) },
                                   onDiscard: { discard(batch) },
                                   onEditDate: { dateEditBatchID = batch.id },
                                   onOpen: { navigator.push(.product(batch.id)) })
                    }
                }

                if !store.undatedBatches.isEmpty {
                    SectionCard(title: "Without a date", symbol: "questionmark.circle.fill", tint: Ocean.tide) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(store.undatedBatches.count) batch(es) have no date you entered. They are not counted as fresh or expired — they are Unknown.")
                                .font(OceanFont.body(14)).foregroundStyle(Ocean.inkSoft)
                            ForEach(store.undatedBatches.prefix(5)) { batch in
                                Button {
                                    dateEditBatchID = batch.id
                                } label: {
                                    HStack(spacing: 10) {
                                        FloatDisc(symbol: "calendar.badge.plus", tint: Ocean.tide, size: 30)
                                        Text(batch.displayTitle)
                                            .font(OceanFont.headline(14)).foregroundStyle(Ocean.ink)
                                        Spacer()
                                        Text("Set date").font(OceanFont.caption(11.5)).foregroundStyle(Ocean.tide)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(OceanBackground(tint: Ocean.coral))
        .toastHost($toast)
        .navigationTitle("Expiry Review")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(item: Binding(get: { adjustBatchID.map(IdentifiedUUID.init) },
                             set: { adjustBatchID = $0?.id })) { wrapper in
            AdjustQuantitySheet(batchID: wrapper.id, initialReason: .used) { message in
                toast = ToastMessage(title: "Recorded", detail: message)
            }
        }
        .sheet(item: Binding(get: { dateEditBatchID.map(IdentifiedUUID.init) },
                             set: { dateEditBatchID = $0?.id })) { wrapper in
            DateChangeSheet(batchID: wrapper.id, requireReason: false) { message in
                toast = ToastMessage(title: "Date updated", detail: message)
            }
        }
        .sheet(item: Binding(get: { stillGoodBatchID.map(IdentifiedUUID.init) },
                             set: { stillGoodBatchID = $0?.id })) { wrapper in
            DateChangeSheet(batchID: wrapper.id, requireReason: true) { message in
                toast = ToastMessage(title: "Your new date is saved", detail: message)
            }
        }
        .oceanTabInset()
    }

    private var disclaimer: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Ocean.coral)
            VStack(alignment: .leading, spacing: 3) {
                Text("Check the product yourself. This app cannot confirm food safety.")
                    .font(OceanFont.headline(14))
                    .foregroundStyle(Ocean.ink)
                Text("Dates here are the ones you typed. Ocean Cast sorts them — it does not inspect food.")
                    .font(OceanFont.caption(11.5))
                    .foregroundStyle(Ocean.inkSoft)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Ocean.sky.opacity(0.3))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Ocean.sky, lineWidth: 1.4))
        )
    }

    private func freeze(_ batch: Batch) {
        guard let freezer = store.household?.activeZones.first(where: { $0.kind == .freezer }) else {
            toast = ToastMessage(kind: .warning, title: "No freezer zone",
                                 detail: "Add a freezer zone in Household Setup first.")
            Haptics.warning()
            return
        }
        store.move(batchID: batch.id, to: freezer.id)
        Haptics.success()
        toast = ToastMessage(title: "Moved to \(freezer.name)",
                             detail: "Freezing does not change your date — edit it if you want a new one.")
    }

    private func discard(_ batch: Batch) {
        do {
            try store.adjust(batchID: batch.id, delta: -batch.remaining, reason: .discarded,
                             note: "Discarded during expiry review")
            Haptics.success()
            toast = ToastMessage(title: "Recorded as discarded",
                                 detail: "It will show up in Insights under waste.")
        } catch {
            Haptics.warning()
            toast = ToastMessage(kind: .warning, title: "Not changed", detail: error.localizedDescription)
        }
    }
}

private struct ExpiryCard: View {
    @Environment(AppStore.self) private var store

    var batch: Batch
    var onStillGood: () -> Void
    var onUseToday: () -> Void
    var onFreeze: () -> Void
    var onDiscard: () -> Void
    var onEditDate: () -> Void
    var onOpen: () -> Void

    private var state: ExpiryState { store.expiryState(batch) }

    private var tint: Color {
        switch state {
        // Coral is the app's only warm colour, so it marks the most urgent row:
        // something already past the user's own date.
        case .expired: return Ocean.coral
        case .soon: return Ocean.blue
        default: return Ocean.turquoise
        }
    }

    private var statusText: String {
        switch state {
        case .expired(let days): return "Past your date by \(days) day(s)"
        case .soon(let days): return days == 0 ? "Your date is today" : "Your date in \(days) day(s)"
        case .later(let days): return "Your date in \(days) day(s)"
        case .unknown: return "No date set"
        }
    }

    var body: some View {
        WaveCard(tint: tint, padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                Button(action: onOpen) {
                    HStack(spacing: 14) {
                        FloatDisc(symbol: "clock.fill", tint: tint, size: 46)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(batch.displayTitle)
                                .font(OceanFont.title(17)).foregroundStyle(Ocean.ink)
                                .multilineTextAlignment(.leading)
                            Text(statusText).font(OceanFont.caption(12)).foregroundStyle(tint)
                            Text("\(Format.measure(batch.remaining, batch.unit)) on hand · \(store.zoneName(batch.zoneID) ?? "No zone")")
                                .font(OceanFont.caption(11)).foregroundStyle(Ocean.inkFaint)
                        }
                        Spacer(minLength: 0)
                        RowChevron()
                    }
                }
                .buttonStyle(.plain)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    OceanChip(title: "Still Good for Me", symbol: "hand.thumbsup.fill",
                              tint: Ocean.turquoise, action: onStillGood)
                    OceanChip(title: "Use Today", symbol: "fork.knife", tint: Ocean.tide, action: onUseToday)
                    OceanChip(title: "Freeze", symbol: "snowflake", tint: Ocean.turquoise, action: onFreeze)
                    OceanChip(title: "Discard", symbol: "trash.fill", tint: Ocean.blue, action: onDiscard)
                }

                OceanChip(title: "Edit Date", symbol: "calendar", tint: Ocean.sky, action: onEditDate)
            }
        }
    }
}

// MARK: - Date change

struct DateChangeSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var batchID: UUID
    /// "Still Good for Me" requires a new date and a short note.
    var requireReason: Bool
    var onDone: ((String) -> Void)?

    @State private var date: Date?
    @State private var note = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let batch = store.batch(batchID) {
                        ScreenHeader(eyebrow: batch.displayTitle,
                                     title: requireReason ? "Set your new date" : "Change the date",
                                     subtitle: requireReason
                                        ? "Marking something good for you means giving it a new date. Ocean Cast records your decision — it does not assess the food."
                                        : "This is your own date. It is stored with the batch and written to its history.",
                                     tint: Ocean.turquoise)

                        WaveCard(tint: Ocean.turquoise) {
                            VStack(alignment: .leading, spacing: 14) {
                                OptionalDateField(label: "Your date", date: $date, tint: Ocean.turquoise)
                                if let error {
                                    Label(error, systemImage: "exclamationmark.circle.fill")
                                        .font(OceanFont.caption(11.5)).foregroundStyle(Ocean.coral)
                                }
                                OceanTextField(label: requireReason ? "Why (required)" : "Note",
                                               placeholder: requireReason ? "smells and looks fine to me" : "optional",
                                               required: requireReason,
                                               text: $note)
                            }
                        }

                        OceanButton(title: "Save Date", symbol: "checkmark") { save(batch) }
                    }
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .background(OceanBackground(tint: Ocean.turquoise))
            .navigationTitle("Edit Date")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { date = store.batch(batchID)?.bestBefore }
        }
    }

    private func save(_ batch: Batch) {
        if requireReason {
            guard date != nil else {
                error = "A new date is required."
                Haptics.warning()
                return
            }
            guard !note.trimmingCharacters(in: .whitespaces).isEmpty else {
                error = "Add a short reason so the history explains the change."
                Haptics.warning()
                return
            }
        }
        store.setBestBefore(batchID: batch.id, date: date,
                            note: note.isEmpty ? "changed by you" : note)
        Haptics.success()
        onDone?(date.map { "New date: \(DateFormat.day($0))" } ?? "Date cleared — the item is Unknown again")
        dismiss()
    }
}
