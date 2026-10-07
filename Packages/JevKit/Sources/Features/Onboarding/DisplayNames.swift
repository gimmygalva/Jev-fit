import JevCore
import JevDomain
import Persistence
import SwiftUI

// Etichette italiane dei valori di dominio (ADR-015: le chiavi sono il testo italiano e stanno
// nello String Catalog dell'app). Testi di obiettivi ed esperienza da UF-01.

extension GoalType {
    var title: LocalizedStringKey {
        switch self {
        case .strength: "Forza"
        case .hypertrophy: "Ipertrofia"
        case .maintenance: "Mantenimento"
        case .recomposition: "Ricomposizione"
        case .fatLoss: "Dimagrimento"
        case .generalFitness: "Fitness generale"
        }
    }

    var effect: LocalizedStringKey {
        switch self {
        case .strength: "Carichi in crescita sui fondamentali, calorie di mantenimento"
        case .hypertrophy: "Volume alto e leggero surplus calorico"
        case .maintenance: "Mantieni peso e prestazioni con meno volume"
        case .recomposition: "Calorie vicine al mantenimento, proteine alte"
        case .fatLoss: "Deficit moderato, proteine alte, volume mantenuto"
        case .generalFitness: "Allenamento equilibrato e sostenibile"
        }
    }
}

extension ExperienceLevel {
    var title: LocalizedStringKey {
        switch self {
        case .beginner: "Principiante"
        case .intermediate: "Intermedio"
        case .advanced: "Avanzato"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .beginner: "Meno di 1 anno di allenamento costante"
        case .intermediate: "Da 1 a 4 anni"
        case .advanced: "Più di 4 anni"
        }
    }
}

extension ActivityLevel {
    var title: LocalizedStringKey {
        switch self {
        case .sedentary: "Sedentario"
        case .light: "Leggero"
        case .moderate: "Moderato"
        case .high: "Alto"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .sedentary: "Lavoro alla scrivania, meno di 5.000 passi al giorno"
        case .light: "In piedi a tratti, 5.000–7.500 passi"
        case .moderate: "Spesso in movimento, 7.500–10.000 passi"
        case .high: "Lavoro fisico o più di 10.000 passi"
        }
    }
}

extension SplitType {
    var title: LocalizedStringKey {
        switch self {
        case .fullBody: "Full Body"
        case .upperLower: "Upper/Lower"
        case .pushPullLegs: "Push Pull Legs"
        case .torsoLimbs: "Torso/Arti"
        case .hybrid: "Ibrido"
        case .custom: "Personalizzato"
        }
    }
}

extension Equipment {
    var title: LocalizedStringKey {
        switch self {
        case .barbell: "Bilanciere"
        case .dumbbell: "Manubri"
        case .kettlebell: "Kettlebell"
        case .cable: "Cavi"
        case .machine: "Macchine"
        case .smithMachine: "Multipower"
        case .ezBar: "Bilanciere EZ"
        case .trapBar: "Trap bar"
        case .pullUpBar: "Sbarra"
        case .dipStation: "Parallele"
        case .bench: "Panca"
        case .resistanceBand: "Elastici"
        case .bodyweight: "Corpo libero"
        }
    }
}

extension EquipmentPreset {
    var title: LocalizedStringKey {
        switch self {
        case .fullGym: "Palestra completa"
        case .homeGym: "Home gym"
        case .dumbbellsOnly: "Solo manubri"
        case .bodyweight: "Corpo libero"
        }
    }
}

extension MuscleGroup {
    var title: LocalizedStringKey {
        switch self {
        case .chest: "Petto"
        case .lats: "Dorsali"
        case .upperBack: "Alta schiena"
        case .frontDelts: "Deltoidi anteriori"
        case .sideDelts: "Deltoidi laterali"
        case .rearDelts: "Deltoidi posteriori"
        case .biceps: "Bicipiti"
        case .triceps: "Tricipiti"
        case .forearms: "Avambracci"
        case .abs: "Addome"
        case .obliques: "Obliqui"
        case .lowerBack: "Lombari"
        case .glutes: "Glutei"
        case .quads: "Quadricipiti"
        case .hamstrings: "Femorali"
        case .adductors: "Adduttori"
        case .calves: "Polpacci"
        }
    }
}

extension BodyArea {
    var title: LocalizedStringKey {
        switch self {
        case .shoulder: "Spalla"
        case .elbow: "Gomito"
        case .wrist: "Polso"
        case .neck: "Collo"
        case .lowerBack: "Zona lombare"
        case .hip: "Anca"
        case .knee: "Ginocchio"
        case .ankle: "Caviglia"
        case .other: "Altro"
        }
    }
}

extension LimitationSeverity {
    var title: LocalizedStringKey {
        switch self {
        case .mild: "Lieve"
        case .moderate: "Moderato"
        }
    }
}

extension MacroMode {
    var title: LocalizedStringKey {
        switch self {
        case .auto: "Automatica"
        case .assisted: "Assistita"
        case .manual: "Manuale"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .auto: "JEV calcola calorie e macro e li aggiorna ogni settimana"
        case .assisted: "Scegli tu la ripartizione tra carboidrati e grassi, le proteine restano protette"
        case .manual: "Imposti tu tutti i valori; JEV ti avvisa se scendi sotto i minimi"
        }
    }
}

extension BiologicalSex {
    var title: LocalizedStringKey {
        switch self {
        case .male: "Maschile"
        case .female: "Femminile"
        }
    }
}

/// Giorni della settimana, 1 = lunedì (formato di `training_preferences` e `app_settings`).
enum Weekday {
    static let all = Array(1...7)

    static func short(_ day: Int) -> LocalizedStringKey {
        switch day {
        case 1: "Lun"
        case 2: "Mar"
        case 3: "Mer"
        case 4: "Gio"
        case 5: "Ven"
        case 6: "Sab"
        default: "Dom"
        }
    }

    static func long(_ day: Int) -> LocalizedStringKey {
        switch day {
        case 1: "Lunedì"
        case 2: "Martedì"
        case 3: "Mercoledì"
        case 4: "Giovedì"
        case 5: "Venerdì"
        case 6: "Sabato"
        default: "Domenica"
        }
    }
}

extension OnboardingIssue {
    var message: LocalizedStringKey {
        switch self {
        case .missingSelection: "Scegli un'opzione per continuare."
        case .invalidWeight: "Inserisci un peso valido."
        case .invalidHeight: "Inserisci un'altezza valida, in centimetri."
        case .invalidAge: "Controlla l'età inserita."
        case .invalidBodyFat: "La percentuale di grasso deve essere tra 2 e 70."
        case .appNotForMinors: "JEV FIT non è pensata per chi ha meno di 16 anni."
        case .goalBlocked(.belowMinimumAppAge): "JEV FIT non è pensata per chi ha meno di 16 anni."
        case .goalBlocked(.minorNoDeficit): "Sotto i 18 anni non proponiamo obiettivi di dimagrimento. Scegli un altro obiettivo."
        case .goalBlocked(.pregnancyNoDeficit): "In gravidanza o allattamento non proponiamo un deficit calorico. Scegli un altro obiettivo."
        case .goalBlocked(.underweightNoLoss): "Con i dati inseriti il dimagrimento non è indicato. Scegli un altro obiettivo."
        case .targetBelowHealthyWeight: "Questo peso obiettivo è sotto la soglia di peso sano per la tua altezza."
        case .targetIncoherent: "Il peso obiettivo non va nella direzione dell'obiettivo scelto."
        }
    }
}
