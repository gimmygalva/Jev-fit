import Foundation

// MARK: - Unità canoniche (ADR-010)
// Lo storage e gli engine lavorano SEMPRE in kg e kcal. Le conversioni verso lb e kJ
// avvengono solo nel layer di presentazione o in ingresso dai form utente.

/// Massa in chilogrammi (unità canonica).
public struct Mass: Sendable, Hashable, Comparable, Codable {
    /// Fattore esatto di definizione internazionale (1959).
    public static let kilogramsPerPound = 0.453_592_37

    public let kilograms: Double

    public init(kilograms: Double) {
        self.kilograms = kilograms
    }

    public static func kilograms(_ value: Double) -> Mass { Mass(kilograms: value) }
    public static func pounds(_ value: Double) -> Mass { Mass(kilograms: value * kilogramsPerPound) }

    public var pounds: Double { kilograms / Mass.kilogramsPerPound }

    public func value(in unit: MassUnit) -> Double {
        switch unit {
        case .kilograms: kilograms
        case .pounds: pounds
        }
    }

    public init(value: Double, unit: MassUnit) {
        switch unit {
        case .kilograms: self.init(kilograms: value)
        case .pounds: self.init(kilograms: value * Mass.kilogramsPerPound)
        }
    }

    public static let zero = Mass(kilograms: 0)

    public static func < (lhs: Mass, rhs: Mass) -> Bool { lhs.kilograms < rhs.kilograms }
    public static func + (lhs: Mass, rhs: Mass) -> Mass { Mass(kilograms: lhs.kilograms + rhs.kilograms) }
    public static func - (lhs: Mass, rhs: Mass) -> Mass { Mass(kilograms: lhs.kilograms - rhs.kilograms) }
    public static func * (lhs: Mass, rhs: Double) -> Mass { Mass(kilograms: lhs.kilograms * rhs) }
}

public enum MassUnit: String, Sendable, Codable, CaseIterable {
    case kilograms
    case pounds
}

/// Energia in kilocalorie (unità canonica).
public struct Energy: Sendable, Hashable, Comparable, Codable {
    /// 1 kcal termochimica = 4,184 kJ.
    public static let kilojoulesPerKilocalorie = 4.184

    public let kilocalories: Double

    public init(kilocalories: Double) {
        self.kilocalories = kilocalories
    }

    public static func kilocalories(_ value: Double) -> Energy { Energy(kilocalories: value) }
    public static func kilojoules(_ value: Double) -> Energy {
        Energy(kilocalories: value / kilojoulesPerKilocalorie)
    }

    public var kilojoules: Double { kilocalories * Energy.kilojoulesPerKilocalorie }

    public func value(in unit: EnergyUnit) -> Double {
        switch unit {
        case .kilocalories: kilocalories
        case .kilojoules: kilojoules
        }
    }

    public init(value: Double, unit: EnergyUnit) {
        switch unit {
        case .kilocalories: self.init(kilocalories: value)
        case .kilojoules: self.init(kilocalories: value / Energy.kilojoulesPerKilocalorie)
        }
    }

    public static let zero = Energy(kilocalories: 0)

    public static func < (lhs: Energy, rhs: Energy) -> Bool { lhs.kilocalories < rhs.kilocalories }
    public static func + (lhs: Energy, rhs: Energy) -> Energy { Energy(kilocalories: lhs.kilocalories + rhs.kilocalories) }
    public static func - (lhs: Energy, rhs: Energy) -> Energy { Energy(kilocalories: lhs.kilocalories - rhs.kilocalories) }
    public static func * (lhs: Energy, rhs: Double) -> Energy { Energy(kilocalories: lhs.kilocalories * rhs) }
}

public enum EnergyUnit: String, Sendable, Codable, CaseIterable {
    case kilocalories
    case kilojoules
}

/// Energia per grammo di macronutriente (fattori di Atwater generali).
public enum AtwaterFactor {
    public static let proteinKcalPerGram = 4.0
    public static let carbohydrateKcalPerGram = 4.0
    public static let fatKcalPerGram = 9.0
}
