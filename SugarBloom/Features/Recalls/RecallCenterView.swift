//
//  RecallCenterView.swift
//  Ocean Cast
//
//  SCREEN 12 — Official notices, matched locally against your batches.
//  The app never decides that a notice involves your item — you confirm it.
//

import SwiftUI

struct RecallCenterView: View {
    @Environment(AppStore.self) private var store
    @Environment(Navigator.self) private var navigator
    @Environment(NetworkMonitor.self) private var network

    enum FetchState: Equatable {
        case idle, loading, failed(String), offline
    }

    @State private var fetchState: FetchState = .idle
    @State private var toast: ToastMessage?
    @State private var showArchived = false

    private let service = RecallService()

    private var pendingMatches: [RecallMatch] { store.unconfirmedRecallMatches }

    private var alertsWithMatches: [RecallAlert] {
        let ids = Set(store.data.recallMatches.map(\.alertID))
        return store.visibleAlerts.filter { ids.contains($0.id) }
    }

    private var otherAlerts: [RecallAlert] {
        let ids = Set(alertsWithMatches.map(\.id))
        return store.visibleAlerts.filter { !ids.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(eyebrow: "Recall Center",
                             title: pendingMatches.isEmpty ? "Recall alerts" : "\(pendingMatches.count) need your check",
                             subtitle: "Notices come from the U.S. FDA enforcement feed. Matching happens on this device and always tells you why.",
                             tint: Ocean.coral)

                if !network.isOnline {
                    OfflineBanner(lastUpdated: store.data.recallLastCheckedAt)
                }

                sourceCard

                if store.data.batches.isEmpty {
                    EmptyStateCard(symbol: "shippingbox.fill",
                                   title: "Nothing to match yet",
                                   message: "Recall matching compares notices with your own batches — brand, barcode, lot code and product words. Add an item first.",
                                   actionTitle: "Add an item",
                                   tint: Ocean.tide) {
                        navigator.sheet = .addProduct(barcode: nil)
                    }
                } else if store.data.recallAlerts.isEmpty {
                    EmptyStateCard(symbol: "shield.lefthalf.filled",
                                   title: "No notices downloaded yet",
                                   message: network.isOnline
                                    ? "Nothing is shown until real notices are fetched. Use Check for notices above — Ocean Cast never invents an alert or an instruction."
                                    : "No notices have been downloaded on this device yet, and there is no connection to fetch them now.",
                                   tint: Ocean.turquoise)
                } else {
                    if !alertsWithMatches.isEmpty {
                        Text("Possible matches in your kitchen")
                            .font(OceanFont.headline(15)).foregroundStyle(Ocean.ink)
                        ForEach(alertsWithMatches) { alert in
                            RecallCard(alert: alert,
                                       matches: store.matches(for: alert.id),
                                       onOpen: { navigator.push(.recallDetail(alert.id)) })
                        }
                    }

                    if !otherAlerts.isEmpty {
                        Text("Other recent notices")
                            .font(OceanFont.headline(15)).foregroundStyle(Ocean.ink)
                            .padding(.top, 4)
                        ForEach(otherAlerts.prefix(12)) { alert in
                            RecallCard(alert: alert,
                                       matches: [],
                                       onOpen: { navigator.push(.recallDetail(alert.id)) })
                        }
                        if otherAlerts.count > 12 {
                            Text("\(otherAlerts.count - 12) more notice(s) downloaded and stored locally.")
                                .font(OceanFont.caption(11)).foregroundStyle(Ocean.inkFaint)
                        }
                    }
                }

                if !store.data.archivedAlerts.isEmpty { archivedSection }

                InfoNote(text: "This feed covers U.S. FDA food enforcement reports. It does not cover every country or every product, so it cannot be treated as a complete safety check.",
                         symbol: "exclamationmark.circle.fill", tint: Ocean.tide)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(OceanBackground(tint: Ocean.coral))
        .toastHost($toast)
        .navigationTitle("Alerts")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .oceanTabInset()
    }

    private var sourceCard: some View {
        WaveCard(tint: Ocean.turquoise) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    FloatDisc(symbol: "antenna.radiowaves.left.and.right", tint: Ocean.turquoise, size: 38)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Official source")
                            .font(OceanFont.headline(15)).foregroundStyle(Ocean.ink)
                        Text(RecallService.sourceName)
                            .font(OceanFont.caption(11.5)).foregroundStyle(Ocean.inkSoft)
                    }
                    Spacer(minLength: 0)
                }

