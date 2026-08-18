//
//  ReceiptScanner.swift
//  Ocean Cast
//
//  On-device receipt reading (Vision). It produces a *draft* only: nothing
//  reaches Inventory until the user confirms the import.
//

import Foundation
import Vision
import CoreGraphics

struct ReceiptLine: Identifiable, Hashable {
    var id = UUID()
    var rawText: String
    var name: String
    var quantityText: String
    var unit: MeasureUnit = .piece
    var priceText: String
    var barcode: String = ""
    /// Recognition confidence reported by Vision for this line (0...1).
    var confidence: Double
    var ignored: Bool = false

    static let reviewThreshold: Double = 0.6

    var needsReview: Bool {
        confidence < Self.reviewThreshold
            || name.trimmingCharacters(in: .whitespaces).isEmpty
            || Parse.double(quantityText) == nil
    }

    var quantity: Double? { Parse.double(quantityText) }
    var price: Double? { Parse.double(priceText) }
}

enum ReceiptScanOutcome {
    case lines([ReceiptLine])
    case noTextFound
    case failed(String)
}

struct ReceiptScanner {
    static let sourceName = "On-device text recognition (Vision)"

    func scan(imageData: Data) async -> ReceiptScanOutcome {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Self.recognize(imageData: imageData))
            }
        }
    }

    private static func recognize(imageData: Data) -> ReceiptScanOutcome {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return .failed("The image could not be read.")
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return .failed(error.localizedDescription)
        }

        guard let observations = request.results, !observations.isEmpty else {
            return .noTextFound
        }

        var lines: [ReceiptLine] = []
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count >= 3 else { continue }
            if Self.isNoise(text) { continue }
            lines.append(Self.parse(text: text, confidence: Double(candidate.confidence)))
        }

        return lines.isEmpty ? .noTextFound : .lines(lines)
    }

    private static func isNoise(_ text: String) -> Bool {
        let lower = text.lowercased()
        let markers = ["total", "subtotal", "vat", "tax", "change", "cash", "card", "thank", "receipt",
                       "balance", "tender", "invoice", "cashier", "www.", "tel", "store #"]
        if markers.contains(where: { lower.contains($0) }) { return true }
        // A line with no letters at all is usually a timestamp or a separator.
        return !text.contains(where: { $0.isLetter })
    }

    private static func parse(text: String, confidence: Double) -> ReceiptLine {
        var working = text
        var price = ""
        var quantity = ""

        // Trailing amount, e.g. "Milk 2 x 1,29" or "Milk 2.58"
        if let match = working.range(of: #"(\d+[.,]\d{2})\s*$"#, options: .regularExpression) {
            price = String(working[match]).trimmingCharacters(in: .whitespaces)
            working = String(working[working.startIndex..<match.lowerBound])
        }

        // Leading or embedded quantity, e.g. "2 x", "3pcs", "0.5 kg"
        var unit = MeasureUnit.piece
        if let match = working.range(of: #"(\d+(?:[.,]\d+)?)\s*(x|pcs|pc|kg|g|l|ml)\b"#,
                                     options: [.regularExpression, .caseInsensitive]) {
            let fragment = String(working[match])
            let number = fragment.components(separatedBy: CharacterSet.decimalDigits.inverted.subtracting(CharacterSet(charactersIn: ".,")))
                .joined()
            quantity = number
            let lower = fragment.lowercased()
            if lower.contains("kg") { unit = .kilogram }
            else if lower.hasSuffix("g") && !lower.contains("kg") { unit = .gram }
            else if lower.contains("ml") { unit = .milliliter }
            else if lower.contains("l") && !lower.contains("ml") { unit = .liter }
            working.removeSubrange(match)
        }

        let name = working
            .trimmingCharacters(in: CharacterSet(charactersIn: " -*#.,;:"))
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)

        return ReceiptLine(rawText: text,
                           name: name,
                           quantityText: quantity.isEmpty ? "1" : quantity.replacingOccurrences(of: ",", with: "."),
                           unit: unit,
                           priceText: price.replacingOccurrences(of: ",", with: "."),
                           confidence: confidence)
    }
}
