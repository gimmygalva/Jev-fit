import Foundation
import JevCore

// Tipi di dominio condivisi da engine, persistenza e UI.
// I raw value sono stabili: finiscono nel database e nella sync. Non rinominarli mai;
// aggiungere un caso è consentito, rimuoverlo richiede una migrazione (piano §3.3).

public enum GoalType: String, Sendable, Codable, CaseIterable {
    case strength
    case hypertrophy
    case maintenance
    case recomposition
    case fatLoss = "fat_loss"
    case generalFitness = "general_fitness"
}

public enum ExperienceLevel: String, Sendable, Codable, CaseIterable, Comparable {
    case beginner
    case intermediate
    case advanced

    private var rank: Int {
        switch self {
        case .beginner: 0
        case .intermediate: 1
        case .advanced: 2
        }
    }

    public static func < (lhs: ExperienceLevel, rhs: ExperienceLevel) -> Bool { lhs.rank < rhs.rank }
}

/// Sesso biologico: facoltativo (nil = non indicato). Serve solo alle equazioni del metabolismo
/// basale; senza, si usa una costante intermedia e un prior più incerto (piano §5.2).
public enum BiologicalSex: String, Sendable, Codable, CaseIterable {
    case male
    case female
}

public enum ActivityLevel: String, Sendable, Codable, CaseIterable {
    case sedentary
    case light
    case moderate
    case high
}

public enum SplitType: String, Sendable, Codable, CaseIterable {
    case fullBody = "full_body"
    case upperLower = "upper_lower"
    case pushPullLegs = "push_pull_legs"
    case torsoLimbs = "torso_limbs"
    case hybrid
    case custom
}

/// I 17 gruppi muscolari del RecoveryEngine e della body map (PS-RC-01).
public enum MuscleGroup: String, Sendable, Codable, CaseIterable {
    case chest
    case lats
    case upperBack = "upper_back"         // trapezi / alta schiena
    case frontDelts = "front_delts"
    case sideDelts = "side_delts"
    case rearDelts = "rear_delts"
    case biceps
    case triceps
    case forearms
    case abs
    case obliques
    case lowerBack = "lower_back"
    case glutes
    case quads
    case hamstrings
    case adductors
    case calves

    /// Classe dimensionale usata per la costante di recupero di base (piano §5.8).
    public var sizeClass: MuscleSizeClass {
        switch self {
        case .sideDelts, .calves, .forearms, .abs, .obliques: .small
        case .chest, .lats, .upperBack, .frontDelts, .rearDelts, .biceps, .triceps, .adductors: .medium
        case .glutes, .quads, .hamstrings, .lowerBack: .large
        }
    }
}

public enum MuscleSizeClass: String, Sendable, Codable, CaseIterable {
    case small
    case medium
    case large
}

public enum MuscleRole: String, Sendable, Codable, CaseIterable {
    case primary
    case secondary
}

public enum Equipment: String, Sendable, Codable, CaseIterable {
    case barbell
    case dumbbell
    case kettlebell
    case cable
    case machine
    case smithMachine = "smith_machine"
    case ezBar = "ez_bar"
    case trapBar = "trap_bar"
    case pullUpBar = "pull_up_bar"
    case dipStation = "dip_station"
    case bench
    case resistanceBand = "resistance_band"
    case bodyweight
}

/// Come si calcola il carico effettivo di un esercizio (QA-01, piano §5.7).
public enum LoadType: String, Sendable, Codable, CaseIterable {
    /// Carico esterno inserito dall'utente.
    case external
    /// Peso corporeo × frazione + eventuale zavorra.
    case bodyweight
    /// Peso corporeo × frazione − assistenza.
    case assisted
    /// Esercizio a tempo (isometrici): progressione sulla durata, nessun e1RM.
    case timed
}

public enum SetType: String, Sendable, Codable, CaseIterable {
    case warmup
    case working
    case top
    case backoff
    case drop
    case failure
    case amrap

    /// Le serie di riscaldamento non contano per volume, overload ed e1RM (PS-WK-03).
    public var countsAsWorkingSet: Bool { self != .warmup }
}

public enum PainLevel: String, Sendable, Codable, CaseIterable {
    case none
    case mild
    case strong
}

public enum MealSlot: String, Sendable, Codable, CaseIterable {
    case breakfast
    case lunch
    case dinner
    case snack
}

public enum MacroMode: String, Sendable, Codable, CaseIterable {
    case auto
    case assisted
    case manual
}

public enum NutritionDayStatus: String, Sendable, Codable, CaseIterable {
    case open
    case complete
    case incomplete
}

public enum DayType: String, Sendable, Codable, CaseIterable {
    case training
    case rest
}

/// Profilo nutrizionale per 100 g (unità canoniche: kcal e grammi).
public struct NutrientProfile: Sendable, Hashable, Codable {
    public var energyKcal: Double
    public var proteinGrams: Double
    public var carbohydrateGrams: Double
    public var fatGrams: Double
    public var fiberGrams: Double?

    public init(energyKcal: Double, proteinGrams: Double, carbohydrateGrams: Double, fatGrams: Double, fiberGrams: Double? = nil) {
        self.energyKcal = energyKcal
        self.proteinGrams = proteinGrams
        self.carbohydrateGrams = carbohydrateGrams
        self.fatGrams = fatGrams
        self.fiberGrams = fiberGrams
    }

    /// Nutrienti di una porzione di `grams` grammi, a partire dal profilo per 100 g.
    public func scaled(toGrams grams: Double) -> NutrientProfile {
        let f = grams / 100
        return NutrientProfile(
            energyKcal: energyKcal * f,
            proteinGrams: proteinGrams * f,
            carbohydrateGrams: carbohydrateGrams * f,
            fatGrams: fatGrams * f,
            fiberGrams: fiberGrams.map { $0 * f }
        )
    }

    /// Energia ricostruita dai macro con i fattori di Atwater: serve a segnalare dati incoerenti.
    public var atwaterEnergyKcal: Double {
        proteinGrams * AtwaterFactor.proteinKcalPerGram
            + carbohydrateGrams * AtwaterFactor.carbohydrateKcalPerGram
            + fatGrams * AtwaterFactor.fatKcalPerGram
    }

    /// Valori fisicamente plausibili per 100 g: nessun negativo, macro ≤ 100 g, energia ≤ 900 kcal.
    public var isPhysicallyPlausiblePer100g: Bool {
        let parts = [energyKcal, proteinGrams, carbohydrateGrams, fatGrams] + [fiberGrams].compactMap { $0 }
        guard parts.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return false }
        return proteinGrams + carbohydrateGrams + fatGrams <= 100.5 && energyKcal <= 900
    }
}
