//
//  BatchForm.swift
//  Ocean Cast
//
//  Shared editing model for a batch. Used when adding an item and when editing
//  one later, so both paths validate identically.
//

import SwiftUI
import PhotosUI

struct BatchForm {
    var name = ""
    var brand = ""
    var barcode = ""
    var batchCode = ""
    var quantityText = "1"
    var unit: MeasureUnit = .piece
    var purchaseDate: Date? = Calendar.current.startOfDay(for: Date())
    var bestBefore: Date?
    var zoneID: UUID?
    var priceText = ""
    var store = ""
    var notes = ""
    var opened = false
    var photoData: Data?
    var photoFilename: String?
    var reference: ReferenceHint?

    var hasContent: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            || !brand.isEmpty || !barcode.isEmpty || !priceText.isEmpty
            || !notes.isEmpty || photoData != nil
    }

    func validate() -> [String: String] {
        var errors: [String: String] = [:]
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors["name"] = "Product name is required."
        }
        guard let quantity = Parse.double(quantityText) else {
            errors["quantity"] = "Enter a quantity."
            return errors
        }
        if quantity <= 0 { errors["quantity"] = "Quantity must be greater than 0." }
        if !priceText.isEmpty {
            if let price = Parse.double(priceText) {
                if price < 0 { errors["price"] = "Price cannot be negative." }
            } else {
                errors["price"] = "Price must be a number, or left empty."
            }
        }
        if let bestBefore, let purchaseDate, bestBefore < purchaseDate {
            errors["bestBefore"] = "Your date is before the purchase date. Check it once more."
        }
        return errors
    }

    func makeBatch(origin: BatchOrigin, existing: Batch? = nil) -> Batch {
        var batch = existing ?? Batch(productName: "", quantity: 1, remaining: 1, unit: .piece)
        batch.productName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        batch.brand = brand.nilIfBlank
        batch.barcode = barcode.nilIfBlank
        batch.batchCode = batchCode.nilIfBlank
        batch.quantity = Parse.double(quantityText) ?? 0
        batch.unit = unit
        batch.purchaseDate = purchaseDate
        batch.bestBefore = bestBefore
        batch.zoneID = zoneID
        batch.price = priceText.isEmpty ? nil : Parse.double(priceText)
        batch.store = store.nilIfBlank
        batch.notes = notes.nilIfBlank
        batch.opened = opened
        batch.reference = reference
        batch.photoFilename = photoFilename
        if existing == nil { batch.origin = origin }
        return batch
    }

    static func from(_ batch: Batch) -> BatchForm {
        var form = BatchForm()
        form.name = batch.productName
        form.brand = batch.brand ?? ""
        form.barcode = batch.barcode ?? ""
        form.batchCode = batch.batchCode ?? ""
        form.quantityText = Format.quantity(batch.quantity)
        form.unit = batch.unit
        form.purchaseDate = batch.purchaseDate
        form.bestBefore = batch.bestBefore
        form.zoneID = batch.zoneID
        form.priceText = batch.price.map(Format.quantity) ?? ""
        form.store = batch.store ?? ""
        form.notes = batch.notes ?? ""
        form.opened = batch.opened
        form.photoFilename = batch.photoFilename
        form.photoData = PersistenceController.shared.photoData(batch.photoFilename)
        form.reference = batch.reference
        return form
    }
}

/// The full field set, reused by Add and Edit.
struct BatchFormFields: View {
    @Binding var form: BatchForm
    var errors: [String: String]
    var zones: [StorageZone]
    var currency: String
    var tint: Color = Ocean.blue
    var showBarcodeField = true

    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            OceanTextField(label: "Product name", placeholder: "Greek yoghurt",
                           required: true, error: errors["name"], text: $form.name)

            HStack(alignment: .top, spacing: 12) {
                OceanTextField(label: "Brand", placeholder: "optional", text: $form.brand)
                if showBarcodeField {
                    OceanTextField(label: "Barcode", placeholder: "optional",
                                   keyboard: .number, text: $form.barcode)
                }
            }

