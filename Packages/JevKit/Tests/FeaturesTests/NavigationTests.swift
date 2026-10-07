import Foundation
import Testing
@testable import Features

@Suite("Deep link jevfit:// e router")
@MainActor
struct NavigationTests {
    @Test("I link documentati aprono la tab giusta", arguments: [
        ("jevfit://today", RootTab.today),
        ("jevfit://profile", .today),
        ("jevfit://weight/new", .today),
        ("jevfit://workout", .training),
        ("jevfit://workout/session/0192c0de-0000-7000-8000-000000000000", .training),
        ("jevfit://exercises/bench_press", .training),
        ("jevfit://nutrition/day/2026-10-06", .nutrition),
        ("jevfit://nutrition/log?meal=lunch&date=", .nutrition),
        ("jevfit://body/muscle/chest", .body),
        ("jevfit://progress", .progress),
        ("JEVFIT://WORKOUT", .training),
        ("jevfit:///nutrition", .nutrition),
    ] as [(String, RootTab)])
    func knownLinks(url: String, tab: RootTab) throws {
        let parsed = try #require(URL(string: url))
        let link = try #require(DeepLink(url: parsed))
        #expect(link == .tab(tab))
        #expect(link.targetTab == tab)
    }

    @Test("Schemi e percorsi sconosciuti vengono ignorati", arguments: [
        "https://jevfit.app/today", "jevfit://", "jevfit://unknown", "otherapp://today",
    ])
    func unknownLinks(url: String) throws {
        let parsed = try #require(URL(string: url))
        #expect(DeepLink(url: parsed) == nil)
    }

    @Test("Il router cambia tab con un deep link valido e ignora gli altri")
    func routerApplies() throws {
        let router = AppRouter()
        let nutrition = try #require(URL(string: "jevfit://nutrition"))
        let unknown = try #require(URL(string: "jevfit://boh"))
        #expect(router.handle(nutrition))
        #expect(router.selectedTab == .nutrition)
        #expect(!router.handle(unknown))
        #expect(router.selectedTab == .nutrition)
    }

    @Test("Durante l'onboarding il link resta in attesa e si applica alla fine")
    func pendingDuringOnboarding() throws {
        let router = AppRouter(isOnboardingActive: true)
        let body = try #require(URL(string: "jevfit://body"))
        router.handle(body)
        #expect(router.selectedTab == .today)
        #expect(router.pendingLink == .tab(.body))
        router.onboardingFinished()
        #expect(!router.isOnboardingActive)
        #expect(router.selectedTab == .body)
        #expect(router.pendingLink == nil)
    }

    @Test("Senza link in attesa, la fine dell'onboarding porta a Oggi")
    func finishGoesToToday() {
        let router = AppRouter(isOnboardingActive: true)
        router.selectedTab = .progress
        router.onboardingFinished()
        #expect(router.selectedTab == .today)
    }

    @Test("La chiusura di sistema del cover non interrompe l'onboarding")
    func coverCannotBeDismissed() {
        let router = AppRouter(isOnboardingActive: true)
        router.isOnboardingPresented = false
        #expect(router.isOnboardingPresented)
    }
}
