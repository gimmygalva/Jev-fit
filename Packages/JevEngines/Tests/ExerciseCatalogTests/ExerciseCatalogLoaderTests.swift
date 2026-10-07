import Foundation
import JevDomain
import Testing
@testable import ExerciseCatalog

@Suite("Catalogo esercizi — loader, validazione, alternative")
struct ExerciseCatalogLoaderTests {
    static let validEntry = """
    {"id":"bench_press_barbell","nameKey":"exercise.bench_press_barbell","name":"Panca","pattern":"horizontal_push",
    "loadType":"external","equipment":["barbell","bench"],"primaryMuscles":["chest"],
    "secondaryMuscles":["triceps","front_delts"],"mechanics":"compound","laterality":"bilateral","difficulty":2,
    "fatigueScore":1.2,"stimulusScore":1.0,"loadIncrementKg":2.5,"contraindicatedAreas":["shoulder"]}
    """

    private func file(_ entries: [String], version: Int = 2) -> Data {
        Data(#"{"schemaVersion":\#(version),"exercises":[\#(entries.joined(separator: ","))]}"#.utf8)
    }

    /// La voce valida con un campo sostituito (valore JSON).
    private func entry(replacing key: String, with value: String) -> String {
        var object = (try? JSONSerialization.jsonObject(with: Data(Self.validEntry.utf8))) as? [String: Any] ?? [:]
        object[key] = try? JSONSerialization.jsonObject(with: Data(value.utf8), options: .fragmentsAllowed)
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    @Test("Il catalogo incluso nel bundle si carica, è valido e copre tutti i muscoli")
    func bundled() throws {
        let file = try ExerciseCatalogLoader.loadBundled()
        #expect(file.schemaVersion == ExerciseCatalogLoader.supportedSchemaVersion)
        #expect(file.exercises.count >= 140)
        #expect(Set(file.exercises.map(\.id)).count == file.exercises.count)
        let covered = Set(file.exercises.flatMap(\.primaryMuscles))
        #expect(covered == Set(MuscleGroup.allCases))
        // Ogni muscolo ha almeno un esercizio a corpo libero o con soli manubri (home gym minima).
        let minimal: Set<Equipment> = [.dumbbell, .bench, .bodyweight, .pullUpBar, .resistanceBand]
        for muscle in MuscleGroup.allCases {
            #expect(file.exercises.contains { $0.primaryMuscles.contains(muscle) && $0.requiredEquipment.isSubset(of: minimal) },
                    "Nessun esercizio con attrezzatura minima per \(muscle)")
        }
    }

    @Test("Una voce valida viene decodificata con contributi e attrezzatura richiesta")
    func decodesEntry() throws {
        let decoded = try ExerciseCatalogLoader.decode(file([Self.validEntry]))
        let exercise = try #require(decoded.exercises.first)
        #expect(exercise.secondaryMuscles == [.triceps, .frontDelts])
        #expect(exercise.contribution(to: .chest) == 1)
        #expect(exercise.contribution(to: .triceps) == 0.5)
        #expect(exercise.contribution(to: .quads) == 0)
        #expect(exercise.muscleContributions.map(\.contribution) == [1, 0.5, 0.5])
        #expect(exercise.requiredEquipment == [.barbell, .bench])
    }

    @Test("Schema non supportato, ID duplicati, JSON corrotto e voci incoerenti vengono rifiutati")
    func rejects() {
        #expect(throws: CatalogError.unsupportedSchemaVersion(1)) {
            try ExerciseCatalogLoader.decode(file([], version: 1))
        }
        #expect(throws: CatalogError.duplicateIdentifier("bench_press_barbell")) {
            try ExerciseCatalogLoader.decode(file([Self.validEntry, Self.validEntry]))
        }
        #expect(throws: DecodingError.self) {
            try ExerciseCatalogLoader.decode(file([#"{"id":"y"}"#]))
        }
        let invalid = [
            entry(replacing: "primaryMuscles", with: "[]"),
            entry(replacing: "secondaryMuscles", with: #"["chest"]"#),
            entry(replacing: "difficulty", with: "4"),
            entry(replacing: "fatigueScore", with: "2"),
            entry(replacing: "stimulusScore", with: "0.1"),
            entry(replacing: "loadIncrementKg", with: "0"),
            entry(replacing: "loadType", with: #""bodyweight""#),
            entry(replacing: "loadType", with: #""timed""#),
        ]
        for json in invalid {
            #expect(throws: CatalogError.invalidEntry("bench_press_barbell")) {
                try ExerciseCatalogLoader.decode(file([json]))
            }
        }
    }

    @Test("Le alternative condividono i muscoli primari e lo stesso schema viene prima")
    func alternatives() throws {
        let catalog = try ExerciseCatalog.bundled()
        let alternatives = catalog.alternatives(to: "barbell_bench_press")
        #expect(!alternatives.isEmpty)
        #expect(alternatives.count <= 8)
        #expect(!alternatives.contains { $0.id == "barbell_bench_press" })
        #expect(alternatives.allSatisfy { $0.primaryMuscles.contains(.chest) })
        #expect(alternatives.first?.pattern == .horizontalPush)
        #expect(catalog.alternatives(to: "missing").isEmpty)
        #expect(catalog["barbell_bench_press"]?.name == "Panca piana con bilanciere")
        #expect(catalog["missing"] == nil)
        let a = try #require(catalog["barbell_bench_press"])
        #expect(ExerciseCatalog.similarity(a, a) == 1)
    }
}
