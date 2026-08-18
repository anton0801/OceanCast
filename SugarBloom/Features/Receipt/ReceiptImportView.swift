//
//  ReceiptImportView.swift
//  Ocean Cast
//
//  SCREEN 4 — A receipt photo produces a draft, never stock.
//  Inventory changes only after Confirm Import.
//

import SwiftUI
import PhotosUI

struct ReceiptImportView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    enum Stage: Equatable { case empty, scanning, review, imported, failed(String) }

    @State private var stage: Stage = .empty
    @State private var photoItem: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var lines: [ReceiptLine] = []
    @State private var scannedAt: Date?
    @State private var showMatches = false
    @State private var importedCount = 0
    @State private var zoneID: UUID?
    @State private var toast: ToastMessage?
    @State private var isImporting = false

    private let scanner = ReceiptScanner()

    private var included: [ReceiptLine] { lines.filter { !$0.ignored } }
    private var needsReviewCount: Int { included.filter(\.needsReview).count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch stage {
                    case .empty: emptyStage
                    case .scanning: scanningStage
                    case .review: reviewStage
                    case .imported: importedStage
                    case .failed(let message): failedStage(message)
                    }
                }
                .padding(20)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .background(OceanBackground(tint: Ocean.sky))
            .toastHost($toast)
            .navigationTitle("Receipt Import")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(stage == .imported ? "Close" : "Cancel") { dismiss() }
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    stage = .scanning
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        imageData = data
                        await runScan(data)
                    } else {
                        stage = .failed("The selected photo could not be read.")
                    }
                }
            }
        }
    }

    // MARK: - Stages

    private var emptyStage: some View {
        VStack(alignment: .leading, spacing: 18) {
            ScreenHeader(eyebrow: "Receipt",
                         title: "Turn a receipt into a draft",
                         subtitle: "Text is read on this device. Every line starts as a draft you can edit, split or ignore — your stock changes only when you confirm.",
                         tint: Ocean.sky)

            PhotosPicker(selection: $photoItem, matching: .images) {
                HStack(spacing: 8) {
                    Image(systemName: "photo.badge.plus").font(.system(size: 15, weight: .bold))
                    Text("Upload Receipt")
                }
            }
            .buttonStyle(OceanButtonStyle(kind: .primary))

            InfoNote(text: "Reading works best on a flat, well-lit photo. Handwriting and faded thermal print often fail — those lines are marked Needs Review instead of being guessed.")

            EmptyStateCard(symbol: "doc.text.viewfinder",
                           title: "No receipt loaded",
                           message: "Nothing has been imported yet. This screen stays empty until you pick a photo.",
                           tint: Ocean.sky)
        }
    }

    private var scanningStage: some View {
        VStack(alignment: .leading, spacing: 18) {
            ScreenHeader(eyebrow: "Receipt", title: "Reading the photo…", tint: Ocean.sky)
            LoadingCard(message: "Recognising text on this device", tint: Ocean.sky)
            InfoNote(text: "Nothing has been added to Inventory. This step only produces a draft.")
        }
    }

    private var reviewStage: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScreenHeader(eyebrow: "Draft — not imported yet",
                         title: "Review \(included.count) line(s)",
                         subtitle: needsReviewCount > 0
                            ? "\(needsReviewCount) line(s) need review: the text was read with low confidence or the quantity is missing."
                            : "Every line was read with usable confidence. Check them anyway — receipts abbreviate names.",
                         tint: Ocean.sky)

            HStack(spacing: 10) {
                OceanChip(title: showMatches ? "Hide matches" : "Review Matches",
                          symbol: "link", tint: Ocean.tide, isOn: showMatches) {
                    showMatches.toggle()
                }
                if let scannedAt {
                    SourceStampView(source: ReceiptScanner.sourceName, updated: scannedAt)
                }
            }

            zonePicker

            VStack(spacing: 12) {
                ForEach($lines) { $line in
                    ReceiptLineCard(line: $line,
                                    showMatch: showMatches,
                                    match: match(for: line),
                                    currency: store.currency,
                                    onSplit: { split(line) })
                }
            }

            OceanButton(title: "Confirm Import (\(included.count))", symbol: "tray.and.arrow.down.fill",
                        isBusy: isImporting) {
                confirmImport()
            }
            .disabled(included.isEmpty)

            if let imageData {
                WaveCard(tint: Ocean.tide) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Original photo").font(OceanFont.headline(15)).foregroundStyle(Ocean.ink)
                        #if os(iOS)
                        if let image = UIImage(data: imageData) {
                            Image(uiImage: image)
                                .resizable().scaledToFit()
                                .frame(maxHeight: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        #endif
                        OceanButton(title: "Delete original photo", symbol: "trash",
                                    kind: .danger, compact: true) {
                            self.imageData = nil
                            toast = ToastMessage(kind: .info, title: "Photo removed",
                                                 detail: "The draft lines you already have are kept.")
                        }
                    }
                }
            }

            OceanButton(title: "Start over with another photo", kind: .ghost) {
                reset()
            }
        }
    }

    private var zonePicker: some View {
        WaveCard(tint: Ocean.turquoise) {
            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(text: "Storage zone for imported items")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        OceanChip(title: "No zone", tint: Ocean.turquoise, isOn: zoneID == nil) { zoneID = nil }
                        ForEach(store.household?.activeZones ?? []) { zone in
                            OceanChip(title: zone.name, symbol: zone.kind.symbol,
                                      tint: Ocean.turquoise, isOn: zoneID == zone.id) {
                                zoneID = zone.id
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                Text("You can move any item later from Inventory.")
                    .font(OceanFont.caption(11)).foregroundStyle(Ocean.inkSoft)
            }
        }
    }

    private var importedStage: some View {
        VStack(alignment: .leading, spacing: 18) {
            WaveCard(tint: Ocean.turquoise, padding: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) {
                        FloatDisc(symbol: "checkmark", tint: Ocean.turquoise, size: 52)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Imported").font(OceanFont.title(20)).foregroundStyle(Ocean.ink)
                            Text("\(importedCount) batch(es) created")
                                .font(OceanFont.caption(12.5)).foregroundStyle(Ocean.inkSoft)
                        }
                    }
                    Text("Each line became its own batch, with the price you confirmed. Prices also went to Price History, and Home now counts them.")
                        .font(OceanFont.body(14)).foregroundStyle(Ocean.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            OceanButton(title: "Import another receipt", symbol: "doc.badge.plus") { reset() }
            OceanButton(title: "Done", kind: .ghost) { dismiss() }
        }
    }

    private func failedStage(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ScreenHeader(eyebrow: "Receipt", title: "The photo could not be read", tint: Ocean.coral)
            ErrorCard(title: "Reading failed", message: message,
                      onRetry: {
                          if let imageData {
                              Task { await runScan(imageData) }
                          } else {
                              stage = .empty
                          }
                      },
                      onDismiss: { stage = .empty })
            InfoNote(text: "You can always add items by hand instead — nothing about this receipt was saved.",
                     tint: Ocean.coral)
        }
    }

    // MARK: - Logic

    private func runScan(_ data: Data) async {
        stage = .scanning
        let outcome = await scanner.scan(imageData: data)
        switch outcome {
        case .lines(let found):
            lines = found
            scannedAt = Date()
            zoneID = store.household?.activeZones.first?.id
            stage = .review
            Haptics.success()
        case .noTextFound:
            stage = .failed("No readable text was found in this photo.")
        case .failed(let message):
            stage = .failed(message)
        }
    }

    private func match(for line: ReceiptLine) -> Batch? {
        let key = ProductKey.make(line.name)
        guard key.count >= 3 else { return nil }
        return store.data.batches
            .sorted { $0.createdAt > $1.createdAt }
            .first { $0.productKey.contains(key) || key.contains($0.productKey) }
    }

    private func split(_ line: ReceiptLine) {
        guard let index = lines.firstIndex(where: { $0.id == line.id }) else { return }
        let quantity = line.quantity ?? 1
        let half = max(quantity / 2, 0.5)
        var first = line
        first.quantityText = Format.quantity(half)
        var second = line
        second.id = UUID()
        second.quantityText = Format.quantity(max(quantity - half, 0.5))
        if let price = line.price {
            first.priceText = Format.quantity(price / 2)
            second.priceText = Format.quantity(price / 2)
        }
        lines[index] = first
        lines.insert(second, at: index + 1)
        Haptics.tap()
    }

    private func confirmImport() {
        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false }

        var created = 0
        var failures: [String] = []
        for line in included {
            guard let quantity = line.quantity, quantity > 0,
                  !line.name.trimmingCharacters(in: .whitespaces).isEmpty else {
                failures.append(line.rawText)
                continue
            }
            let batch = Batch(productName: line.name,
                              barcode: line.barcode.nilIfBlank,
                              quantity: quantity,
                              remaining: quantity,
                              unit: line.unit,
                              purchaseDate: Date(),
                              zoneID: zoneID,
                              price: line.price,
                              origin: .receipt)
            do {
                _ = try store.addBatch(batch)
                created += 1
            } catch {
                failures.append(line.name)
            }
        }

        store.rebuildRecallMatches()
        store.mutate { data in
            data.activity.insert(ActivityEntry(
                kind: .receiptImported,
                summary: "Receipt import confirmed",
                detail: "\(created) line(s) became batches" + (failures.isEmpty ? "" : " · \(failures.count) line(s) skipped")
            ), at: 0)
        }

        importedCount = created
        if failures.isEmpty {
            stage = .imported
            Haptics.success()
        } else {
            toast = ToastMessage(kind: .warning,
                                 title: "\(created) imported, \(failures.count) skipped",
                                 detail: "Skipped lines had no name or quantity. They are still here to fix.")
            lines.removeAll { line in
                !line.ignored && !failures.contains(line.name) && !failures.contains(line.rawText)
            }
            Haptics.warning()
        }
    }

    private func reset() {
        lines = []
        imageData = nil
        photoItem = nil
        scannedAt = nil
        importedCount = 0
        stage = .empty
    }
}

