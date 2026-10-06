import Testing
@testable import Food

@Suite("Food — normalizzazione query e barcode")
struct FoodQueryTests {
    @Test("Accenti, maiuscole e spazi non contano")
    func normalization() {
        #expect(FoodQuery("  Pàsta   INTEGRALE ").normalized == "pasta integrale")
        #expect(FoodQuery("caffè").normalized == FoodQuery("CAFFE").normalized)
        #expect(FoodQuery("   ").isEmpty)
    }

    @Test("Check digit GS1", arguments: [
        ("8076809513753", true),   // EAN-13 valido
        ("8076809513754", false),  // check digit errato
        ("96385074", true),        // EAN-8 valido
        ("036000291452", true),    // UPC-A valido
        ("12345", false),
        ("80768095137a3", false),
        ("", false),
    ])
    func barcode(code: String, valid: Bool) {
        #expect(Barcode.isValid(code) == valid)
    }
}
