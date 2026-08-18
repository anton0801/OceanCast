//
//  ProductLookupService.swift
//  Ocean Cast
//
//  Barcode lookup against the Open Food Facts catalogue.
//  A lookup only pre-fills a form — the user confirms every field, and a
//  catalogue hint is never stored as if it were the user's own date.
//

import Foundation

struct ProductLookupResult: Equatable {
    var barcode: String
    var name: String?
    var brand: String?
    var quantityText: String?
    var categories: String?
    var sourceName: String
    var sourceURL: URL?
    var fetchedAt: Date

    var hint: ReferenceHint {
        ReferenceHint(sourceName: sourceName,
                      sourceURL: sourceURL?.absoluteString,
                      fetchedAt: fetchedAt,
                      shelfLifeDaysHint: nil,
                      categories: categories,
                      quantityText: quantityText)
    }
}

enum ProductLookupOutcome: Equatable {
    case found(ProductLookupResult)
    case notFound(barcode: String)
    case offline
    case failed(String)
}

struct ProductLookupService {
    static let sourceName = "Open Food Facts"

    func lookup(barcode: String, isOnline: Bool) async -> ProductLookupOutcome {
        let clean = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 6, clean.allSatisfy(\.isNumber) else {
            return .failed("“\(clean)” is not a valid barcode.")
        }
        guard isOnline else { return .offline }

        var components = URLComponents(string: "https://world.openfoodfacts.org/api/v2/product/\(clean).json")
        components?.queryItems = [
            URLQueryItem(name: "fields", value: "code,product_name,brands,quantity,categories")
        ]
        guard let url = components?.url else { return .failed("Could not build the lookup request.") }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("OceanCast/1.0 (iOS home pantry app)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                return .notFound(barcode: clean)
            }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                return .failed("The catalogue replied with status \(code).")
            }
            let decoded = try JSONDecoder().decode(OFFResponse.self, from: data)
            guard decoded.status == 1, let product = decoded.product else {
                return .notFound(barcode: clean)
            }
            let result = ProductLookupResult(
                barcode: clean,
                name: product.product_name?.nilIfBlank,
                brand: product.brands?.nilIfBlank,
                quantityText: product.quantity?.nilIfBlank,
                categories: product.categories?.nilIfBlank,
                sourceName: Self.sourceName,
                sourceURL: URL(string: "https://world.openfoodfacts.org/product/\(clean)"),
                fetchedAt: Date()
            )
            return .found(result)
        } catch is CancellationError {
            return .failed("The lookup was cancelled.")
        } catch let error as URLError where error.code == .notConnectedToInternet {
            return .offline
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private struct OFFResponse: Decodable {
        var status: Int
        var product: OFFProduct?
    }

    private struct OFFProduct: Decodable {
        var product_name: String?
        var brands: String?
        var quantity: String?
        var categories: String?
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
