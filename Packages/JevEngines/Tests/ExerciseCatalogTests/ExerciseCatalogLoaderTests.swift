import Foundation
import Testing
@testable import ExerciseCatalog

@Suite("Catalogo esercizi — loader e validazione")
struct ExerciseCatalogLoaderTests {
    @Test("Il catalogo incluso nel bundle si carica con lo schema supportato")
    func bundled() throws {
        let file = try ExerciseCatalogLoader.loadBundled()
        #expect(file.schemaVersion == ExerciseCatalogLoader.supportedSchemaVersion)
        #expect(Set(file.exercises.map(\.id)).count == file.exercises.count)
    }

    @Test("Una voce valida viene decodificata")
    func decodesEntry() throws {
        let json = """
        {"schemaVersion":1,"exercises":[{"id":"bench_press_barbell","nameKey":"exercise.bench_press_barbell",
        "loadType":"external","equipment":["barbell","bench"],"primaryMuscles":["chest"],
        "secondaryMuscles":["triceps","front_delts"]}]}
        """
        let file = try ExerciseCatalogLoader.decode(Data(json.utf8))
        #expect(file.exercises.first?.secondaryMuscles == [.triceps, .frontDelts])
    }

    @Test("Schema non supportato, ID duplicati e JSON corrotto vengono rifiutati")
    func rejects() {
        #expect(throws: CatalogError.unsupportedSchemaVersion(2)) {
            try ExerciseCatalogLoader.decode(Data(#"{"schemaVersion":2,"exercises":[]}"#.utf8))
        }
        let entry = #"{"id":"x","nameKey":"k","loadType":"timed","equipment":[],"primaryMuscles":["abs"],"secondaryMuscles":[]}"#
        #expect(throws: CatalogError.duplicateIdentifier("x")) {
            try ExerciseCatalogLoader.decode(Data(#"{"schemaVersion":1,"exercises":[\#(entry),\#(entry)]}"#.utf8))
        }
        #expect(throws: DecodingError.self) {
            try ExerciseCatalogLoader.decode(Data(#"{"schemaVersion":1,"exercises":[{"id":"y"}]}"#.utf8))
        }
    }
}
