//
//  RecallService.swift
//  Ocean Cast
//
//  Official recall notices from openFDA (U.S. FDA food enforcement reports).
//  The app forwards what the source says — it never writes its own guidance and
//  never decides that a notice involves the user's batch.
//

import Foundation

enum RecallFetchOutcome {
    case success([RecallAlert])
    case offline
    case failed(String)
}

struct RecallService {
    static let sourceName = "openFDA · U.S. FDA Food Enforcement Reports"
    static let sourceURL = URL(string: "https://open.fda.gov/apis/food/enforcement/")
    static let officialGuidanceURL = URL(string: "https://www.fda.gov/safety/recalls-market-withdrawals-safety-alerts")!

    func fetchLatest(limit: Int = 30, isOnline: Bool) async -> RecallFetchOutcome {
        guard isOnline else { return .offline }

        var components = URLComponents(string: "https://api.fda.gov/food/enforcement.json")
        components?.queryItems = [
            URLQueryItem(name: "sort", value: "report_date:desc"),
            URLQueryItem(name: "limit", value: String(max(1, min(limit, 99))))
        ]
        guard let url = components?.url else { return .failed("Could not build the request.") }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("OceanCast/1.0 (iOS home pantry app)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failed("The source returned an unexpected response.")
            }
            if http.statusCode == 404 { return .success([]) }
            guard (200..<300).contains(http.statusCode) else {
                return .failed("The source replied with status \(http.statusCode).")
            }
            let decoded = try JSONDecoder().decode(FDAResponse.self, from: data)
            let now = Date()
            let alerts = (decoded.results ?? []).map { $0.toAlert(fetchedAt: now) }
            return .success(alerts)
        } catch let error as URLError where error.code == .notConnectedToInternet {
            return .offline
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    // MARK: - Decoding

    private struct FDAResponse: Decodable {
        var results: [FDARecall]?
    }

    private struct FDARecall: Decodable {
        var recall_number: String?
        var status: String?
        var classification: String?
        var product_description: String?
        var code_info: String?
        var reason_for_recall: String?
        var recalling_firm: String?
        var distribution_pattern: String?
        var report_date: String?
        var product_type: String?

        func toAlert(fetchedAt: Date) -> RecallAlert {
            let description = product_description ?? "Product description not provided by the source"
            let identifier = recall_number ?? UUID().uuidString
            return RecallAlert(
                id: identifier,
                title: RecallService.shortTitle(from: description),
                firmName: recalling_firm,
                productDescription: description,
                reason: reason_for_recall,
                classification: classification,
                status: status,
                distribution: distribution_pattern,
                codes: RecallService.extractCodes(from: code_info),
                reportedAt: RecallService.parseDate(report_date),
                sourceName: RecallService.sourceName,
                sourceURL: RecallService.officialGuidanceURL.absoluteString,
                fetchedAt: fetchedAt
            )
        }
    }

    static func parseDate(_ raw: String?) -> Date? {
        guard let raw, raw.count == 8 else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: raw)
    }

    static func shortTitle(from description: String) -> String {
        let firstSentence = description.split(separator: ",").first.map(String.init) ?? description
        return String(firstSentence.prefix(90)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Pulls quotable identifiers (UPCs, lot codes) out of the free-text code field.
    static func extractCodes(from raw: String?) -> [String] {
        guard let raw, !raw.isEmpty else { return [] }
        var codes: [String] = []
        let pattern = #"[A-Z0-9][A-Z0-9\-/]{4,}"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let range = NSRange(raw.startIndex..., in: raw)
            for match in regex.matches(in: raw, range: range) {
                if let swiftRange = Range(match.range, in: raw) {
                    let value = String(raw[swiftRange])
                    if !codes.contains(value) { codes.append(value) }
                }
                if codes.count >= 40 { break }
            }
        }
        return codes
    }
}
