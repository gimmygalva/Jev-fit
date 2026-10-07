import Foundation
import JevCore
import JevDomain

/// Macronutrienti (§5.4): AUTO, ASSISTED, MANUAL. Grammi interi, mai negativi.
public enum MacroPlanner {
    public struct Macros: Sendable, Hashable {
        public var proteinG: Double
        public var carbsG: Double
        public var fatG: Double
        public var fiberG: Double
        /// `4P + 4C + 9F` dei grammi arrotondati.
        public var kcal: Double
        /// Il target calorico non basta per i minimi di proteine e grassi.
        public var infeasible: Bool
        /// Avvisi non bloccanti (MANUAL e ASSISTED): `macro.protein_below_minimum`, `macro.fat_below_minimum`.
        public var warnings: [String]
    }

    /// Peso di riferimento: trend; con BMI > 30 e % grasso ignota, il peso a BMI 27.
    public static func referenceWeightKg(
        trendWeightKg: Double, heightCm: Double, bodyFatKnown: Bool, config: EngineConfig = .current
    ) -> Double {
        let n = config.nutrition
        guard !bodyFatKnown, let bmi = GoalSafety.bmi(weightKg: trendWeightKg, heightCm: heightCm),
              bmi > n.referenceWeightBMICap else { return trendWeightKg }
        let meters = heightCm / 100
        return n.referenceWeightBMITarget * meters * meters
    }

    /// AUTO: proteine per obiettivo, grassi 30% (minimo 0,6 g/kg), carboidrati residuo. Se il
    /// residuo è negativo: grassi al minimo, poi proteine fino a 1,6 g/kg, poi "infeasible".
    public static func auto(kcal: Double, goal: GoalType, referenceWeightKg w: Double, config: EngineConfig = .current) -> Macros {
        let n = config.nutrition
        var protein = (n.proteinGramsPerKg[goal] ?? n.proteinFloorGramsPerKg) * w
        var fat = max(n.fatEnergyShare * kcal / 9, n.fatFloorGramsPerKg * w)
        var carbs = (kcal - 4 * protein - 9 * fat) / 4
        if carbs < 0 {
            fat = n.fatFloorGramsPerKg * w
            carbs = (kcal - 4 * protein - 9 * fat) / 4
        }
        if carbs < 0 {
            protein = max(n.proteinFloorGramsPerKg * w, (kcal - 9 * fat) / 4)
            carbs = (kcal - 4 * protein - 9 * fat) / 4
        }
        return build(protein: protein, carbs: carbs, fat: fat, targetKcal: kcal, infeasible: carbs < -0.5, warnings: [], config: config)
    }

    /// ASSISTED: proteine bloccate (non sotto il minimo), l'utente sposta la quota dei carboidrati
    /// sull'energia non proteica (`carbShare` 0…1); il solver mantiene `4P + 4C + 9F = kcal`.
    public static func assisted(
        kcal: Double, goal: GoalType, referenceWeightKg w: Double, carbShare: Double, proteinG: Double? = nil,
        config: EngineConfig = .current
    ) -> Macros {
        let n = config.nutrition
        let minimumProtein = n.proteinFloorGramsPerKg * w
        let protein = max(proteinG ?? (n.proteinGramsPerKg[goal] ?? n.proteinFloorGramsPerKg) * w, minimumProtein)
        let share = RobustStatistics.clamp(carbShare.isFinite ? carbShare : 0.5, 0...1)
        let nonProtein = kcal - 4 * protein
        var fat = max((1 - share) * nonProtein / 9, n.fatFloorGramsPerKg * w)
        var carbs = (nonProtein - 9 * fat) / 4
        var warnings: [String] = []
        if carbs < 0 {
            fat = max(nonProtein / 9, 0)
            carbs = 0
            if fat < n.fatFloorGramsPerKg * w { warnings.append("macro.fat_below_minimum") }
        }
        return build(protein: protein, carbs: carbs, fat: fat, targetKcal: kcal, infeasible: nonProtein < 0,
                     warnings: warnings, config: config)
    }

    /// MANUAL: macro liberi, kcal derivate; avvisi non bloccanti sotto i minimi.
    public static func manual(
        proteinG: Double, carbsG: Double, fatG: Double, referenceWeightKg w: Double, config: EngineConfig = .current
    ) -> Macros {
        let n = config.nutrition
        var warnings: [String] = []
        if proteinG < n.proteinFloorGramsPerKg * w { warnings.append("macro.protein_below_minimum") }
        if fatG < n.fatFloorGramsPerKg * w { warnings.append("macro.fat_below_minimum") }
        return build(protein: proteinG, carbs: carbsG, fat: fatG, targetKcal: nil, infeasible: false,
                     warnings: warnings, config: config)
    }

    /// Fibra: 14 g ogni 1.000 kcal.
    public static func fiberG(kcal: Double, config: EngineConfig = .current) -> Double {
        (config.nutrition.fiberGramsPer1000Kcal * kcal / 1000).rounded()
    }

    private static func build(
        protein: Double, carbs: Double, fat: Double, targetKcal: Double?, infeasible: Bool, warnings: [String],
        config: EngineConfig
    ) -> Macros {
        let p = max(protein, 0).rounded()
        let f = max(fat, 0).rounded()
        var c = max(carbs, 0).rounded()
        // Con un target calorico i carboidrati assorbono l'arrotondamento (somma entro ±1%).
        if let target = targetKcal, !infeasible {
            c = max(((target - 4 * p - 9 * f) / 4).rounded(), 0)
        }
        let kcal = 4 * p + 4 * c + 9 * f
        return Macros(
            proteinG: p, carbsG: c, fatG: f, fiberG: fiberG(kcal: targetKcal ?? kcal, config: config), kcal: kcal,
            infeasible: infeasible, warnings: warnings
        )
    }
}