                SourceStampView(source: RecallService.sourceName,
                                updated: store.data.recallLastCheckedAt,
                                isCached: !network.isOnline,
                                url: RecallService.sourceURL)

                switch fetchState {
                case .loading:
                    LoadingCard(message: "Fetching the latest notices…")
                case .failed(let message):
                    ErrorCard(title: "Could not reach the source", message: message,
                              onRetry: { Task { await fetch() } })
                case .offline:
                    Text("You are offline. The list below is the local snapshot from \(store.data.recallLastCheckedAt.map(DateFormat.stamp) ?? "an earlier session") — it is not live.")
                        .font(OceanFont.caption(11.5)).foregroundStyle(Ocean.coral)
                case .idle:
                    EmptyView()
                }

                OceanButton(title: "Check for notices", symbol: "arrow.clockwise",
                            kind: .secondary, tint: Ocean.turquoise,
                            isBusy: fetchState == .loading) {
                    Task { await fetch() }
                }
            }
        }
    }

    private var archivedSection: some View {
        SectionCard(title: "Archived notices", symbol: "archivebox.fill", tint: Ocean.inkFaint,
                    accessory: {
            Button(showArchived ? "Hide" : "Show") { withAnimation(OceanMotion.pop) { showArchived.toggle() } }
                .font(OceanFont.caption(12))
                .foregroundStyle(Ocean.turquoise)
        }, content: {
            VStack(alignment: .leading, spacing: 8) {
                if showArchived {
                    ForEach(store.data.archivedAlerts) { archived in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(store.alert(archived.alertID)?.title ?? archived.alertID)
                                    .font(OceanFont.headline(14)).foregroundStyle(Ocean.inkSoft)
                                    .lineLimit(2)
                                Text("Reason: \(archived.reason) · \(DateFormat.day(archived.archivedAt))")
                                    .font(OceanFont.caption(10.5)).foregroundStyle(Ocean.inkFaint)
                            }
                            Spacer()
                            Button("Restore") {
                                store.restoreAlert(alertID: archived.alertID)
                                toast = ToastMessage(kind: .info, title: "Notice restored")
                            }
                            .font(OceanFont.caption(12))
                            .foregroundStyle(Ocean.turquoise)
                        }
                    }
                } else {
                    Text("\(store.data.archivedAlerts.count) notice(s) archived with a reason.")
                        .font(OceanFont.caption(12)).foregroundStyle(Ocean.inkSoft)
                }
            }
        })
    }

    private func fetch() async {
        fetchState = .loading
        let outcome = await service.fetchLatest(isOnline: network.isOnline)
        switch outcome {
        case .success(let alerts):
            store.ingestAlerts(alerts)
            fetchState = .idle
            Haptics.success()
            let pending = store.unconfirmedRecallMatches.count
            toast = ToastMessage(title: "\(alerts.count) notice(s) received",
                                 detail: pending == 0
                                    ? "Nothing matched your batches. Nothing was hidden — open any notice to read it."
                                    : "\(pending) possible match(es) need your check.")
        case .offline:
            fetchState = .offline
        case .failed(let message):
            fetchState = .failed(message)
            Haptics.warning()
        }
    }
}

// MARK: - Card

private struct RecallCard: View {
    var alert: RecallAlert
    var matches: [RecallMatch]
    var onOpen: () -> Void

    private var pending: Int { matches.filter { $0.decision == .unconfirmed }.count }

    private var tint: Color {
        if pending > 0 { return Ocean.blue }
        if alert.isCritical { return Ocean.coral }
        return Ocean.turquoise
    }

    var body: some View {
        Button(action: onOpen) {
            WaveCard(tint: tint, padding: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        FloatDisc(symbol: pending > 0 ? "exclamationmark.shield.fill" : "shield.fill",
                                  tint: tint, size: 40)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(alert.title)
                                .font(OceanFont.headline(15))
                                .foregroundStyle(Ocean.ink)
                                .multilineTextAlignment(.leading)
                                .lineLimit(3)
                            if let firm = alert.firmName {
                                Text(firm).font(OceanFont.caption(11.5)).foregroundStyle(Ocean.inkSoft)
                            }
                            HStack(spacing: 6) {
                                if let classification = alert.classification {
                                    Text(classification)
                                        .font(OceanFont.caption(10))
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Capsule().fill(tint.opacity(0.16)))
                                        .foregroundStyle(tint)
                                }
                                if let date = alert.reportedAt {
                                    Text(DateFormat.day(date))
                                        .font(OceanFont.caption(10.5))
                                        .foregroundStyle(Ocean.inkFaint)
                                }
                            }
                        }
                        Spacer(minLength: 0)
                        RowChevron()
                    }

