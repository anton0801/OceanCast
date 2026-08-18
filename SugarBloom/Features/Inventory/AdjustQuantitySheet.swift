//
//  AdjustQuantitySheet.swift
//  Ocean Cast
//
//  The one place quantities change. A reason is always required.
//

import SwiftUI

struct AdjustQuantitySheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var batchID: UUID
    var initialReason: AdjustReason = .used
    var onDone: ((String) -> Void)?

    @State private var amountText = ""
    @State private var reason: AdjustReason = .used
    @State private var direction: Direction = .remove
    @State private var note = ""
    @State private var error: String?
    @State private var isSaving = false

    private enum Direction: String, CaseIterable, Identifiable {
        case remove, add
        var id: String { rawValue }
        var title: String { self == .remove ? "Remove" : "Add back" }
    }

    private var batch: Batch? { store.batch(batchID) }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let batch {
                    VStack(alignment: .leading, spacing: 18) {
                        ScreenHeader(eyebrow: batch.displayTitle,
                                     title: "Adjust quantity",
                                     subtitle: "On hand \(Format.measure(batch.remaining, batch.unit)) · reserved \(Format.measure(store.reserved(batch.id), batch.unit)) · available \(Format.measure(store.available(batch), batch.unit))",
                                     tint: Ocean.turquoise)

                        WaveCard(tint: Ocean.turquoise) {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack(spacing: 8) {
                                    ForEach(Direction.allCases) { option in
                                        OceanChip(title: option.title, tint: Ocean.turquoise,
                                                  isOn: direction == option) { direction = option }
                                    }
                                }

                                QuantityStepperField(label: "Amount (\(batch.unit.short))",
                                                     error: error, text: $amountText)

                                VStack(alignment: .leading, spacing: 8) {
                                    FieldLabel(text: "Reason", required: true)
                                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                        ForEach(AdjustReason.allCases) { option in
                                            OceanChip(title: option.title, symbol: option.symbol,
                                                      tint: reasonTint(option), isOn: reason == option) {
                                                reason = option
                                            }
                                        }
                                    }
                                }

                                OceanTextField(label: "Note", placeholder: "optional", text: $note)

                                quickButtons(batch)
                            }
                        }

                        InfoNote(text: "Every adjustment is written to this batch's history with its reason, so Insights can separate real use from waste.")

                        OceanButton(title: "Save Adjustment", symbol: "checkmark", isBusy: isSaving) { save() }
                    }
                    .padding(20)
                    .padding(.bottom, 30)
                } else {
                    EmptyStateCard(title: "This batch no longer exists",
                                   message: "It may have been deleted from another screen.",
                                   tint: Ocean.coral)
                        .padding(20)
                }
            }
            .scrollIndicators(.hidden)
            .background(OceanBackground(tint: Ocean.turquoise))
            .navigationTitle("Adjust Quantity")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear { reason = initialReason }
        }
    }

    private func reasonTint(_ reason: AdjustReason) -> Color {
        switch reason {
        case .used: return Ocean.turquoise
        case .spilled: return Ocean.coral
        case .corrected: return Ocean.tide
        case .discarded: return Ocean.blue
        }
    }

    private func quickButtons(_ batch: Batch) -> some View {
        HStack(spacing: 8) {
            ForEach([0.25, 0.5, 1.0], id: \.self) { fraction in
                Button {
                    amountText = Format.quantity(batch.remaining * fraction)
                    Haptics.tap()
                } label: {
                    Text(fraction == 1 ? "All" : "\(Int(fraction * 100))%")
                        .font(OceanFont.caption(12))
                }
                .buttonStyle(OceanButtonStyle(kind: .ghost, fullWidth: false, compact: true))
            }
        }
    }

    private func save() {
        guard !isSaving, let batch else { return }
        guard let amount = Parse.double(amountText), amount > 0 else {
            error = "Enter an amount greater than 0."
            Haptics.warning()
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let delta = direction == .remove ? -amount : amount
            try store.adjust(batchID: batch.id, delta: delta, reason: reason,
                             note: note.isEmpty ? nil : note)
            Haptics.success()
            onDone?("\(direction == .remove ? "Removed" : "Added") \(Format.measure(amount, batch.unit)) · \(reason.title)")
            dismiss()
        } catch {
            self.error = error.localizedDescription
            Haptics.warning()
        }
    }
}

struct MoveBatchSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var batchID: UUID
    var onDone: ((String) -> Void)?

    @State private var zoneID: UUID?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ScreenHeader(eyebrow: store.batch(batchID)?.productName ?? "Item",
                                 title: "Move to another zone",
                                 tint: Ocean.tide)

                    WaveCard(tint: Ocean.tide) {
                        VStack(alignment: .leading, spacing: 10) {
                            OceanChip(title: "No zone", tint: Ocean.tide, isOn: zoneID == nil) { zoneID = nil }
                            ForEach(store.household?.activeZones ?? []) { zone in
                                OceanChip(title: zone.name, symbol: zone.kind.symbol,
                                          tint: Ocean.tide, isOn: zoneID == zone.id) {
                                    zoneID = zone.id
                                }
                            }
                        }
                    }

                    OceanButton(title: "Move Item", symbol: "arrow.left.arrow.right") {
                        store.move(batchID: batchID, to: zoneID)
                        Haptics.success()
                        onDone?("Moved to \(store.zoneName(zoneID) ?? "No zone")")
                        dismiss()
                    }
                }
                .padding(20)
            }
            .background(OceanBackground(tint: Ocean.tide))
            .navigationTitle("Move Item")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { zoneID = store.batch(batchID)?.zoneID }
        }
    }
}
