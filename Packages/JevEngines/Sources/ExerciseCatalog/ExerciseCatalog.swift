import Foundation
import JevDomain

/// File del catalogo esercizi incluso nell'app (`Resources/exercises.json`).
///
/// Il catalogo è contenuto ORIGINALE del progetto (nessun testo, immagine o database copiato da
/// altre app). In M1 il file contiene solo l'intestazione; Agent 04 lo popola in M4 con
/// ~150 esercizi e la struttura completa del piano §3.2 (`exercise`, `exercise_muscle`,
/// `exercise_alternative`).
public struct CatalogFile: Sendable, Codable, Hashable {
    public var schemaVersion: Int
    public var exercises: [CatalogExercise]
}

/// Voce minima del catalogo: verrà estesa da Agent 04 (campi aggiunti come opzionali per
/// restare compatibili con i file esistenti).
public struct CatalogExercise: Sendable, Codable, Hashable, Identifiable {
    public var id: String
    public var nameKey: String
    public var loadType: LoadType
    public var equipment: [Equipment]
    public var primaryMuscles: [MuscleGroup]
    public var secondaryMuscles: [MuscleGroup]
}

public enum CatalogError: Error, Equatable {
    case resourceMissing
    case unsupportedSchemaVersion(Int)
    case duplicateIdentifier(String)
}

public enum ExerciseCatalogLoader {
    public static let supportedSchemaVersion = 1

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
        }
        return file
    }
}
