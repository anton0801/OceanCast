//
//  HouseholdSetupView.swift
//  Ocean Cast
//
//  SCREEN 2 — Household, members, storage zones and shopping preferences.
//

import SwiftUI

struct HouseholdSetupView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @AppStorage("draft.householdName") private var draftName = ""
    @AppStorage("draft.currency") private var draftCurrency = Locale.current.currency?.identifier ?? "USD"

    @State private var name = ""
    @State private var currency = "USD"
    @State private var nameError: String?
    @State private var isSaving = false
    @State private var toast: ToastMessage?

    @State private var memberName = ""
    @State private var memberEmail = ""
    @State private var memberRole: Member.Role = .adult
    @State private var memberError: String?

    @State private var zoneName = ""
    @State private var zoneKind: StorageZone.Kind = .pantry
    @State private var zoneError: String?

    @State private var preferences = ShoppingPreferences()
    @State private var lowStockText = ""
    @State private var zoneToArchive: StorageZone?

    private var isNew: Bool { store.household == nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ScreenHeader(eyebrow: isNew ? "Setup" : "Household",
                                 title: isNew ? "Create Your Household" : (store.household?.name ?? "Household"),
                                 subtitle: isNew
                                    ? "Zones, currency and members are used by every other screen."
                                    : "Changing this updates every screen that reads from it.",
                                 tint: Ocean.coral)

                    basicsCard
                    if !isNew {
                        membersCard
                        zonesCard
                        preferencesCard
                        dangerCard
                    }
                }
                .padding(20)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .background(OceanBackground(tint: Ocean.coral))
            .toastHost($toast)
            .navigationTitle("Household Setup")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Create" : "Save Setup") { save() }
                        .font(OceanFont.headline(15))
                        .disabled(isSaving)
                }
            }
            .onAppear(perform: load)
            .alert(item: $zoneToArchive) { zone in
                Alert(
                    title: Text("Archive “\(zone.name)”?"),
                    message: Text(archiveMessage(for: zone)),
                    primaryButton: .default(Text("Archive")) {
                        store.archiveZone(zone.id, moveTo: nil)
                        toast = ToastMessage(kind: .info, title: "Zone archived",
                                             detail: "Items kept their history and are now without a zone.")
                    },
                    secondaryButton: .cancel(Text("Keep zone"))
                )
            }
        }
    }

    private func archiveMessage(for zone: StorageZone) -> String {
        let count = store.batchCount(inZone: zone.id)
        if count == 0 { return "No items are stored here. You can restore the zone later." }
        return "\(count) item(s) are stored here. They will stay in Inventory with no zone, keep their history, and you can move them later. The zone can be restored."
    }

    // MARK: - Cards

    private var basicsCard: some View {
        SectionCard(title: "Basics", symbol: "house.fill", tint: Ocean.coral) {
            VStack(alignment: .leading, spacing: 14) {
                OceanTextField(label: "Household name", placeholder: "Our Kitchen",
                               required: true, error: nameError, text: $name)
                    .onChange(of: name) { _, newValue in
                        if isNew { draftName = newValue }
                        if nameError != nil && !newValue.trimmingCharacters(in: .whitespaces).isEmpty { nameError = nil }
                    }

                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel(text: "Default currency")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(CurrencyOptions.suggested, id: \.self) { code in
                                OceanChip(title: code, tint: Ocean.coral, isOn: currency == code) {
                                    currency = code
                                    if isNew { draftCurrency = code }
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    Text("Prices you record are stored in this currency. Existing records keep the currency they were entered with.")
                        .font(OceanFont.caption(11))
                        .foregroundStyle(Ocean.inkSoft)
                }

                if isNew {
                    InfoNote(text: "Creating a household also adds three storage zones — Pantry, Fridge and Freezer. Rename or archive them at any time.",
                             tint: Ocean.coral)
                }
            }
        }
    }

    private var membersCard: some View {
        SectionCard(title: "Members", symbol: "person.2.fill", tint: Ocean.tide) {
            VStack(alignment: .leading, spacing: 14) {
                if let household = store.household, !household.members.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(household.members) { member in
                            HStack(spacing: 12) {
                                FloatDisc(symbol: "person.fill",
                                          tint: member.removed ? Ocean.inkFaint : Ocean.tide, size: 34)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.name)
                                        .font(OceanFont.headline(15))
                                        .foregroundStyle(member.removed ? Ocean.inkFaint : Ocean.ink)
                                        .strikethrough(member.removed)
                                    Text(member.removed ? "Removed — their history was kept" : member.role.title)
                                        .font(OceanFont.caption(11.5))
                                        .foregroundStyle(Ocean.inkSoft)
                                }
                                Spacer()
                                if member.removed {
                                    Button("Restore") { store.restoreMember(member.id) }
                                        .font(OceanFont.caption(12))
                                        .foregroundStyle(Ocean.turquoise)
                                } else {
                                    Button("Remove") { store.removeMember(member.id) }
                                        .font(OceanFont.caption(12))
                                        .foregroundStyle(Ocean.coral)
                                }
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Ocean.foam.opacity(0.7)))
                        }
                    }
                } else {
                    Text("No members yet. You can use Ocean Cast alone — members only help you see who recorded what.")
                        .font(OceanFont.body(14))
                        .foregroundStyle(Ocean.inkSoft)
                }

                VStack(alignment: .leading, spacing: 10) {
                    OceanTextField(label: "Name", placeholder: "Alex", error: memberError, text: $memberName)
                    OceanTextField(label: "Email (optional)", placeholder: "alex@example.com",
                                   keyboard: .email, text: $memberEmail)
                    HStack(spacing: 8) {
                        ForEach(Member.Role.allCases) { role in
                            OceanChip(title: role.title, tint: Ocean.tide, isOn: memberRole == role) {
                                memberRole = role
                            }
                        }
                    }
                    OceanButton(title: "Add Member", symbol: "person.badge.plus",
                                kind: .secondary, tint: Ocean.tide) {
                        addMember()
                    }
                }
            }
        }
    }

    private var zonesCard: some View {
        SectionCard(title: "Storage Zones", symbol: "square.grid.2x2.fill", tint: Ocean.turquoise) {
            VStack(alignment: .leading, spacing: 14) {
                if let household = store.household {
                    VStack(spacing: 8) {
                        ForEach(household.zones) { zone in
                            HStack(spacing: 12) {
                                FloatDisc(symbol: zone.kind.symbol,
                                          tint: zone.archived ? Ocean.inkFaint : Ocean.turquoise, size: 34)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(zone.name)
                                        .font(OceanFont.headline(15))
                                        .foregroundStyle(zone.archived ? Ocean.inkFaint : Ocean.ink)
                                    Text(zone.archived
                                         ? "Archived"
                                         : "\(store.batchCount(inZone: zone.id)) active item(s)")
                                        .font(OceanFont.caption(11.5))
                                        .foregroundStyle(Ocean.inkSoft)
                                }
                                Spacer()
                                if zone.archived {
                                    Button("Restore") { store.restoreZone(zone.id) }
                                        .font(OceanFont.caption(12))
                                        .foregroundStyle(Ocean.turquoise)
                                } else {
                                    Button("Archive") { zoneToArchive = zone }
                                        .font(OceanFont.caption(12))
                                        .foregroundStyle(Ocean.coral)
                                }
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Ocean.foam.opacity(0.7)))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    OceanTextField(label: "Zone name", placeholder: "Garage shelf",
                                   error: zoneError, text: $zoneName)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(StorageZone.Kind.allCases) { kind in
                                OceanChip(title: kind.title, symbol: kind.symbol,
                                          tint: Ocean.turquoise, isOn: zoneKind == kind) {
                                    zoneKind = kind
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    OceanButton(title: "Add Storage Zone", symbol: "plus",
                                kind: .secondary, tint: Ocean.turquoise) {
                        addZone()
                    }
                }
            }
        }
    }

    private var preferencesCard: some View {
        SectionCard(title: "Shopping Preferences", symbol: "cart.fill", tint: Ocean.sky) {
            VStack(alignment: .leading, spacing: 14) {
                OceanTextField(label: "Default store", placeholder: "Corner Market",
                               text: Binding(get: { preferences.defaultStore },
                                             set: { preferences.defaultStore = $0 }))

                Toggle(isOn: Binding(get: { preferences.groupByStore },
                                     set: { preferences.groupByStore = $0 })) {
                    Text("Group the shopping list by store")
                        .font(OceanFont.body(14.5))
                        .foregroundStyle(Ocean.ink)
                }
                .tint(Ocean.turquoise)

                OceanField(label: "Expiry window (days)", tint: Ocean.sky) {
                    Stepper(value: Binding(get: { preferences.expiryWindowDays },
                                           set: { preferences.expiryWindowDays = $0 }), in: 1...30) {
                        Text("\(preferences.expiryWindowDays) day(s) before your date")
                            .font(OceanFont.body(14.5))
                            .foregroundStyle(Ocean.ink)
                    }
                }

                OceanTextField(label: "Default low-stock threshold (optional)",
                               placeholder: "leave empty to keep low stock uncomputed",
                               keyboard: .decimal, text: $lowStockText)
                Text("Without a threshold, Home shows “—” for low stock instead of guessing that empty means zero.")
                    .font(OceanFont.caption(11))
                    .foregroundStyle(Ocean.inkSoft)

                OceanButton(title: "Save Preferences", symbol: "checkmark",
                            kind: .secondary, tint: Ocean.sky) {
                    savePreferences()
                }
            }
        }
    }

    private var dangerCard: some View {
        WaveCard(tint: Ocean.coral) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Deleting the household")
                    .font(OceanFont.headline(15))
                    .foregroundStyle(Ocean.ink)
                Text("Deleting removes \(store.data.batches.count) batch(es), \(store.data.meals.count) meal(s) and \(store.data.shopping.count) shopping line(s). It lives in Settings & Data, behind a second confirmation.")
                    .font(OceanFont.caption(12))
                    .foregroundStyle(Ocean.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Actions

    private func load() {
        if let household = store.household {
            name = household.name
            currency = household.currencyCode
            preferences = household.preferences
            lowStockText = household.preferences.defaultLowStockThreshold.map(Format.quantity) ?? ""
        } else {
            name = draftName
            currency = draftCurrency
        }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            if isNew {
                try store.createHousehold(name: name, currency: currency)
                draftName = ""
                Haptics.success()
                dismiss()
            } else {
                try store.updateHousehold(name: name, currency: currency)
                Haptics.success()
                toast = ToastMessage(title: "Household saved", detail: "Name and currency updated everywhere.")
            }
        } catch {
            nameError = error.localizedDescription
            Haptics.warning()
        }
    }

    private func addMember() {
        do {
            try store.addMember(name: memberName,
                                email: memberEmail.isEmpty ? nil : memberEmail,
                                role: memberRole)
            memberName = ""
            memberEmail = ""
            memberError = nil
            Haptics.success()
            toast = ToastMessage(title: "Member added")
        } catch {
            memberError = error.localizedDescription
            Haptics.warning()
        }
    }

    private func addZone() {
        do {
            try store.addZone(name: zoneName, kind: zoneKind)
            zoneName = ""
            zoneError = nil
            Haptics.success()
            toast = ToastMessage(title: "Storage zone added")
        } catch {
            zoneError = error.localizedDescription
            Haptics.warning()
        }
    }

    private func savePreferences() {
        var updated = preferences
        updated.defaultLowStockThreshold = Parse.double(lowStockText)
        store.updatePreferences(updated)
        preferences = updated
        Haptics.success()
        toast = ToastMessage(title: "Preferences saved",
                             detail: updated.defaultLowStockThreshold == nil
                                ? "Low stock stays uncomputed until a threshold exists."
                                : "Low stock now uses \(Format.quantity(updated.defaultLowStockThreshold!)) as the default threshold.")
    }
}