                    if pending > 0 {
                        Text("\(pending) of your batch(es) may be involved — only you can confirm the batch.")
                            .font(OceanFont.caption(11.5)).foregroundStyle(Ocean.blue)
                    } else if !matches.isEmpty {
                        Text(matches.map { $0.decision.title }.joined(separator: " · "))
                            .font(OceanFont.caption(11)).foregroundStyle(Ocean.inkSoft)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Detail

struct RecallDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(Navigator.self) private var navigator
    @Environment(\.dismiss) private var dismiss

    var alertID: String

    @State private var showArchive = false
    @State private var archiveReason = ""
    @State private var toast: ToastMessage?

    private let archiveReasons = ["Checked — none of my items match",
                                  "Followed the official guidance",
                                  "Not sold in my country",
                                  "Already discarded the item"]

    private var alert: RecallAlert? { store.alert(alertID) }

    var body: some View {
        ScrollView {
            if let alert {
                VStack(alignment: .leading, spacing: 16) {
                    header(alert)
                    detailsCard(alert)
                    matchesCard(alert)
                    guidanceCard(alert)
                    archiveCard(alert)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            } else {
                EmptyStateCard(symbol: "questionmark.folder.fill",
                               title: "Notice not found",
                               message: "It may have been removed when data was re-imported.",
                               actionTitle: "Back",
                               tint: Ocean.coral) { dismiss() }
                    .padding(20)
            }
        }
        .scrollIndicators(.hidden)
        .background(OceanBackground(tint: Ocean.coral))
        .toastHost($toast)
        .navigationTitle("Recall Notice")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .oceanTabInset()
    }

    private func header(_ alert: RecallAlert) -> some View {
        WaveCard(tint: alert.isCritical ? Ocean.blue : Ocean.coral, padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    FloatDisc(symbol: "exclamationmark.shield.fill",
                              tint: alert.isCritical ? Ocean.blue : Ocean.coral, size: 46)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(alert.title)
                            .font(OceanFont.title(18)).foregroundStyle(Ocean.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if let firm = alert.firmName {
                            Text(firm).font(OceanFont.caption(12)).foregroundStyle(Ocean.inkSoft)
                        }
                    }
                    Spacer(minLength: 0)
                }
                SourceStampView(source: alert.sourceName,
                                updated: alert.fetchedAt,
                                url: alert.sourceURL.flatMap(URL.init(string:)))
                Text("Notice number \(alert.id)")
                    .font(OceanFont.caption(10.5)).foregroundStyle(Ocean.inkFaint)
            }
        }
    }

