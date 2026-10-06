// swift-tools-version: 6.0
// JevKit — Livello 1 (dati, servizi di sistema) e UI. Solo iOS.
// Dipende da JevEngines per i tipi di dominio e gli engine. Gli engine NON dipendono da qui.

import PackageDescription

let package = Package(
    name: "JevKit",
    defaultLocalization: "it",
    platforms: [
        .iOS(.v18),
    ],
    products: [
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "Sync", targets: ["Sync"]),
        .library(name: "Health", targets: ["Health"]),
        .library(name: "Food", targets: ["Food"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "Features", targets: ["Features"]),
    ],
    dependencies: [
        .package(path: "../JevEngines"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "Persistence",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "JevCore", package: "JevEngines"),
                .product(name: "JevDomain", package: "JevEngines"),
            ]
        ),
        .target(
            name: "Sync",
            dependencies: [
                "Persistence",
                // Solo i moduli necessari (SECURITY.md §16): niente Realtime/Storage.
                .product(name: "Auth", package: "supabase-swift"),
                .product(name: "PostgREST", package: "supabase-swift"),
                .product(name: "Functions", package: "supabase-swift"),
            ]
        ),
        .target(
            name: "Health",
            dependencies: [
                .product(name: "JevCore", package: "JevEngines"),
                .product(name: "JevDomain", package: "JevEngines"),
            ]
        ),
        .target(
            name: "Food",
            dependencies: [
                .product(name: "JevCore", package: "JevEngines"),
                .product(name: "JevDomain", package: "JevEngines"),
            ]
        ),
        .target(
            name: "DesignSystem",
            dependencies: [
                .product(name: "JevCore", package: "JevEngines"),
                .product(name: "JevDomain", package: "JevEngines"),
            ]
        ),
        .target(
            name: "Features",
            dependencies: [
                "Persistence", "Sync", "Health", "Food", "DesignSystem",
                .product(name: "WorkoutEngine", package: "JevEngines"),
                .product(name: "NutritionEngine", package: "JevEngines"),
                .product(name: "RecoveryEngine", package: "JevEngines"),
                .product(name: "CheckInEngine", package: "JevEngines"),
                .product(name: "CoachKit", package: "JevEngines"),
                .product(name: "ExerciseCatalog", package: "JevEngines"),
            ]
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: ["Persistence", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(name: "FoodTests", dependencies: ["Food"]),
        .testTarget(name: "FeaturesTests", dependencies: ["Features"]),
    ]
)