            HStack(alignment: .top, spacing: 12) {
                QuantityStepperField(label: "Quantity", error: errors["quantity"],
                                     text: $form.quantityText, tint: tint)
                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel(text: "Unit", required: true)
                    Menu {
                        ForEach(MeasureUnit.allCases) { unit in
                            Button {
                                form.unit = unit
                            } label: {
                                Label("\(unit.title) (\(unit.short))",
                                      systemImage: form.unit == unit ? "checkmark" : "")
                            }
                        }
                    } label: {
                        HStack {
                            Text(form.unit.short)
                                .font(OceanFont.headline(16))
                                .foregroundStyle(Ocean.ink)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Ocean.inkFaint)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: OceanRadius.chip, style: .continuous)
                                .fill(Ocean.foam.opacity(0.8))
                                .overlay(RoundedRectangle(cornerRadius: OceanRadius.chip, style: .continuous)
                                    .strokeBorder(tint.opacity(0.25), lineWidth: 1.4))
                        )
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                FieldLabel(text: "Storage zone")
                if zones.isEmpty {
                    Text("No active zones. Add one in Household Setup — items can still be saved without a zone.")
                        .font(OceanFont.caption(11.5))
                        .foregroundStyle(Ocean.coral)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            OceanChip(title: "No zone", tint: tint, isOn: form.zoneID == nil) {
                                form.zoneID = nil
                            }
                            ForEach(zones) { zone in
                                OceanChip(title: zone.name, symbol: zone.kind.symbol,
                                          tint: tint, isOn: form.zoneID == zone.id) {
                                    form.zoneID = zone.id
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            OptionalDateField(label: "Purchase date", date: $form.purchaseDate, tint: tint)

            VStack(alignment: .leading, spacing: 6) {
                OptionalDateField(label: "Best before (your date)",
                                  note: "This is your own date. Ocean Cast does not decide when food is unsafe.",
                                  date: $form.bestBefore, tint: tint)
                if let error = errors["bestBefore"] {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(OceanFont.caption(11.5))
                        .foregroundStyle(Ocean.coral)
                }
                if let reference = form.reference, let hint = reference.shelfLifeDaysHint {
                    Text("Catalogue hint: about \(hint) days after packaging — stored separately from your date.")
                        .font(OceanFont.caption(11))
                        .foregroundStyle(Ocean.inkSoft)
                }
            }

            HStack(alignment: .top, spacing: 12) {
                OceanTextField(label: "Price (\(currency))", placeholder: "optional",
                               error: errors["price"], keyboard: .decimal, text: $form.priceText)
                OceanTextField(label: "Store", placeholder: "optional", text: $form.store)
            }

            OceanTextField(label: "Batch / lot code", placeholder: "helps recall checks", text: $form.batchCode)

            Toggle(isOn: $form.opened) {
                Text("Already opened").font(OceanFont.body(14.5)).foregroundStyle(Ocean.ink)
            }
            .tint(tint)

            photoField

            OceanTextField(label: "Notes", placeholder: "optional", text: $form.notes)

            if let reference = form.reference {
                SourceStampView(source: reference.sourceName,
                                updated: reference.fetchedAt,
                                url: reference.sourceURL.flatMap(URL.init(string:)))
            }
        }
    }

    private var photoField: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: "Photo")
            HStack(spacing: 12) {
                #if os(iOS)
                if let data = form.photoData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable().scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(tint.opacity(0.3), lineWidth: 1.2))
                }
                #endif
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(form.photoData == nil ? "Add photo" : "Replace photo", systemImage: "camera.fill")
                        .font(OceanFont.caption(13))
                }
                .buttonStyle(OceanButtonStyle(kind: .secondary, tint: tint, fullWidth: false, compact: true))

                if form.photoData != nil {
                    Button {
                        form.photoData = nil
                        form.photoFilename = nil
                    } label: {
                        Image(systemName: "trash.fill").foregroundStyle(Ocean.coral)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    form.photoData = data
                }
            }
        }
    }
}
