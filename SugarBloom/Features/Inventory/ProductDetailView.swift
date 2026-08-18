//
//  ProductDetailView.swift
//  Ocean Cast
//
//  SCREEN 6 — One batch: what is left, what is reserved, where it came from and
//  every change ever made to it.
//

import SwiftUI

struct ProductDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(Navigator.self) private var navigator
    @Environment(\.dismiss) private var dismiss

    var batchID: UUID

    @State private var showAdjust = false
    @State private var showMove = false
    @State private var showEdit = false
    @State private var showDelete = false
    @State private var showUseAll = false
    @State private var displayUnit: MeasureUnit?
    @State private var thresholdText = ""
    @State private var toast: ToastMessage?

    private var batch: Batch? { store.batch(batchID) }

    var body: some View {
        Group {
            if let batch {
                content(batch)
            } else {
                missingState
            }
        }
        .background(OceanBackground(tint: Ocean.turquoise))
        .toastHost($toast)
        .navigationTitle("Product Details")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .oceanTabInset()
    }

    private var missingState: some View {
        ScrollView {
            EmptyStateCard(symbol: "questionmark.folder.fill",
                           title: "This batch is gone",
                           message: "It was deleted or merged away from another screen. Nothing else was changed.",
                           actionTitle: "Back to Inventory",
                           tint: Ocean.coral) { dismiss() }
                .padding(20)
        }
    }

    private func content(_ batch: Batch) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard(batch)
                actionsCard(batch)
                detailsCard(batch)
                unitCard(batch)
                thresholdCard(batch)
                linkedMealsCard(batch)
                recallCard(batch)
                historyCard(batch)
                dangerZone(batch)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showAdjust) {
            AdjustQuantitySheet(batchID: batchID) { message in
                toast = ToastMessage(title: "Quantity updated", detail: message)
            }
        }
        .sheet(isPresented: $showMove) {
            MoveBatchSheet(batchID: batchID) { message in
                toast = ToastMessage(title: "Item moved", detail: message)
            }
        }
        .sheet(isPresented: $showEdit) {
            EditBatchView(batchID: batchID) { message in
                toast = ToastMessage(title: "Saved", detail: message)
            }
        }
        .confirmationDialog("Use everything left?", isPresented: $showUseAll, titleVisibility: .visible) {
            Button("Use all \(Format.measure(batch.remaining, batch.unit))") { useAll(batch) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(store.reserved(batch.id) > 0
                 ? "\(Format.measure(store.reserved(batch.id), batch.unit)) is reserved for a planned meal. Release the reservation first, or this will be blocked."
                 : "This records the whole batch as Used and leaves the history intact.")
        }
        .confirmationDialog("Delete this batch?", isPresented: $showDelete, titleVisibility: .visible) {
            Button("Delete permanently", role: .destructive) {
                store.deleteBatch(batchID)
                Haptics.warning()
                dismiss()
            }
            Button("Archive instead") {
                store.archiveBatch(batchID, archived: true)
                Haptics.success()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(store.deletionImpact(batchID: batchID).lines.joined(separator: "\n"))
        }
        .onAppear {
            thresholdText = store.data.restockThresholds[batch.productKey].map(Format.quantity) ?? ""
        }
    }

    // MARK: - Cards

    private func headerCard(_ batch: Batch) -> some View {
        let tint = Ocean.accent(for: batch.productKey)
        let purchased = batch.quantity
        let progress = purchased > 0 ? min(1, batch.remaining / purchased) : nil

        return WaveCard(tint: tint, padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    #if os(iOS)
                    if let data = PersistenceController.shared.photoData(batch.photoFilename),
                       let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable().scaledToFill()
                            .frame(width: 68, height: 68)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    } else {
                        FloatDisc(symbol: "shippingbox.fill", tint: tint, size: 68)
                    }
                    #else
                    FloatDisc(symbol: "shippingbox.fill", tint: tint, size: 68)
                    #endif

                    VStack(alignment: .leading, spacing: 4) {
                        Text(batch.productName)
                            .font(OceanFont.title(21))
                            .foregroundStyle(Ocean.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if let brand = batch.brand {
                            Text(brand).font(OceanFont.caption(12.5)).foregroundStyle(Ocean.inkSoft)
                        }
                        if batch.archived {
                            Text("Archived — not counted")
                                .font(OceanFont.caption(11))
                                .foregroundStyle(Ocean.coral)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(Ocean.coral.opacity(0.15)))
                        }
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 16) {
                    StockRing(progress: progress, tint: tint, size: 76,
                              centerText: Format.quantity(convert(batch.remaining, batch)))
                    VStack(alignment: .leading, spacing: 8) {
                        amountRow("On hand", convert(batch.remaining, batch), tint: Ocean.ink)
                        amountRow("Reserved", convert(store.reserved(batch.id), batch), tint: Ocean.tide)
                        amountRow("Available", convert(store.available(batch), batch), tint: Ocean.turquoise)
                    }
                    Spacer(minLength: 0)
                }

                Text("Purchased as \(Format.measure(batch.quantity, batch.unit)) · \(batch.origin.title)")
                    .font(OceanFont.caption(11))
                    .foregroundStyle(Ocean.inkFaint)
            }
        }
    }

    private func amountRow(_ label: String, _ value: Double, tint: Color) -> some View {
        HStack(spacing: 8) {
            Text(label).font(OceanFont.caption(11.5)).foregroundStyle(Ocean.inkSoft)
            Text(Format.measure(value, displayUnit ?? batch?.unit ?? .piece))
                .font(OceanFont.headline(14))
                .foregroundStyle(tint)
        }
    }

    private func convert(_ value: Double, _ batch: Batch) -> Double {
        guard let displayUnit, let converted = MeasureUnit.convert(value, from: batch.unit, to: displayUnit) else {
            return value
        }
        return converted
    }

    private func actionsCard(_ batch: Batch) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                OceanButton(title: "Use Some", symbol: "minus.circle.fill") { showAdjust = true }
                OceanButton(title: "Use All", symbol: "checkmark.circle.fill",
                            kind: .secondary, tint: Ocean.turquoise) { showUseAll = true }
            }
            HStack(spacing: 10) {
                OceanChip(title: "Edit Details", symbol: "square.and.pencil", tint: Ocean.tide) { showEdit = true }
                OceanChip(title: "Move", symbol: "arrow.left.arrow.right", tint: Ocean.turquoise) { showMove = true }
                OceanChip(title: batch.opened ? "Mark unopened" : "Mark Opened", symbol: "seal.fill",
                          tint: Ocean.sky) {
                    store.markOpened(batchID: batch.id, opened: !batch.opened)
                    toast = ToastMessage(title: batch.opened ? "Marked unopened" : "Marked opened")
                }
            }
            HStack(spacing: 10) {
                OceanChip(title: batch.archived ? "Restore" : "Archive", symbol: "archivebox.fill",
                          tint: Ocean.coral) {
                    store.archiveBatch(batch.id, archived: !batch.archived)
                    toast = ToastMessage(kind: .info,
                                         title: batch.archived ? "Restored" : "Archived",
                                         detail: batch.archived ? "It counts again." : "It stops counting but keeps its history.")
                }
                OceanChip(title: "Price History", symbol: "chart.line.uptrend.xyaxis", tint: Ocean.sky) {
                    navigator.push(.priceHistory(key: batch.productKey, name: batch.productName))
                }
            }
        }
    }

    private func detailsCard(_ batch: Batch) -> some View {
        SectionCard(title: "Details", symbol: "list.bullet.rectangle.fill", tint: Ocean.tide) {
            VStack(spacing: 10) {
                detailRow("Your date", batch.bestBefore.map(DateFormat.day),
                          note: batch.bestBefore.map { DateFormat.relativeDays($0) })
                detailRow("Purchase date", batch.purchaseDate.map(DateFormat.day))
                detailRow("Storage zone", store.zoneName(batch.zoneID))
                detailRow("Price paid", store.money(batch.price))
                detailRow("Store", batch.store)
                detailRow("Barcode", batch.barcode)
                detailRow("Batch / lot code", batch.batchCode)
                detailRow("Opened", batch.opened ? (batch.openedAt.map(DateFormat.day) ?? "yes") : "not opened")
                if let notes = batch.notes {
                    detailRow("Notes", notes)
                }
                if let reference = batch.reference {
                    Divider().overlay(Ocean.hairline)
                    SourceStampView(source: reference.sourceName,
                                    updated: reference.fetchedAt,
                                    url: reference.sourceURL.flatMap(URL.init(string:)))
                    Text("Catalogue details are kept apart from your own date and quantity.")
                        .font(OceanFont.caption(10.5))
                        .foregroundStyle(Ocean.inkFaint)
                }
            }
        }
    }

    private func detailRow(_ label: String, _ value: String?, note: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(OceanFont.caption(12)).foregroundStyle(Ocean.inkSoft)
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                ValueOrUnknown(value: value, unknownLabel: "Not set", font: OceanFont.headline(14))
                if let note, value != nil {
                    Text(note).font(OceanFont.caption(10.5)).foregroundStyle(Ocean.inkFaint)
                }
            }
        }
    }

    private func unitCard(_ batch: Batch) -> some View {
        let compatible = MeasureUnit.allCases.filter { MeasureUnit.compatible($0, batch.unit) }
        return SectionCard(title: "Show amounts in", symbol: "ruler.fill", tint: Ocean.turquoise) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ForEach(compatible) { unit in
                        OceanChip(title: unit.short, tint: Ocean.turquoise,
                                  isOn: (displayUnit ?? batch.unit) == unit) {
                            displayUnit = unit
                        }
                    }
                }
                if compatible.count == 1 {
                    Text("\(batch.unit.title) cannot be converted into weight or volume — those are different dimensions, so Ocean Cast will not invent a factor.")
                        .font(OceanFont.caption(11))
                        .foregroundStyle(Ocean.inkSoft)
                }
            }
        }
    }

    private func thresholdCard(_ batch: Batch) -> some View {
        SectionCard(title: "Restock threshold", symbol: "arrow.down.circle.fill", tint: Ocean.sky) {
            VStack(alignment: .leading, spacing: 10) {
                OceanTextField(label: "Warn when total drops to (\(batch.unit.short))",
                               placeholder: "leave empty for no threshold",
                               keyboard: .decimal, text: $thresholdText)
                HStack(spacing: 10) {
                    OceanButton(title: "Save threshold", kind: .secondary, tint: Ocean.sky,
                                fullWidth: false, compact: true) {
                        store.setThreshold(Parse.double(thresholdText), for: batch.productKey, name: batch.productName)
                        Haptics.success()
                        toast = ToastMessage(title: Parse.double(thresholdText) == nil ? "Threshold cleared" : "Threshold saved",
                                             detail: "Low stock on Home uses this number.")
                    }
                    if store.data.restockThresholds[batch.productKey] != nil {
                        OceanButton(title: "Remove", kind: .ghost, fullWidth: false, compact: true) {
                            thresholdText = ""
                            store.setThreshold(nil, for: batch.productKey, name: batch.productName)
                            toast = ToastMessage(kind: .info, title: "Threshold removed")
                        }
                    }
                }
                Text("Without a threshold, low stock stays uncomputed for this product — it is never assumed to be zero.")
                    .font(OceanFont.caption(11)).foregroundStyle(Ocean.inkSoft)
            }
        }
    }

    @ViewBuilder
    private func linkedMealsCard(_ batch: Batch) -> some View {
        let reservations = store.reservations(for: batch.id)
        if !reservations.isEmpty {
            SectionCard(title: "Reserved by meals", symbol: "lock.fill", tint: Ocean.tide) {
                VStack(spacing: 8) {
                    ForEach(reservations) { reservation in
                        Button {
                            navigator.push(.meal(reservation.mealID))
                        } label: {
                            HStack(spacing: 10) {
                                FloatDisc(symbol: "fork.knife", tint: Ocean.tide, size: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(store.meal(reservation.mealID)?.name ?? "Meal")
                                        .font(OceanFont.headline(14)).foregroundStyle(Ocean.ink)
                                    Text("holds \(Format.measure(reservation.quantity, batch.unit))")
                                        .font(OceanFont.caption(11)).foregroundStyle(Ocean.inkSoft)
                                }
                                Spacer()
                                RowChevron()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Text("Reserved amounts lower Available but never On hand.")
                        .font(OceanFont.caption(10.5)).foregroundStyle(Ocean.inkFaint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private func recallCard(_ batch: Batch) -> some View {
        let matches = store.matches(forBatch: batch.id)
        if !matches.isEmpty {
            SectionCard(title: "Recall checks", symbol: "exclamationmark.shield.fill", tint: Ocean.coral) {
                VStack(spacing: 8) {
                    ForEach(matches) { match in
                        Button {
                            navigator.push(.recallDetail(match.alertID))
                        } label: {
                            HStack(spacing: 10) {
                                FloatDisc(symbol: "shield.fill",
                                          tint: match.decision == .unconfirmed ? Ocean.coral : Ocean.turquoise,
                                          size: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(match.decision.title)
                                        .font(OceanFont.headline(14)).foregroundStyle(Ocean.ink)
                                    Text(match.reason)
                                        .font(OceanFont.caption(11)).foregroundStyle(Ocean.inkSoft)
                                        .lineLimit(2)
                                }
                                Spacer()
                                RowChevron()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func historyCard(_ batch: Batch) -> some View {
        let entries = store.history(batchID: batch.id)
        return SectionCard(title: "History", symbol: "clock.arrow.circlepath", tint: Ocean.turquoise,
                           accessory: {
            Text("\(entries.count)")
                .font(OceanFont.caption(12))
                .foregroundStyle(Ocean.inkSoft)
        }, content: {
            VStack(spacing: 8) {
                if entries.isEmpty {
                    Text("No changes recorded yet.")
                        .font(OceanFont.body(14)).foregroundStyle(Ocean.inkSoft)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(entries.prefix(6)) { entry in
                        ActivityRow(entry: entry)
                    }
                    if entries.count > 6 {
                        Button {
                            navigator.push(.activity)
                        } label: {
                            HStack {
                                Text("View all \(entries.count) records")
                                    .font(OceanFont.caption(12.5))
                                    .foregroundStyle(Ocean.turquoise)
                                RowChevron(tint: Ocean.turquoise)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        })
    }

    private func dangerZone(_ batch: Batch) -> some View {
        WaveCard(tint: Ocean.coral) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Delete batch").font(OceanFont.headline(15)).foregroundStyle(Ocean.ink)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(store.deletionImpact(batchID: batch.id).lines, id: \.self) { line in
                        Label(line, systemImage: "arrow.turn.down.right")
                            .font(OceanFont.caption(11.5))
                            .foregroundStyle(Ocean.inkSoft)
                    }
                }
                OceanButton(title: "Delete Batch", symbol: "trash.fill", kind: .danger) {
                    showDelete = true
                }
                Text("Archiving is reversible and keeps every record. Deleting is not.")
                    .font(OceanFont.caption(10.5)).foregroundStyle(Ocean.inkFaint)
            }
        }
    }

    private func useAll(_ batch: Batch) {
        do {
            try store.adjust(batchID: batch.id, delta: -batch.remaining, reason: .used, note: "Used all")
            Haptics.success()
            toast = ToastMessage(title: "Batch used up", detail: "It stays in history and in Insights.")
        } catch {
            Haptics.warning()
            toast = ToastMessage(kind: .warning, title: "Not changed", detail: error.localizedDescription)
        }
    }
}

// MARK: - Edit

struct EditBatchView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var batchID: UUID
    var onSaved: ((String) -> Void)?

    @State private var form = BatchForm()
    @State private var errors: [String: String] = [:]
    @State private var isSaving = false
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let loadError {
                        ErrorCard(title: "Could not save", message: loadError,
                                  onRetry: { save() }, onDismiss: { self.loadError = nil })
                    }
                    WaveCard(tint: Ocean.tide) {
                        BatchFormFields(form: $form,
                                        errors: errors,
                                        zones: store.household?.activeZones ?? [],
                                        currency: store.currency,
                                        tint: Ocean.tide)
                    }
                    InfoNote(text: "Editing the purchased quantity does not change what is left — use Adjust Quantity for that, so the reason is recorded.",
                             tint: Ocean.tide)
                    OceanButton(title: "Save Changes", symbol: "checkmark", isBusy: isSaving) { save() }
                }
                .padding(20)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .background(OceanBackground(tint: Ocean.tide))
            .navigationTitle("Edit Details")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(isSaving)
                }
            }
            .onAppear {
                if let batch = store.batch(batchID) { form = BatchForm.from(batch) }
            }
        }
    }

    private func save() {
        guard !isSaving, let existing = store.batch(batchID) else { return }
        errors = form.validate()
        guard errors.isEmpty else {
            Haptics.warning()
            return
        }
        isSaving = true
        defer { isSaving = false }

        var working = form
        if let data = working.photoData, working.photoFilename == nil {
            working.photoFilename = try? PersistenceController.shared.savePhoto(data)
        }
        var updated = working.makeBatch(origin: existing.origin, existing: existing)
        // Purchased quantity may grow; remaining follows only when it was untouched.
        if existing.remaining == existing.quantity { updated.remaining = updated.quantity }
        else { updated.remaining = min(existing.remaining, updated.quantity) }

        do {
            try store.updateBatch(updated)
            store.rebuildRecallMatches()
            Haptics.success()
            onSaved?("Changes are visible everywhere this batch is used.")
            dismiss()
        } catch {
            loadError = error.localizedDescription
            Haptics.warning()
        }
    }
}
