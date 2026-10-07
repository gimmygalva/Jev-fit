// swift-tools-version: 6.0
// JevEngines — Livello 2 (deterministic engines) + contratti condivisi.
// REGOLA: questo package dipende solo da Foundation. Niente UIKit, SwiftUI, HealthKit, GRDB.
// Deve compilare e passare i test su iOS, macOS e Linux (`swift test`). Vedi ADR-003.

import PackageDescription

let package = Package(
    name: "JevEngines",
    defaultLocalization: "it",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "JevCore", targets: ["JevCore"]),
        .library(name: "JevDomain", targets: ["JevDomain"]),
        .library(name: "ExerciseCatalog", targets: ["ExerciseCatalog"]),
        .library(name: "WorkoutEngine", targets: ["WorkoutEngine"]),
        .library(name: "NutritionEngine", targets: ["NutritionEngine"]),
        .library(name: "RecoveryEngine", targets: ["RecoveryEngine"]),
        .library(name: "CheckInEngine", targets: ["CheckInEngine"]),
        .library(name: "CoachKit", targets: ["CoachKit"]),
    ],
    targets: [
        // Fondamenta: unità, giorni locali, identificatori, statistica.
        .target(name: "JevCore"),
        // Tipi di dominio condivisi + EngineConfig (fonte unica delle soglie, ADR-013).
        .target(name: "JevDomain", dependencies: ["JevCore"]),
        // Catalogo esercizi originale (JSON) + loader + validazione.
        .target(
            name: "ExerciseCatalog",
            dependencies: ["JevDomain"],
            resources: [.process("Resources")]
        ),
        .target(name: "WorkoutEngine", dependencies: ["JevCore", "JevDomain", "ExerciseCatalog"]),
        .target(name: "NutritionEngine", dependencies: ["JevCore", "JevDomain"]),
        .target(name: "RecoveryEngine", dependencies: ["JevCore", "JevDomain"]),
        .target(
            name: "CheckInEngine",
            dependencies: ["JevCore", "JevDomain", "WorkoutEngine", "NutritionEngine", "RecoveryEngine"]
        ),
        .target(name: "CoachKit", dependencies: ["JevCore", "JevDomain", "CheckInEngine"]),

        .testTarget(name: "JevCoreTests", dependencies: ["JevCore"]),
        .testTarget(name: "JevDomainTests", dependencies: ["JevDomain"]),
        .testTarget(name: "ExerciseCatalogTests", dependencies: ["ExerciseCatalog"]),
        .testTarget(name: "WorkoutEngineTests", dependencies: ["WorkoutEngine", "JevDomain", "JevCore", "ExerciseCatalog"]),
        .testTarget(name: "NutritionEngineTests", dependencies: ["NutritionEngine", "JevDomain"]),
        .testTarget(name: "RecoveryEngineTests", dependencies: ["RecoveryEngine", "JevDomain"]),
        .testTarget(name: "CheckInEngineTests", dependencies: ["CheckInEngine"]),
        .testTarget(name: "CoachKitTests", dependencies: ["CoachKit"]),
    ]
)
