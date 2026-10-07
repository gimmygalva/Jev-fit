import DesignSystem
import Food
import Foundation
import JevCore
import JevDomain
import NutritionEngine
import Persistence
import SwiftUI
import VisionKit

/// Tab "Nutrizione" (SCR-NU-01): totali del giorno contro il target, pasti, copia ieri,
/// giorno completo, pesata rapida e trend del peso.
public struct NutritionTabView: View {
    let service: NutritionPlanService
    let search: FoodSearch
    @State private var day = DayKey(date: Date(), timeZone: .current)
    @State private var entries: [FoodLogEntryRecord] = []
    @State private var totals = NutritionLogRepository.Totals()
    @State private var targets: NutritionPlanService.Targets?
    @State private var isComplete = false
    @State private var addingSlot: MealSlot?
    @State private var weightText = ""

    public init(service: NutritionPlanService, search: FoodSearch) {
        self.service = service
        self.search = search
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Button { move(-1) } label: { Image(systemName: "chevron.left") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Giorno precedente")
                        Spacer()
                        Text(verbatim: day.description).font(.headline).monospacedDigit()
                        Spacer()
                        Button { move(1) } label: { Image(systemName: "chevron.right") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Giorno successivo")
                    }
                    DaySummaryView(totals: totals, targets: targets)
                    Toggle("Giornata completa", isOn: Binding(get: { isComplete }, set: { setComplete($0) }))
                        .accessibilityIdentifier("nutrition.complete")
                }
                ForEach(MealSlot.allCases, id: \.self) { slot in
                    Section {
                        ForEach(entries.filter { $0.mealSlot == slot }, id: \.id) { entry in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(verbatim: entry.foodName ?? quickAddName)
                                    if let grams = entry.grams {
                                        Text(verbatim: "\(grams.formatted(.number.precision(.fractionLength(0...1)))) g")
                                            .font(.caption).foregroundStyle(JevColor.textSecondary)
                                    }
                                }
                                Spacer()
                                Text(verbatim: "\(Int(entry.energyKcal.rounded())) kcal").monospacedDigit()
                            }
                        }
                        .onDelete { offsets in delete(slot: slot, offsets: offsets) }
                        Button("Aggiungi alimento") { addingSlot = slot }
                            .accessibilityIdentifier("nutrition.add.\(slot.rawValue)")
                    } header: {
                        Text(verbatim: slot.displayName)
                    }
                }
                Section {
                    Button("Copia il giorno precedente") { copyPrevious() }
                        .accessibilityIdentifier("nutrition.copy")
                }
                WeightSection(trend: targets?.trend, weightText: $weightText, onSave: saveWeight)
            }
            .navigationTitle("Nutrizione")
            .accessibilityIdentifier("tab.nutrition")
            .task(id: day) { reload() }
            .sheet(item: $addingSlot, onDismiss: reload) { slot in
                AddFoodView(search: search, log: service.log, slot: slot, day: day) { addingSlot = nil }
            }
        }
    }

    private var quickAddName: String { "Aggiunta rapida" }

    private func move(_ days: Int) {
        day = day.adding(days: days)
    }

    private func reload() {
        entries = (try? service.log.entries(day: day)) ?? []
        totals = (try? service.log.totals(day: day)) ?? NutritionLogRepository.Totals()
        targets = try? service.targets(on: day)
        isComplete = (try? service.log.dayStatus(day))?.status == .complete
    }

    private func setComplete(_ value: Bool) {
        _ = try? service.log.setDay(day, status: value ? .complete : .open)
        reload()
    }

    private func delete(slot: MealSlot, offsets: IndexSet) {
        let slotEntries = entries.filter { $0.mealSlot == slot }
        for index in offsets where slotEntries.indices.contains(index) {
            try? service.log.delete(entryID: slotEntries[index].id)
        }
        reload()
    }

    private func copyPrevious() {
        _ = try? service.log.copyDay(from: day.adding(days: -1), to: day)
        reload()
    }

    private func saveWeight() {
        guard let value = WorkoutFormat.parse(weightText) else { return }
        _ = try? service.log.addWeight(kilograms: value, at: Date())
        weightText = ""
        reload()
    }
}

extension MealSlot: @retroactive Identifiable {
    public var id: String { rawValue }
}

