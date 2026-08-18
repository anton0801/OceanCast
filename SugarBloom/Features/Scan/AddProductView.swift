//
//  AddProductView.swift
//  Ocean Cast
//
//  SCREEN 3 — Scan a barcode or add a product by hand.
//  A catalogue answer only pre-fills the form; the user confirms every field.
//

import SwiftUI

struct AddProductView: View {
    enum Mode: Equatable { case chooser, scanning, form, saved }

    @Environment(AppStore.self) private var store
    @Environment(NetworkMonitor.self) private var network
    @Environment(\.dismiss) private var dismiss

    var initialBarcode: String?

    @State private var mode: Mode = .chooser
    @State private var form = BatchForm()
    @State private var errors: [String: String] = [:]
    @State private var isSaving = false
    @State private var lookupState: LookupState = .idle
    @State private var scannerError: String?
    @State private var savedBatch: Batch?
    @State private var toast: ToastMessage?
    @State private var showDiscardPrompt = false
    @State private var manualBarcode = ""
    @State private var searchText = ""

    private enum LookupState: Equatable {
        case idle
        case loading(String)
        case found(ProductLookupResult)
        case notFound(String)
        case offline(String)
        case failed(String, barcode: String)
    }

    private let lookupService = ProductLookupService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch mode {
                    case .chooser: chooser
                    case .scanning: scanner
                    case .form: formSection
                    case .saved: savedSection
                    }
                }
                .padding(20)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .background(OceanBackground(tint: Ocean.blue))
            .toastHost($toast)
            .navigationTitle(mode == .saved ? "Item saved" : "Add Product")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { attemptDismiss() }
                }
                if mode == .form {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save Item") { save() }
                            .font(OceanFont.headline(15))
                            .disabled(isSaving)
                    }
                }
            }
            .onAppear {
                if let initialBarcode, !initialBarcode.isEmpty {
                    form.barcode = initialBarcode
                    mode = .form
                }
            }
            .alert("Keep this draft?", isPresented: $showDiscardPrompt) {
                Button("Keep editing", role: .cancel) {}
                Button("Discard", role: .destructive) { dismiss() }
            } message: {
                Text("Nothing has been saved yet. Discarding loses what you typed; keeping it lets you finish and save.")
            }
        }
    }

    // MARK: - Chooser

    private var chooser: some View {
        VStack(alignment: .leading, spacing: 18) {
            ScreenHeader(eyebrow: "New item",
                         title: "How do you want to add it?",
                         subtitle: "Every route ends in the same form, and you confirm the fields before anything is saved.",
                         tint: Ocean.blue)

            OceanButton(title: "Scan Barcode", symbol: "barcode.viewfinder") {
                scannerError = nil
                mode = .scanning
            }

            WaveCard(tint: Ocean.turquoise) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Have the number already?")
                        .font(OceanFont.headline(15)).foregroundStyle(Ocean.ink)
                    HStack(spacing: 10) {
                        TextField("Type a barcode", text: $manualBarcode)
                            .font(OceanFont.body(15))
                            .textFieldStyle(.plain)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: OceanRadius.chip, style: .continuous)
                                .fill(Ocean.foam.opacity(0.85)))
                        OceanButton(title: "Look up", kind: .secondary, tint: Ocean.turquoise,
                                    fullWidth: false, compact: true) {
                            Task { await lookup(barcode: manualBarcode) }
                        }
                    }
                    lookupStateView
                }
            }

            searchCard

            OceanButton(title: "Add Without Barcode", symbol: "square.and.pencil",
                        kind: .ghost) {
                mode = .form
            }

            OceanButton(title: "Import a Receipt Instead", symbol: "doc.text.viewfinder",
                        kind: .ghost) {
                dismiss()
                // Receipt import is opened from Home; closing here keeps one flow on screen.
            }

            InfoNote(text: "Barcode lookup uses Open Food Facts. It can be wrong or incomplete — check the fields before saving. Your own dates are never taken from a catalogue.")
        }
    }

    private var searchCard: some View {
        WaveCard(tint: Ocean.tide) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Search Product")
                    .font(OceanFont.headline(15)).foregroundStyle(Ocean.ink)
                Text("Search products you already recorded, to reuse the name, unit and zone.")
                    .font(OceanFont.caption(11.5)).foregroundStyle(Ocean.inkSoft)
                TextField("Start typing…", text: $searchText)
                    .font(OceanFont.body(15))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: OceanRadius.chip, style: .continuous)
                        .fill(Ocean.foam.opacity(0.85)))

                let matches = searchMatches
                if searchText.isEmpty {
                    Text(store.data.batches.isEmpty
                         ? "No products recorded yet — this fills up as you add items."
                         : "\(store.knownProductNames.count) product name(s) recorded so far.")
                        .font(OceanFont.caption(11.5)).foregroundStyle(Ocean.inkSoft)
                } else if matches.isEmpty {
                    Text("No match in your records. You can still add it as a new product.")
                        .font(OceanFont.caption(11.5)).foregroundStyle(Ocean.coral)
                } else {
                    VStack(spacing: 8) {
                        ForEach(matches, id: \.id) { batch in
                            Button {
                                prefill(from: batch)
                            } label: {
                                HStack(spacing: 10) {
                                    FloatDisc(symbol: "shippingbox.fill", tint: Ocean.tide, size: 30)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(batch.productName)
                                            .font(OceanFont.headline(14)).foregroundStyle(Ocean.ink)
                                        Text("last added \(DateFormat.day(batch.createdAt)) · \(batch.unit.short)")
                                            .font(OceanFont.caption(11)).foregroundStyle(Ocean.inkSoft)
                                    }
                                    Spacer()
                                    RowChevron()
                                }
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Ocean.foam.opacity(0.7)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var searchMatches: [Batch] {
        guard !searchText.isEmpty else { return [] }
        let needle = ProductKey.make(searchText)
        var seen = Set<String>()
        return store.data.batches
            .sorted { $0.createdAt > $1.createdAt }
            .filter { $0.productKey.contains(needle) }
            .filter { seen.insert($0.productKey).inserted }
            .prefix(5)
            .map { $0 }
    }

    // MARK: - Scanner

    private var scanner: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScreenHeader(eyebrow: "Scanning", title: "Point at the barcode", tint: Ocean.blue)

            ZStack {
                RoundedRectangle(cornerRadius: OceanRadius.card, style: .continuous)
                    .fill(Ocean.ink.opacity(0.9))
                    .frame(height: 280)
                if scannerError == nil {
                    BarcodeScannerView(
                        onCode: { code in
                            guard mode == .scanning else { return }
                            Task { await lookup(barcode: code) }
                        },
                        onFailure: { message in scannerError = message }
                    )
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: OceanRadius.card, style: .continuous))
                }
                RoundedRectangle(cornerRadius: OceanRadius.card, style: .continuous)
                    .strokeBorder(Ocean.sky.opacity(0.9), lineWidth: 3)
                    .frame(height: 280)
            }

            if let scannerError {
                ErrorCard(title: "Camera not available", message: scannerError,
                          retryTitle: "Try camera again",
                          onRetry: { self.scannerError = nil })
            }

            lookupStateView

            OceanButton(title: "Add Without Barcode", symbol: "square.and.pencil", kind: .secondary,
                        tint: Ocean.turquoise) {
                mode = .form
            }
            OceanButton(title: "Back", kind: .ghost) { mode = .chooser }
        }
    }

    @ViewBuilder
    private var lookupStateView: some View {
        switch lookupState {
        case .idle:
            EmptyView()
        case .loading(let code):
            LoadingCard(message: "Looking up \(code) in the catalogue…")
        case .found(let result):
            WaveCard(tint: Ocean.turquoise) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Found in the catalogue")
                        .font(OceanFont.headline(15)).foregroundStyle(Ocean.ink)
                    Text(result.name ?? "This barcode has no product name in the catalogue.")
                        .font(OceanFont.body(14)).foregroundStyle(Ocean.ink)
                    if let brand = result.brand {
                        Text(brand).font(OceanFont.caption(12)).foregroundStyle(Ocean.inkSoft)
                    }
                    SourceStampView(source: result.sourceName, updated: result.fetchedAt, url: result.sourceURL)
                    OceanButton(title: "Use these values", symbol: "arrow.down.doc.fill",
                                kind: .secondary, tint: Ocean.turquoise) {
                        apply(result)
                    }
                    Text("Nothing is saved yet — you still confirm every field.")
                        .font(OceanFont.caption(11)).foregroundStyle(Ocean.inkSoft)
                }
            }
        case .notFound(let code):
            WaveCard(tint: Ocean.sky) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Barcode \(code) is not in the catalogue")
                        .font(OceanFont.headline(15)).foregroundStyle(Ocean.ink)
                    Text("That is normal for local or store-brand products. Add it by hand — the barcode is kept with your item and still works for recall checks.")
                        .font(OceanFont.caption(12)).foregroundStyle(Ocean.inkSoft)
                    OceanButton(title: "Add by hand", symbol: "square.and.pencil",
                                kind: .secondary, tint: Ocean.sky) {
                        form.barcode = code
                        mode = .form
                    }
                }
            }
        case .offline(let code):
            WaveCard(tint: Ocean.coral) {
                VStack(alignment: .leading, spacing: 10) {
                    OfflineBanner(lastUpdated: nil)
                    Text("The catalogue cannot be reached, so no product details were loaded. The barcode \(code) is kept and you can fill the rest yourself.")
                        .font(OceanFont.caption(12)).foregroundStyle(Ocean.inkSoft)
                    OceanButton(title: "Continue by hand", kind: .secondary, tint: Ocean.coral) {
                        form.barcode = code
                        mode = .form
                    }
                }
            }
        case .failed(let message, let code):
            ErrorCard(title: "Lookup failed", message: message,
                      onRetry: { Task { await lookup(barcode: code) } },
                      onDismiss: {
                          form.barcode = code
                          mode = .form
                      })
        }
    }

    // MARK: - Form

    private var formSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            ScreenHeader(eyebrow: "Confirm",
                         title: "Check the details",
                         subtitle: "Saving creates one batch. Two purchases of the same product stay separate, so dates and prices never blend.",
                         tint: Ocean.blue)

            WaveCard(tint: Ocean.blue) {
                BatchFormFields(form: $form,
                                errors: errors,
                                zones: store.household?.activeZones ?? [],
                                currency: store.currency)
            }

            OceanButton(title: "Save Item", symbol: "checkmark", isBusy: isSaving) { save() }
            OceanButton(title: "Back", kind: .ghost) { mode = .chooser }
        }
    }

    // MARK: - Saved

    @ViewBuilder
    private var savedSection: some View {
        if let batch = savedBatch {
            VStack(alignment: .leading, spacing: 18) {
                WaveCard(tint: Ocean.turquoise, padding: 22) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 14) {
                            FloatDisc(symbol: "checkmark", tint: Ocean.turquoise, size: 52)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Saved").font(OceanFont.title(20)).foregroundStyle(Ocean.ink)
                                Text(batch.displayTitle)
                                    .font(OceanFont.caption(12.5)).foregroundStyle(Ocean.inkSoft)
                            }
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            savedRow("On hand", Format.measure(batch.remaining, batch.unit))
                            savedRow("Storage", store.zoneName(batch.zoneID) ?? "No zone")
                            savedRow("Your date", batch.bestBefore.map(DateFormat.day) ?? "Not set")
                            savedRow("Price", store.money(batch.price) ?? "Not recorded")
                        }
                        Text("Home, Inventory and Insights already read this batch. Nothing was copied — they all point at the same record.")
                            .font(OceanFont.caption(11.5)).foregroundStyle(Ocean.inkSoft)
                    }
                }

                OceanButton(title: "Scan Another", symbol: "barcode.viewfinder") {
                    resetForNext()
                }
                OceanButton(title: "Add Another by Hand", symbol: "square.and.pencil",
                            kind: .secondary, tint: Ocean.turquoise) {
                    resetForNext(scanning: false)
                }
                OceanButton(title: "Done", kind: .ghost) { dismiss() }
            }
        }
    }

    private func savedRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(OceanFont.caption(12)).foregroundStyle(Ocean.inkSoft)
            Spacer()
            Text(value).font(OceanFont.headline(14)).foregroundStyle(Ocean.ink)
        }
    }

    // MARK: - Actions

    private func lookup(barcode: String) async {
        let clean = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        lookupState = .loading(clean)
        let outcome = await lookupService.lookup(barcode: clean, isOnline: network.isOnline)
        switch outcome {
        case .found(let result):
            lookupState = .found(result)
            Haptics.success()
        case .notFound(let code):
            lookupState = .notFound(code)
        case .offline:
            lookupState = .offline(clean)
        case .failed(let message):
            lookupState = .failed(message, barcode: clean)
        }
    }

    private func apply(_ result: ProductLookupResult) {
        form.barcode = result.barcode
        if let name = result.name { form.name = name }
        if let brand = result.brand { form.brand = brand }
        form.reference = result.hint
        mode = .form
        lookupState = .idle
    }

    private func prefill(from batch: Batch) {
        form.name = batch.productName
        form.brand = batch.brand ?? ""
        form.unit = batch.unit
        form.zoneID = batch.zoneID
        form.barcode = batch.barcode ?? ""
        mode = .form
    }

    private func save() {
        guard !isSaving else { return }
        errors = form.validate()
        guard errors.isEmpty else {
            Haptics.warning()
            toast = ToastMessage(kind: .warning, title: "Check the highlighted fields",
                                 detail: "Nothing was saved, and your input was kept.")
            return
        }
        isSaving = true
        defer { isSaving = false }

        var working = form
        if let data = working.photoData, working.photoFilename == nil {
            working.photoFilename = try? PersistenceController.shared.savePhoto(data)
        }
        let origin: BatchOrigin = working.barcode.isEmpty ? .manual : .scan
        do {
            let saved = try store.addBatch(working.makeBatch(origin: origin))
            store.rebuildRecallMatches()
            savedBatch = saved
            mode = .saved
            Haptics.success()
        } catch {
            toast = ToastMessage(kind: .warning, title: "Not saved", detail: error.localizedDescription)
            Haptics.warning()
        }
    }

    private func resetForNext(scanning: Bool = true) {
        var next = BatchForm()
        next.zoneID = form.zoneID
        next.unit = form.unit
        next.store = form.store
        next.purchaseDate = form.purchaseDate
        form = next
        errors = [:]
        savedBatch = nil
        lookupState = .idle
        mode = scanning ? .scanning : .form
    }

    private func attemptDismiss() {
        if mode == .form && form.hasContent {
            showDiscardPrompt = true
        } else {
            dismiss()
        }
    }
}
