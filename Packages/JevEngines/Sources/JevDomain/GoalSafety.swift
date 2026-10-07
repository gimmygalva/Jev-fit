import Foundation

/// Gate di sicurezza sull'obiettivo e limiti del ritmo di variazione del peso
/// (ARCHITECTURE_PLAN §5.3, PS-ON-03, PS-ON-05, PS-SAF-06, QA-14).
///
/// Funzioni pure: le usano l'onboarding (per disattivare le scelte non sicure) e, più avanti,
/// il NutritionEngine e il CheckInEngine (per non generare mai un deficit vietato).
/// Tutte le soglie vengono da `EngineConfig` (ADR-013).
public enum GoalSafety {
    /// Motivo per cui un obiettivo non è selezionabile. Il testo per l'utente lo sceglie la UI:
    /// qui c'è solo il codice, e non viene mai inviato all'AI (SECURITY §3).
    public enum BlockReason: String, Sendable, Hashable, CaseIterable {
        /// Età sotto il minimo dell'app: l'onboarding non procede.
        case belowMinimumAppAge = "below_minimum_app_age"
        /// Minorenne: nessun obiettivo in deficit.
        case minorNoDeficit = "minor_no_deficit"
        /// Gravidanza o allattamento dichiarati: nessun obiettivo in deficit.
        case pregnancyNoDeficit = "pregnancy_no_deficit"
        /// BMI attuale sotto la soglia di sottopeso: niente dimagrimento.
        case underweightNoLoss = "underweight_no_loss"
    }

    /// Dati della persona che il gate considera. I campi mancanti non bloccano: il controllo
    /// si ripete quando il dato arriva (es. l'età è chiesta dopo l'obiettivo).
    public struct Person: Sendable, Hashable {
        public var ageYears: Int?
        public var weightKg: Double?
        public var heightCm: Double?
        public var pregnancyOrLactation: Bool

        public init(ageYears: Int? = nil, weightKg: Double? = nil, heightCm: Double? = nil, pregnancyOrLactation: Bool = false) {
            self.ageYears = ageYears
            self.weightKg = weightKg
            self.heightCm = heightCm
            self.pregnancyOrLactation = pregnancyOrLactation
        }
    }

    /// Obiettivi che richiedono un deficit calorico.
    public static func requiresDeficit(_ goal: GoalType) -> Bool {
        goal == .fatLoss
    }

    /// `nil` se l'app può essere usata a questa età, altrimenti il motivo.
    public static func appUseBlock(ageYears: Int?, config: EngineConfig = .current) -> BlockReason? {
        guard let age = ageYears else { return nil }
        return age < config.safety.minimumAppAgeYears ? .belowMinimumAppAge : nil
    }

    /// `nil` se l'obiettivo è consentito, altrimenti il primo motivo di blocco.
    public static func block(for goal: GoalType, person: Person, config: EngineConfig = .current) -> BlockReason? {
        if let reason = appUseBlock(ageYears: person.ageYears, config: config) { return reason }
        guard requiresDeficit(goal) else { return nil }
        if let age = person.ageYears, age < config.safety.minimumDeficitAgeYears { return .minorNoDeficit }
        if person.pregnancyOrLactation { return .pregnancyNoDeficit }
        if let bmi = bmi(weightKg: person.weightKg, heightCm: person.heightCm), bmi < config.checkIn.underweightBMI {
            return .underweightNoLoss
        }
        return nil
    }

    /// Obiettivi selezionabili, nell'ordine di `GoalType.allCases`.
    public static func allowedGoals(for person: Person, config: EngineConfig = .current) -> [GoalType] {
        GoalType.allCases.filter { block(for: $0, person: person, config: config) == nil }
    }

    /// Indice di massa corporea, `nil` se i dati mancano o non sono plausibili.
    public static func bmi(weightKg: Double?, heightCm: Double?) -> Double? {
        guard let weight = weightKg, let height = heightCm, weight > 0, height > 0,
              weight.isFinite, height.isFinite else { return nil }
        let meters = height / 100
        return weight / (meters * meters)
    }

    /// Peso minimo selezionabile come obiettivo: quello che corrisponde al BMI di sottopeso.
    public static func minimumTargetWeightKg(heightCm: Double, config: EngineConfig = .current) -> Double {
        let meters = heightCm / 100
        return config.checkIn.underweightBMI * meters * meters
    }

    // MARK: Ritmo di variazione

    /// Limiti del ritmo in % del peso a settimana: negativo = perdita, positivo = aumento.
    public struct RateLimits: Sendable, Hashable {
        /// Intervallo selezionabile (estremi inclusi).
        public var range: ClosedRange<Double>
        public var defaultValue: Double
    }

    /// Limiti per l'obiettivo, `nil` se l'obiettivo non prevede una variazione di peso
    /// (mantenimento, forza, ricomposizione, fitness generale: ritmo 0).
    public static func rateLimits(for goal: GoalType, config: EngineConfig = .current) -> RateLimits? {
        let n = config.nutrition
        switch goal {
        case .fatLoss:
            return RateLimits(
                range: (-n.maxLossPercentPerWeek)...(-n.minLossPercentPerWeek),
                defaultValue: -config.safety.defaultLossPercentPerWeek
            )
        case .hypertrophy:
            return RateLimits(
                range: n.minGainPercentPerWeek...n.maxGainPercentPerWeek,
                defaultValue: config.safety.defaultGainPercentPerWeek
            )
        case .strength, .maintenance, .recomposition, .generalFitness:
            return nil
        }
    }

    /// Riporta un ritmo dentro i limiti dell'obiettivo (0 se l'obiettivo non ne prevede).
    public static func clampRate(_ rate: Double, for goal: GoalType, config: EngineConfig = .current) -> Double {
        guard let limits = rateLimits(for: goal, config: config) else { return 0 }
        guard rate.isFinite else { return limits.defaultValue }
        return min(max(rate, limits.range.lowerBound), limits.range.upperBound)
    }

    /// `true` se la perdita supera la soglia "ritmo aggressivo" (PS-ON-05).
    public static func isAggressiveLoss(_ rate: Double, config: EngineConfig = .current) -> Bool {
        rate < 0 && -rate > config.safety.aggressiveLossPercentPerWeek
    }

    /// Settimane stimate per arrivare al peso obiettivo con un ritmo costante in % del peso
    /// attuale. `nil` se il ritmo è nullo o va nella direzione sbagliata.
    public static func weeksToTarget(currentKg: Double, targetKg: Double, ratePercentPerWeek: Double) -> Double? {
        guard currentKg > 0, currentKg.isFinite, targetKg.isFinite, ratePercentPerWeek.isFinite else { return nil }
        let delta = targetKg - currentKg
        if delta == 0 { return 0 }
        let kgPerWeek = currentKg * ratePercentPerWeek / 100
        guard kgPerWeek != 0, (delta > 0) == (kgPerWeek > 0) else { return nil }
        return delta / kgPerWeek
    }

    /// Il peso obiettivo va nella direzione dell'obiettivo? (UF-01: "Dimagrimento ma target
    /// sopra il peso attuale" → avviso). Per gli obiettivi senza variazione è sempre coerente.
    public static func isTargetCoherent(goal: GoalType, currentKg: Double, targetKg: Double) -> Bool {
        switch goal {
        case .fatLoss: targetKg < currentKg
        case .hypertrophy: targetKg > currentKg
        case .strength, .maintenance, .recomposition, .generalFitness: true
        }
    }
}
