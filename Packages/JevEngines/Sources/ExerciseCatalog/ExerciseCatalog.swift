import Foundation
import JevDomain

/// File del catalogo esercizi incluso nell'app (`Resources/exercises.json`).
///
/// Il catalogo è contenuto ORIGINALE del progetto (nessun testo, immagine o database copiato da
/// altre app). Si genera con `tools/catalog/generate_catalog.py`; la CI verifica che il JSON
/// sia aggiornato.
public struct CatalogFile: Sendable, Codable, Hashable {
    public var schemaVersion: Int
    public var exercises: [CatalogExercise]
}

/// Schema di movimento: raggruppa gli esercizi intercambiabili (alternative, varietà).
public enum MovementPattern: String, Sendable, Codable, CaseIterable {
    case horizontalPush = "horizontal_push"
    case verticalPush = "vertical_push"
    case horizontalPull = "horizontal_pull"
    case verticalPull = "vertical_pull"
    case squat
    case lunge
    case hinge
    case hipExtension = "hip_extension"
    case kneeExtension = "knee_extension"
    case kneeFlexion = "knee_flexion"
    case hipAdduction = "hip_adduction"
    case hipAbduction = "hip_abduction"
    case calfRaise = "calf_raise"
    case elbowFlexion = "elbow_flexion"
    case elbowExtension = "elbow_extension"
    case shoulderIsolation = "shoulder_isolation"
    case shrug
    case wrist
    case carry
    case coreFlexion = "core_flexion"
    case coreStability = "core_stability"
    case coreRotation = "core_rotation"
    case fly
}

public enum Mechanics: String, Sendable, Codable, CaseIterable {
    case compound
    case isolation
}

public enum Laterality: String, Sendable, Codable, CaseIterable {
    case bilateral
    case unilateral
}

/// Esercizio del catalogo (piano §3.2: `exercise` + `exercise_muscle`).
public struct CatalogExercise: Sendable, Codable, Hashable, Identifiable {
    public var id: String
    public var nameKey: String
    /// Nome italiano mostrato in UI (MVP solo italiano, ADR-015).
    public var name: String
    public var pattern: MovementPattern
    public var loadType: LoadType
    /// Attrezzatura richiesta: servono TUTTI gli elementi. `bodyweight` = nessuna attrezzatura.
    public var equipment: [Equipment]
    public var primaryMuscles: [MuscleGroup]
    public var secondaryMuscles: [MuscleGroup]
    public var mechanics: Mechanics
    public var laterality: Laterality
    /// 1 principiante, 2 intermedio, 3 avanzato.
    public var difficulty: Int
    /// Fatica sistemica relativa (0,3–1,3): entra nella dose del recupero (§5.8) e nella selezione.
    public var fatigueScore: Double
    /// Qualità dello stimolo (0,6–1,2) per l'ipertrofia.
    public var stimulusScore: Double
    /// Passo di carico tipico in kg (0 per gli esercizi a tempo).
    public var loadIncrementKg: Double
    /// Frazione del peso corporeo sollevata (solo bodyweight e assisted).
    public var bodyweightFraction: Double?
    public var contraindicatedAreas: [BodyArea]

    /// Contributo dell'esercizio a un muscolo: 1 primario, 0,5 secondario, 0 altrimenti.
    public func contribution(to muscle: MuscleGroup) -> Double {
        if primaryMuscles.contains(muscle) { return 1 }
        if secondaryMuscles.contains(muscle) { return 0.5 }
        return 0
    }

    /// Muscoli coinvolti con il contributo, primari prima dei secondari.
    public var muscleContributions: [(muscle: MuscleGroup, contribution: Double)] {
        primaryMuscles.map { ($0, 1.0) } + secondaryMuscles.map { ($0, 0.5) }
    }

    /// Attrezzatura effettivamente necessaria (senza `bodyweight`).
    public var requiredEquipment: Set<Equipment> {
        Set(equipment).subtracting([.bodyweight])
    }
}

public enum CatalogError: Error, Equatable {
    case resourceMissing
    case unsupportedSchemaVersion(Int)
    case duplicateIdentifier(String)
    /// Voce incoerente: senza muscoli primari, frazione del peso mancante, valori fuori scala.
    case invalidEntry(String)
}