// MARK: - Line card

private struct ReceiptLineCard: View {
    @Binding var line: ReceiptLine
    var showMatch: Bool
    var match: Batch?
    var currency: String
    var onSplit: () -> Void

    private var tint: Color { line.ignored ? Ocean.inkFaint : (line.needsReview ? Ocean.coral : Ocean.turquoise) }

    var body: some View {
        WaveCard(tint: tint, padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    FloatDisc(symbol: line.ignored ? "eye.slash.fill" : (line.needsReview ? "questionmark" : "checkmark"),
                              tint: tint, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.rawText)
                            .font(OceanFont.caption(11.5))
                            .foregroundStyle(Ocean.inkSoft)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Text(line.needsReview ? "Needs Review" : "Read confidently")
                                .font(OceanFont.caption(10.5))
                                .foregroundStyle(line.needsReview ? Ocean.coral : Ocean.turquoise)
                            Text("· confidence \(Format.percent(line.confidence))")
                                .font(OceanFont.caption(10.5))
                                .foregroundStyle(Ocean.inkFaint)
                        }
                    }
                    Spacer()
                    Button {
                        line.ignored.toggle()
                        Haptics.tap()
                    } label: {
                        Image(systemName: line.ignored ? "arrow.uturn.backward.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(line.ignored ? Ocean.turquoise : Ocean.inkFaint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(line.ignored ? "Restore line" : "Ignore line")
                }

                if !line.ignored {
                    OceanTextField(label: "Name", text: $line.name)
                    HStack(alignment: .top, spacing: 10) {
                        OceanTextField(label: "Qty", keyboard: .decimal, text: $line.quantityText)
                        VStack(alignment: .leading, spacing: 6) {
                            FieldLabel(text: "Unit")
                            Menu {
                                ForEach(MeasureUnit.allCases) { unit in
                                    Button(unit.title) { line.unit = unit }
                                }
                            } label: {
                                HStack {
                                    Text(line.unit.short).font(OceanFont.headline(15)).foregroundStyle(Ocean.ink)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 10, weight: .bold)).foregroundStyle(Ocean.inkFaint)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: OceanRadius.chip, style: .continuous)
                                    .fill(Ocean.foam.opacity(0.85)))
                            }
                        }
                        OceanTextField(label: "Price (\(currency))", keyboard: .decimal, text: $line.priceText)
                    }

                    if showMatch {
                        if let match {
                            Text("Matches your record: \(match.displayTitle)")
                                .font(OceanFont.caption(11.5))
                                .foregroundStyle(Ocean.tide)
                        } else {
                            Text("No match in your records — this will be a new product.")
                                .font(OceanFont.caption(11.5))
                                .foregroundStyle(Ocean.inkSoft)
                        }
                    }

                    HStack(spacing: 10) {
                        OceanButton(title: "Split Item", symbol: "square.split.2x1",
                                    kind: .ghost, fullWidth: false, compact: true, action: onSplit)
                        Spacer()
                    }
                }
            }
        }
    }
}
