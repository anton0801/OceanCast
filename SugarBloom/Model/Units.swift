//
//  Units.swift
//  Ocean Cast
//
//  Measurement units and the conversion rules used everywhere quantities meet.
//  Conversion is only allowed inside one dimension — pieces are never silently
//  turned into grams.
//

import Foundation

enum MeasureDimension: String, Codable, CaseIterable {
    case count      // pieces
    case pack       // sealed packs, deliberately separate from pieces
    case mass
    case volume

    var title: String {
        switch self {
        case .count: return "Pieces"
        case .pack: return "Packs"
        case .mass: return "Weight"
        case .volume: return "Volume"
        }
    }
}

enum MeasureUnit: String, Codable, CaseIterable, Identifiable, Hashable {
    case piece
    case pack
    case gram
    case kilogram
    case milliliter
    case liter

    var id: String { rawValue }

    var short: String {
        switch self {
        case .piece: return "pcs"
        case .pack: return "pack"
        case .gram: return "g"
        case .kilogram: return "kg"
        case .milliliter: return "ml"
        case .liter: return "L"
        }
    }

    var title: String {
        switch self {
        case .piece: return "Pieces"
        case .pack: return "Packs"
        case .gram: return "Grams"
        case .kilogram: return "Kilograms"
        case .milliliter: return "Millilitres"
        case .liter: return "Litres"
        }
    }

    var dimension: MeasureDimension {
        switch self {
        case .piece: return .count
        case .pack: return .pack
        case .gram, .kilogram: return .mass
        case .milliliter, .liter: return .volume
        }
    }

    /// How many base units (g / ml / piece / pack) one unit holds.
    var baseFactor: Double {
        switch self {
        case .piece, .pack: return 1
        case .gram, .milliliter: return 1
        case .kilogram, .liter: return 1000
        }
    }

    var baseUnit: MeasureUnit {
        switch dimension {
        case .count: return .piece
        case .pack: return .pack
        case .mass: return .gram
        case .volume: return .milliliter
        }
    }

    static func compatible(_ a: MeasureUnit, _ b: MeasureUnit) -> Bool {
        a.dimension == b.dimension
    }

    /// Returns nil when the two units belong to different dimensions —
    /// the caller must then ask the user to choose a unit instead of guessing.
    static func convert(_ value: Double, from: MeasureUnit, to: MeasureUnit) -> Double? {
        guard compatible(from, to) else { return nil }
        return value * from.baseFactor / to.baseFactor
    }

    static func toBase(_ value: Double, unit: MeasureUnit) -> Double {
        value * unit.baseFactor
    }

    /// Picks the friendlier unit for display (1200 g -> 1.2 kg).
    static func humanize(_ value: Double, unit: MeasureUnit) -> (value: Double, unit: MeasureUnit) {
        switch unit {
        case .gram where value >= 1000: return (value / 1000, .kilogram)
        case .milliliter where value >= 1000: return (value / 1000, .liter)
        default: return (value, unit)
        }
    }
}