public enum ExerciseCatalogLoader {
    public static let supportedSchemaVersion = 2

    /// Carica e valida il catalogo incluso nel bundle del modulo.
    public static func loadBundled() throws -> CatalogFile {
        guard let url = Bundle.module.url(forResource: "exercises", withExtension: "json") else {
            throw CatalogError.resourceMissing
        }
        return try decode(Data(contentsOf: url))
    }

    /// Decodifica e valida un catalogo (usato anche nei test con dati costruiti a mano).
    public static func decode(_ data: Data) throws -> CatalogFile {
        let file = try JSONDecoder().decode(CatalogFile.self, from: data)
        guard file.schemaVersion == supportedSchemaVersion else {
            throw CatalogError.unsupportedSchemaVersion(file.schemaVersion)
        }
        var seen = Set<String>()
        for exercise in file.exercises {
            guard seen.insert(exercise.id).inserted else {
                throw CatalogError.duplicateIdentifier(exercise.id)
            }
            try validate(exercise)
        }
        return file
    }

    static func validate(_ e: CatalogExercise) throws {
        guard !e.primaryMuscles.isEmpty,
              Set(e.primaryMuscles).isDisjoint(with: e.secondaryMuscles),
              (1...3).contains(e.difficulty),
              (0.3...1.3).contains(e.fatigueScore),
              (0.6...1.2).contains(e.stimulusScore),
              e.loadIncrementKg >= 0
        else { throw CatalogError.invalidEntry(e.id) }
        switch e.loadType {
        case .bodyweight, .assisted:
            guard let fraction = e.bodyweightFraction, (0.05...1.5).contains(fraction) else {
                throw CatalogError.invalidEntry(e.id)
            }
        case .timed:
            guard e.loadIncrementKg == 0 else { throw CatalogError.invalidEntry(e.id) }
        case .external:
            guard e.loadIncrementKg > 0 else { throw CatalogError.invalidEntry(e.id) }
        }
    }
}

/// Catalogo indicizzato con le alternative per schema di movimento e muscoli (SCR-WK-05).
public struct ExerciseCatalog: Sendable {
    public let exercises: [CatalogExercise]
    private let byID: [String: CatalogExercise]

    public init(_ exercises: [CatalogExercise]) {
        self.exercises = exercises.sorted { $0.id < $1.id }
        self.byID = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public static func bundled() throws -> ExerciseCatalog {
        ExerciseCatalog(try ExerciseCatalogLoader.loadBundled().exercises)
    }

    public subscript(id: String) -> CatalogExercise? { byID[id] }

    /// Somiglianza 0…1: stesso schema (0,5) + sovrapposizione dei muscoli primari (Jaccard, 0,5).
    public static func similarity(_ a: CatalogExercise, _ b: CatalogExercise) -> Double {
        let samePattern: Double = a.pattern == b.pattern ? 0.5 : 0
        let pa = Set(a.primaryMuscles), pb = Set(b.primaryMuscles)
        let union = pa.union(pb).count
        let shared = Double(pa.intersection(pb).count)
        let jaccard: Double = union == 0 ? 0 : shared / Double(union)
        return samePattern + 0.5 * jaccard
    }

    /// Alternative ordinate per somiglianza decrescente (poi per id), escluso l'esercizio stesso.
    /// Solo esercizi con almeno un muscolo primario in comune.
    public func alternatives(to id: String, limit: Int = 8) -> [CatalogExercise] {
        guard let base = byID[id] else { return [] }
        let candidates = exercises.filter {
            $0.id != id && !Set($0.primaryMuscles).isDisjoint(with: base.primaryMuscles)
        }
        let scored: [(exercise: CatalogExercise, score: Double)] = candidates.map { candidate in
            (exercise: candidate, score: Self.similarity(base, candidate))
        }
        let ranked = scored.sorted { (lhs: (exercise: CatalogExercise, score: Double), rhs: (exercise: CatalogExercise, score: Double)) -> Bool in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.exercise.id < rhs.exercise.id
        }
        return Array(ranked.prefix(limit)).map { $0.exercise }
    }
}