    private func detailsCard(_ alert: RecallAlert) -> some View {
        SectionCard(title: "What the notice says", symbol: "doc.text.fill", tint: Ocean.tide) {
            VStack(alignment: .leading, spacing: 12) {
                labelled("Product", alert.productDescription)
                if let reason = alert.reason { labelled("Reason given", reason) }
                if let classification = alert.classification { labelled("Classification", classification) }
                if let status = alert.status { labelled("Status", status) }
                if let distribution = alert.distribution { labelled("Distribution", distribution) }
                if let date = alert.reportedAt { labelled("Reported", DateFormat.day(date)) }

                if !alert.codes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Codes quoted by the notice")
                            .font(OceanFont.caption(11)).foregroundStyle(Ocean.inkSoft)
                        Text(alert.codes.prefix(24).joined(separator: ", "))
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(Ocean.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if alert.codes.count > 24 {
                            Text("+\(alert.codes.count - 24) more in the original notice")
                                .font(OceanFont.caption(10.5)).foregroundStyle(Ocean.inkFaint)
                        }
                    }
                }

                Text("This text is reproduced from the source. Ocean Cast adds no interpretation of its own.")
                    .font(OceanFont.caption(10.5)).foregroundStyle(Ocean.inkFaint)
            }
        }
    }

    private func labelled(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(OceanFont.caption(11)).foregroundStyle(Ocean.inkSoft)
            Text(value)
                .font(OceanFont.body(14))
                .foregroundStyle(Ocean.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func matchesCard(_ alert: RecallAlert) -> some View {
        let matches = store.matches(for: alert.id)
        return SectionCard(title: "Check My Item", symbol: "magnifyingglass", tint: Ocean.turquoise) {
            VStack(alignment: .leading, spacing: 12) {
                if matches.isEmpty {
                    Text("None of your batches share a barcode, brand, lot code or product word with this notice. That is not a guarantee — compare the codes above with the packaging yourself.")
                        .font(OceanFont.body(14)).foregroundStyle(Ocean.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(matches) { match in
                        if let batch = store.batch(match.batchID) {
                            VStack(alignment: .leading, spacing: 10) {
                                Button {
                                    navigator.push(.product(batch.id))
                                } label: {
                                    HStack(spacing: 10) {
                                        FloatDisc(symbol: "shippingbox.fill", tint: Ocean.turquoise, size: 32)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(batch.displayTitle)
                                                .font(OceanFont.headline(14)).foregroundStyle(Ocean.ink)
                                            Text(match.reason)
                                                .font(OceanFont.caption(11)).foregroundStyle(Ocean.inkSoft)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        Spacer()
                                        RowChevron()
                                    }
                                }
                                .buttonStyle(.plain)

                                HStack(spacing: 8) {
                                    OceanChip(title: "It is my batch", symbol: "checkmark",
                                              tint: Ocean.blue,
                                              isOn: match.decision == .confirmed) {
                                        store.setRecallDecision(alertID: alert.id, batchID: batch.id,
                                                                decision: .confirmed)
                                        Haptics.warning()
                                        toast = ToastMessage(kind: .warning, title: "Match confirmed",
                                                             detail: "Follow the official guidance below.")
                                    }
                                    OceanChip(title: "Mark Not a Match", symbol: "xmark",
                                              tint: Ocean.turquoise,
                                              isOn: match.decision == .notAMatch) {
                                        store.setRecallDecision(alertID: alert.id, batchID: batch.id,
                                                                decision: .notAMatch)
                                        Haptics.success()
                                        toast = ToastMessage(kind: .info, title: "Recorded as not a match")
                                    }
                                }

                                if match.decision != .unconfirmed, let decided = match.decidedAt {
                                    Text("\(match.decision.title) on \(DateFormat.stamp(decided))")
                                        .font(OceanFont.caption(10.5)).foregroundStyle(Ocean.inkFaint)
                                }
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Ocean.foam.opacity(0.75)))
                        }
                    }
                }
            }
        }
    }

    private func guidanceCard(_ alert: RecallAlert) -> some View {
        SectionCard(title: "Follow Official Guidance", symbol: "arrow.up.right.square.fill", tint: Ocean.sky) {
            VStack(alignment: .leading, spacing: 12) {
                Text("What to do with a recalled product is decided by the authority and the company — not by this app. Open the official page for the current instruction.")
                    .font(OceanFont.body(14)).foregroundStyle(Ocean.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Link(destination: alert.sourceURL.flatMap(URL.init(string:)) ?? RecallService.officialGuidanceURL) {
                    HStack(spacing: 8) {
                        Image(systemName: "safari.fill")
                        Text("Open official guidance")
                    }
                    .font(OceanFont.headline(15))
                    .foregroundStyle(Ocean.ink)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(Capsule().fill(OceanGradient.cta))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.5), lineWidth: 1.2))
                }
            }
        }
    }

    private func archiveCard(_ alert: RecallAlert) -> some View {
        SectionCard(title: "Archive Alert", symbol: "archivebox.fill", tint: Ocean.inkFaint) {
            VStack(alignment: .leading, spacing: 12) {
                if alert.isCritical {
                    InfoNote(text: "This is a Class I notice — the most serious kind. It cannot be swiped away; archiving needs a reason so the decision stays visible in your history.",
                             symbol: "exclamationmark.triangle.fill", tint: Ocean.blue)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(archiveReasons, id: \.self) { reason in
                            OceanChip(title: reason, tint: Ocean.tide, isOn: archiveReason == reason) {
                                archiveReason = reason
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                OceanTextField(label: "Reason", placeholder: "required", required: true, text: $archiveReason)
                OceanButton(title: "Archive Alert", symbol: "archivebox.fill",
                            kind: .secondary, tint: Ocean.inkFaint) {
                    do {
                        try store.archiveAlert(alertID: alert.id, reason: archiveReason)
                        Haptics.success()
                        dismiss()
                    } catch {
                        Haptics.warning()
                        toast = ToastMessage(kind: .warning, title: "Not archived",
                                             detail: error.localizedDescription)
                    }
                }
            }
        }
    }
}