extension MealSlot {
    var displayName: String {
        switch self {
        case .breakfast: String(localized: "Colazione")
        case .lunch: String(localized: "Pranzo")
        case .dinner: String(localized: "Cena")
        case .snack: String(localized: "Spuntini")
        }
    }
}

/// Calorie e macro consumati contro il target del giorno.
struct DaySummaryView: View {
    let totals: NutritionLogRepository.Totals
    let targets: NutritionPlanService.Targets?

    var body: some View {
        VStack(alignment: .leading, spacing: JevSpacing.s) {
            row(label: "Calorie", value: totals.energyKcal, target: targets?.kcal, unit: "kcal", color: JevColor.ion)
            row(label: "Proteine", value: totals.proteinG, target: targets?.macros.proteinG, unit: "g", color: JevColor.protein)
            row(label: "Carboidrati", value: totals.carbsG, target: targets?.macros.carbsG, unit: "g", color: JevColor.carbs)
            row(label: "Grassi", value: totals.fatG, target: targets?.macros.fatG, unit: "g", color: JevColor.fat)
            if let targets {
                Text(verbatim: "TDEE \(Int(targets.expenditureKcal.rounded())) kcal · \(Int((targets.expenditureConfidence * 100).rounded()))%")
                    .font(.caption)
                    .foregroundStyle(JevColor.textSecondary)
                    .accessibilityIdentifier("nutrition.tdee")
            }
        }
        .accessibilityIdentifier("nutrition.summary")
    }

    private func row(label: LocalizedStringKey, value: Double, target: Double?, unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: JevSpacing.xs) {
            HStack {
                Text(label)
                Spacer()
                Text(verbatim: target.map { "\(Int(value.rounded())) / \(Int($0.rounded())) \(unit)" } ?? "\(Int(value.rounded())) \(unit)")
                    .monospacedDigit()
            }
            .font(.subheadline)
            if let target, target > 0 {
                ProgressView(value: min(value / target, 1))
                    .tint(value > target * 1.05 ? JevColor.warning : color)
            }
        }
    }
}

/// Pesata rapida e trend (SCR-BD-02 ridotta).
struct WeightSection: View {
    let trend: WeightTrend.Result?
    @Binding var weightText: String
    let onSave: () -> Void

    var body: some View {
        Section {
            if let trend {
                HStack {
                    Text("Trend")
                    Spacer()
                    Text(verbatim: WorkoutFormat.kilograms(trend.trendKg)).monospacedDigit()
                }
                HStack {
                    Text("Variazione settimanale")
                    Spacer()
                    Text(verbatim: "\(trend.slopeKgPerWeek >= 0 ? "+" : "")\(trend.slopeKgPerWeek.formatted(.number.precision(.fractionLength(2)))) kg")
                        .monospacedDigit()
                }
            }
            HStack {
                TextField("Peso di oggi (kg)", text: $weightText)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("nutrition.weight.field")
                Button("Salva", action: onSave)
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("nutrition.weight.save")
            }
        } header: {
            Text("Peso")
        }
    }
}

/// Aggiunta di un alimento (SCR-NU-02): ricerca offline + online, barcode, ricette, aggiunta rapida.
struct AddFoodView: View {
    let search: FoodSearch
    let log: NutritionLogRepository
    let slot: MealSlot
    let day: DayKey
    let onClose: () -> Void

    @State private var query = ""
    @State private var results: [FoodCandidate] = []
    @State private var selected: FoodCandidate?
    @State private var gramsText = "100"
    @State private var barcode = ""
    @State private var scanning = false
    @State private var quickKcal = ""
    @State private var notFound = false
    @State private var recipes: [RecipeRecord] = []

