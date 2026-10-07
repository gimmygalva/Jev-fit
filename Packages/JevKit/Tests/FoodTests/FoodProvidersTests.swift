import Foundation
import JevDomain
import Testing
@testable import Food

@Suite("Provider di alimenti: database locale, Open Food Facts, ricerca combinata (M9)")
struct FoodProvidersTests {
    @Test("Database locale incluso: 80 alimenti, ricerca per parole senza accenti")
    func local() async throws {
        let provider = try LocalFoodProvider.bundled()
        #expect(provider.foods.count == 80)
        #expect(provider.worksOffline)
        let chicken = try await provider.search(FoodQuery("POLLO"), limit: 10)
        #expect(chicken.map(\.sourceID) == ["chicken_breast_raw"])
        let pasta = try await provider.search(FoodQuery("pasta"), limit: 10)
        #expect(pasta.first?.name.hasPrefix("Pasta") == true)
        #expect(pasta.count == 2)
        #expect(try await provider.search(FoodQuery(""), limit: 10).isEmpty)
        #expect(try await provider.lookup(barcode: "8076809513753") == nil)
        let oil = try #require(provider.foods.first { $0.sourceID == "olive_oil" })
        #expect(oil.per100g.energyKcal == 899)
    }

    @Test("Open Food Facts: prodotto valido, nutrienti come stringa, energia in kJ")
    func parseProduct() throws {
        let json = """
        {"status": 1, "code": "8076809513753", "product": {"product_name": "Spaghetti n.5", "brands": "Barilla, Barilla G.R.",
         "nutriments": {"energy-kcal_100g": 359, "proteins_100g": "12,5", "carbohydrates_100g": 71.2, "fat_100g": 2,
         "fiber_100g": 3, "nova-group": 1}}}
        """
        let food = try #require(try OpenFoodFactsProvider.parseProduct(Data(json.utf8)))
        #expect(food.name == "Spaghetti n.5" && food.brand == "Barilla")
        #expect(food.barcode == "8076809513753" && food.source == "open_food_facts")
        #expect(food.per100g.proteinGrams == 12.5 && food.per100g.energyKcal == 359)
        let kilojoules = """
        {"status": 1, "code": "96385074", "product": {"product_name_it": "Yogurt", "nutriments":
         {"energy_100g": 418.4, "proteins_100g": 4, "carbohydrates_100g": 5, "fat_100g": 3}}}
        """
        let yogurt = try #require(try OpenFoodFactsProvider.parseProduct(Data(kilojoules.utf8)))
        #expect(abs(yogurt.per100g.energyKcal - 100) < 1e-9)
    }

    @Test("Open Food Facts: prodotti inutilizzabili scartati")
    func rejectInvalid() throws {
        let missing = #"{"status": 0, "code": "123"}"#
        #expect(try OpenFoodFactsProvider.parseProduct(Data(missing.utf8)) == nil)
        let noName = #"{"status": 1, "code": "96385074", "product": {"nutriments": {"energy-kcal_100g": 100, "proteins_100g": 1, "carbohydrates_100g": 1, "fat_100g": 1}}}"#
        #expect(try OpenFoodFactsProvider.parseProduct(Data(noName.utf8)) == nil)
        let absurd = #"{"status": 1, "code": "96385074", "product": {"product_name": "X", "nutriments": {"energy-kcal_100g": 100, "proteins_100g": 60, "carbohydrates_100g": 60, "fat_100g": 1}}}"#
        #expect(try OpenFoodFactsProvider.parseProduct(Data(absurd.utf8)) == nil)
        let search = #"{"products": [{"code": "96385074", "product_name": "A", "nutriments": {"energy-kcal_100g": 50, "proteins_100g": 1, "carbohydrates_100g": 10, "fat_100g": 0}}, {"code": "1"}]}"#
        #expect(try OpenFoodFactsProvider.parseSearch(Data(search.utf8)).map(\.sourceID) == ["96385074"])
    }

    struct Fake: FoodProvider {
        var identifier: String
        var worksOffline: Bool
        var items: [FoodCandidate]
        var fails = false
        func search(_ query: FoodQuery, limit: Int) async throws -> [FoodCandidate] {
            if fails { throw URLError(.notConnectedToInternet) }
            return Array(items.prefix(limit))
        }
        func lookup(barcode: String) async throws -> FoodCandidate? {
            if fails { throw URLError(.notConnectedToInternet) }
            return items.first { $0.barcode == barcode }
        }
    }

    private func food(_ source: String, _ id: String, barcode: String? = nil) -> FoodCandidate {
        FoodCandidate(source: source, sourceID: id, name: id, barcode: barcode,
                      per100g: NutrientProfile(energyKcal: 100, proteinGrams: 1, carbohydrateGrams: 1, fatGrams: 1))
    }

    @Test("Ricerca combinata: prima offline, senza duplicati; un provider online in errore non blocca")
    func combined() async {
        let online = Fake(identifier: "on", worksOffline: false, items: [food("on", "b"), food("off", "a")])
        let offline = Fake(identifier: "off", worksOffline: true, items: [food("off", "a")])
        let search = FoodSearch(providers: [online, offline])
        #expect(await search.search("x").map(\.id) == ["off:a", "on:b"])
        #expect(await search.search("x", includeOnline: false).map(\.id) == ["off:a"])
        #expect(await search.search("   ").isEmpty)
        let broken = FoodSearch(providers: [Fake(identifier: "on", worksOffline: false, items: [], fails: true), offline])
        #expect(await broken.search("x").map(\.id) == ["off:a"])
        let barcodes = FoodSearch(providers: [Fake(identifier: "on", worksOffline: false,
                                                   items: [food("on", "c", barcode: "96385074")])])
        #expect(await barcodes.lookup(barcode: "96385074")?.sourceID == "c")
        #expect(await barcodes.lookup(barcode: "123") == nil)
        #expect(await broken.lookup(barcode: "96385074") == nil)
    }
}