    var body: some View {
        NavigationStack {
            List {
                if let selected {
                    Section {
                        Text(verbatim: selected.name).font(.headline)
                        if let brand = selected.brand { Text(verbatim: brand).foregroundStyle(JevColor.textSecondary) }
                        TextField("Grammi", text: $gramsText)
                            .keyboardType(.decimalPad)
                            .accessibilityIdentifier("food.grams")
                        if let grams = WorkoutFormat.parse(gramsText), grams > 0 {
                            let n = selected.per100g.scaled(toGrams: grams)
                            Text(verbatim: "\(Int(n.energyKcal.rounded())) kcal · P \(Int(n.proteinGrams.rounded())) · C \(Int(n.carbohydrateGrams.rounded())) · G \(Int(n.fatGrams.rounded()))")
                                .monospacedDigit()
                        }
                        Button("Aggiungi") { add(selected) }
                            .buttonStyle(JevPrimaryButtonStyle())
                            .accessibilityIdentifier("food.confirm")
                    }
                } else {
                    Section {
                        TextField("Cerca un alimento", text: $query)
                            .accessibilityIdentifier("food.search")
                            .onSubmit { Task { await runSearch() } }
                        ForEach(results) { food in
                            Button {
                                selected = food
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(verbatim: food.name)
                                        if let brand = food.brand {
                                            Text(verbatim: brand).font(.caption).foregroundStyle(JevColor.textSecondary)
                                        }
                                    }
                                    Spacer()
                                    Text(verbatim: "\(Int(food.per100g.energyKcal.rounded())) kcal/100 g")
                                        .font(.caption).foregroundStyle(JevColor.textSecondary)
                                }
                            }
                            .accessibilityIdentifier("food.result")
                        }
                    }
                    Section {
                        HStack {
                            TextField("Codice a barre", text: $barcode)
                                .keyboardType(.numberPad)
                            Button("Cerca") { Task { await lookup(barcode) } }
                                .buttonStyle(.borderless)
                        }
                        if DataScannerViewController.isSupported {
                            Button("Scansiona") { scanning = true }
                        }
                        if notFound {
                            JevInlineNotice("Prodotto non trovato: cercalo per nome o usa l'aggiunta rapida.")
                        }
                    } header: {
                        Text("Codice a barre")
                    }
                    if !recipes.isEmpty {
                        Section {
                            ForEach(recipes, id: \.id) { recipe in
                                Button {
                                    _ = try? log.logRecipe(recipe.id, servings: 1, slot: slot, day: day)
                                    onClose()
                                } label: {
                                    Text(verbatim: recipe.name)
                                }
                            }
                        } header: {
                            Text("Ricette")
                        }
                    }
                    Section {
                        HStack {
                            TextField("Calorie", text: $quickKcal)
                                .keyboardType(.numberPad)
                                .accessibilityIdentifier("food.quick.kcal")
                            Button("Aggiungi") { quickAdd() }
                                .buttonStyle(.borderless)
                                .accessibilityIdentifier("food.quick.add")
                        }
                    } header: {
                        Text("Aggiunta rapida")
                    }
                }
            }
            .navigationTitle(Text(verbatim: slot.displayName))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { onClose() }
                }
            }
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(250))
                await runSearch(includeOnline: false)
            }
            .onAppear { recipes = (try? log.recipes()) ?? [] }
            .sheet(isPresented: $scanning) {
                BarcodeScannerView { code in
                    scanning = false
                    barcode = code
                    Task { await lookup(code) }
                }
                .ignoresSafeArea()
            }
        }
    }

    private func runSearch(includeOnline: Bool = true) async {
        results = await search.search(query, includeOnline: includeOnline)
    }

    private func lookup(_ code: String) async {
        notFound = false
        if let found = await search.lookup(barcode: code.trimmingCharacters(in: .whitespaces)) {
            selected = found
        } else {
            notFound = true
        }
    }

    private func add(_ food: FoodCandidate) {
        guard let grams = WorkoutFormat.parse(gramsText) else { return }
        let source: FoodSource = food.source == OpenFoodFactsProvider.sourceName ? .openFoodFacts : .catalog
        _ = try? log.log(source: source, sourceID: food.sourceID, name: food.name, per100g: food.per100g,
                         grams: grams, slot: slot, day: day)
        onClose()
    }

    private func quickAdd() {
        guard let kcal = WorkoutFormat.parse(quickKcal) else { return }
        _ = try? log.quickAdd(energyKcal: kcal, slot: slot, day: day)
        onClose()
    }
}

/// Scanner dei codici a barre con VisionKit (solo su dispositivi supportati).
struct BarcodeScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean8, .ean13, .upce])],
            qualityLevel: .balanced, recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false, isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var delivered = false

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            guard !delivered else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let value = barcode.payloadStringValue, Barcode.isValid(value) {
                    delivered = true
                    dataScanner.stopScanning()
                    onCode(value)
                    return
                }
            }
        }
    }
}
