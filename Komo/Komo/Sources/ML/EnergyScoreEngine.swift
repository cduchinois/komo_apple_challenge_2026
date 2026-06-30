import Foundation

// MARK: - Mood Label (contrat d'équipe — NE PAS CHANGER sans accord de tous)
//
// C'est l'interface entre :
//   • Sacha  → produit le label via le pipeline CoreML
//   • Julien → anime le blob selon ce label
//   • Yue    → affiche la phrase first-person dans l'UI
//   • Jade   → orchestre le flow de démo

enum MoodLabel: String, CaseIterable {
    case lumineux = "lumineux"   // 80-100 : top forme, récupéré, actif
    case serein   = "serein"     // 60-79  : bon équilibre, pas de signal négatif majeur
    case agité    = "agité"      // 40-59  : stress détecté, ou sommeil moyen
    case fatigué  = "fatigué"    // 20-39  : peu dormis, faible HRV, peu de pas
    case lourd    = "lourd"      // 0-19   : surcharge : stress + dette sommeil + agenda chargé

    /// Localized display name — reads from Localizable.xcstrings
    /// EN: "Radiant" / FR: "Lumineux" / ES: "Radiante" / DE: "Strahlend" / ZH: "光彩照人" / JA: "輝いている"
    var localizedName: String {
        NSLocalizedString("mood.\(rawValue)", comment: "MoodLabel display name")
    }

    /// Device language tag for Foundation Models instruction
    static var deviceLanguageInstruction: String {
        let langCode = Locale.current.language.languageCode?.identifier ?? "en"
        switch langCode {
        case "fr": return "Réponds UNIQUEMENT en français."
        case "es": return "Responde ÚNICAMENTE en español."
        case "de": return "Antworte NUR auf Deutsch."
        case "zh": return "请只用中文回答。"
        case "ja": return "必ず日本語で答えてください。"
        case "pt": return "Responda APENAS em português."
        default:   return "Reply ONLY in English."
        }
    }

    /// First-person context — localized for the current device language
    var firstPersonContext: String {
        let langCode = Locale.current.language.languageCode?.identifier ?? "en"
        switch self {
        case .lumineux:
            switch langCode {
            case "fr": return "Je me sens énergisé et en pleine forme aujourd'hui."
            case "es": return "Me siento lleno de energía y en gran forma hoy."
            case "de": return "Ich fühle mich heute energiegeladen und in Topform."
            case "zh": return "今天我感到精力充沛，状态极佳。"
            case "ja": return "今日はエネルギーに満ち溢れ、絶好調です。"
            case "pt": return "Hoje me sinto cheio de energia e em ótima forma."
            default:   return "I feel energized and in great shape today."
            }
        case .serein:
            switch langCode {
            case "fr": return "Je suis calme et équilibré, pas de signal d'alarme."
            case "es": return "Estoy tranquilo y equilibrado, sin señales de alarma."
            case "de": return "Ich bin ruhig und ausgeglichen, keine Alarmsignale."
            case "zh": return "我感到平静和平衡，没有警报信号。"
            case "ja": return "穏やかでバランスが取れており、警告サインはありません。"
            case "pt": return "Estou calmo e equilibrado, sem sinais de alerta."
            default:   return "I'm calm and balanced, no alarm signals."
            }
        case .agité:
            switch langCode {
            case "fr": return "Je ressens une certaine tension, mon corps est un peu sous pression."
            case "es": return "Siento cierta tensión, mi cuerpo está un poco bajo presión."
            case "de": return "Ich spüre eine gewisse Anspannung, mein Körper steht etwas unter Druck."
            case "zh": return "我感到有些紧张，我的身体承受着一定的压力。"
            case "ja": return "少し緊張感があり、体にストレスがかかっています。"
            case "pt": return "Sinto certa tensão, meu corpo está sob um pouco de pressão."
            default:   return "I feel some tension, my body is under a bit of pressure."
            }
        case .fatigué:
            switch langCode {
            case "fr": return "Je suis fatigué, mon corps manque de récupération."
            case "es": return "Estoy cansado, mi cuerpo necesita recuperarse."
            case "de": return "Ich bin müde, mein Körper braucht Erholung."
            case "zh": return "我很疲惫，我的身体需要恢复。"
            case "ja": return "疲れています。体が回復を必要としています。"
            case "pt": return "Estou cansado, meu corpo precisa de recuperação."
            default:   return "I'm tired, my body needs recovery."
            }
        case .lourd:
            switch langCode {
            case "fr": return "Je suis épuisé — surcharge de stress et manque de sommeil."
            case "es": return "Estoy agotado — estrés excesivo y falta de sueño."
            case "de": return "Ich bin erschöpft — zu viel Stress und zu wenig Schlaf."
            case "zh": return "我精疲力竭——压力过大，睡眠不足。"
            case "ja": return "消耗しています — ストレス過多と睡眠不足。"
            case "pt": return "Estou exausto — excesso de estresse e falta de sono."
            default:   return "I'm exhausted — too much stress and not enough sleep."
            }
        }
    }
}

// MARK: - Energy Score Result

struct EnergyScoreResult {
    let energyScore: Int        // 0-100
    let moodLabel: MoodLabel
    let breakdown: ScoreBreakdown
}

// MARK: - Score Breakdown
//
// Architecture Recovery / Load (modèle Oura + WHOOP + WESAD)
// Sources :
//   • Shaffer & Ginsberg (2017) Front. Public Health — HRV biomarqueur primaire
//   • Oura Ring Validation Study (2021) — readiness = f(HRV, rHR, sommeil, activité)
//   • Walker (2017) Why We Sleep — privation sommeil → -40% perf. pour 6h vs 8h
//   • Nazari et al. (2023) WESAD stress — fréquence épisodes > durée

struct ScoreBreakdown {
    // RECOVERY (0-100 : ce que ton corps a accumulé comme ressources)
    let hrvRecovery: Int        // 0-35  HRV SDNN — biomarqueur primaire (Shaffer & Ginsberg)
    let sleepRecovery: Int      // 0-30  qualité sommeil (Walker 2017)
    let activityRecovery: Int   // 0-20  pas + exercise DOUX (zones 1-2)
    let restingHRRecovery: Int  // 0-15  FC repos basse = bonne récup (Oura)

    // LOAD — ce que la journée a consommé comme ressources
    let stressLoad: Int             // 0-25  épisodes stress WESAD CoreML (physiologique)
    let workoutPhysicalLoad: Int    // 0-15  exercise INTENSE zones 4-5 (TRIMP, Banister 1991)
    let behavioralLoad: Int         // 0-15  agenda + screen time (comportemental)

    // Score final = Recovery - Load, clamp 0-100
    var recoveryTotal: Int { hrvRecovery + sleepRecovery + activityRecovery + restingHRRecovery }
    var loadTotal: Int { stressLoad + workoutPhysicalLoad + behavioralLoad }
}

// MARK: - EnergyScoreEngine
//
// PIPELINE :
//   DayAnalysis (CoreML réel ou Mock)
//       ↓
//   score(signals) → EnergyScoreResult
//       ↓
//   MoodLabel → Blob Julien + Phrase Foundation Models

struct EnergyScoreEngine {

    // MARK: - Point d'entrée principal

    /// Modèle Recovery / Load :
    ///   Score = f(Recovery) - f(Load)  normalisé 0-100
    ///
    /// Recovery (100 pts max) :
    ///   HRV SDNN     : 35 pts  — Shaffer & Ginsberg 2017, biomarqueur primaire SNA
    ///   Sommeil      : 30 pts  — Walker 2017, impact cognitif -40% en dessous de 7h
    ///   Activité     : 20 pts  — effet anabolique : pas + exercise
    ///   FC repos     : 15 pts  — Oura 2021, FC repos basse = bon état cardio
    ///
    /// Load (40 pts max) :
    ///   Stress WESAD : 25 pts  — Nazari 2023, épisodes stress CoreML (physiologique)
    ///   Behavioral   : 15 pts  — agenda + screen time (charge cognitive)
    ///
    /// Score final = (Recovery / 100) * 100 - (Load / 40) * 40, clamp 0-100
    ///
    /// - Parameters:
    ///   - analysis: DayAnalysis produit par HealthAnalyzer (CoreML)
    ///   - baseline: Baseline personnelle sur 14j (optionnelle). Si fournie et fiable,
    ///               les seuils HRV et FC repos sont ajustés à l'utilisateur (modèle Whoop).
    static func score(from analysis: DayAnalysis, baseline: PersonalBaseline? = nil) -> EnergyScoreResult {

        // --- RECOVERY ---
        let hrvRecovery      = computeHRVRecovery(analysis, baseline: baseline)         // 0-35
        let sleepRecovery    = computeSleepRecovery(analysis)       // 0-30
        let activityRecovery = computeActivityRecovery(analysis)    // 0-20 (zones 1-2 seulement)
        let restingHRRecovery = computeRestingHRRecovery(analysis, baseline: baseline)  // 0-15

        let rawRecovery = Double(hrvRecovery + sleepRecovery + activityRecovery + restingHRRecovery)

        // --- LOAD ---
        let stressLoad          = computeStressLoad(analysis)           // 0-25 (CoreML WESAD)
        let workoutPhysicalLoad = computeWorkoutPhysicalLoad(analysis)  // 0-15 (zones 4-5 HIIT)
        let behavioralLoad      = computeBehavioralLoad(analysis)       // 0-15 (agenda + screen)

        let rawLoad = Double(stressLoad + workoutPhysicalLoad + behavioralLoad)
        // Load max = 25 + 15 + 15 = 55 — normalisé → impact sur 55 pts max du score
        let loadImpact = rawLoad  // déjà en points directs, pas besoin de normaliser

        let finalDouble = max(0, min(100, rawRecovery - loadImpact))
        let finalScore = Int(finalDouble.rounded())
        let label = moodLabel(for: finalScore)

        // Log baseline status
        if let b = baseline, b.isReliable {
            print("📊 Energy scored with personal baseline (\(b.dataPointCount) days) | HRV today=\(String(format: "%.1f", analysis.averageHRV))ms vs avg=\(String(format: "%.1f", b.hrvAvg))ms")
        }

        return EnergyScoreResult(
            energyScore: finalScore,
            moodLabel: label,
            breakdown: ScoreBreakdown(
                hrvRecovery: hrvRecovery,
                sleepRecovery: sleepRecovery,
                activityRecovery: activityRecovery,
                restingHRRecovery: restingHRRecovery,
                stressLoad: stressLoad,
                workoutPhysicalLoad: workoutPhysicalLoad,
                behavioralLoad: behavioralLoad
            )
        )
    }

    // MARK: - Mapping score → MoodLabel (contrat figé)

    static func moodLabel(for score: Int) -> MoodLabel {
        switch score {
        case 80...100: return .lumineux
        case 60..<80:  return .serein
        case 40..<60:  return .agité
        case 20..<40:  return .fatigué
        default:       return .lourd
        }
    }

    // MARK: - RECOVERY components

    /// HRV SDNN — 35 pts max
    /// Réf. Shaffer & Ginsberg (2017) : SDNN >50ms = bonne récup SNA
    ///
    /// Si baseline personnelle disponible (≥3 jours) :
    ///   → compare HRV du jour à la moyenne perso (modèle Whoop)
    ///   → bonus/malus de ±5 pts selon l'écart à ta norme
    /// Sinon : seuils population générale (cap 80ms)
    private static func computeHRVRecovery(_ a: DayAnalysis, baseline: PersonalBaseline? = nil) -> Int {
        let hrv = a.averageHRV
        guard hrv > 0 else { return 10 }  // pas de donnée → valeur neutre

        // Score de base : distribution continue, cap à 80ms
        let baseScore = min(35.0, (min(hrv, 80.0) / 80.0) * 35.0)

        // Ajustement personnel (si baseline fiable)
        if let b = baseline, b.isReliable, b.hrvAvg > 0 {
            let ratio = hrv / b.hrvAvg  // >1 = au-dessus de ta norme
            // Bonus/malus : ±5 pts max, proportionnel à l'écart
            // ratio 1.2 (+20%) → +5 pts | ratio 0.8 (-20%) → -5 pts
            let personalBonus = (ratio - 1.0) * 25.0  // amplifié pour être significatif
            let clampedBonus = max(-5.0, min(5.0, personalBonus))
            let adjusted = max(0, min(35.0, baseScore + clampedBonus))
            return Int(adjusted.rounded())
        }

        return Int(baseScore.rounded())
    }

    /// Sommeil — 30 pts max
    /// Réf. Walker 2017 : 7-8h cible. Effet non linéaire sous 6h.
    /// On utilise le score CoreML (0-100) qui intègre deep%, REM%, réveils
    private static func computeSleepRecovery(_ a: DayAnalysis) -> Int {
        guard let sleep = a.sleepAssessment else { return 10 }  // neutre si absent
        // Score CoreML → 30 pts, avec malus exponentiel sous 6h
        let hours = sleep.data.totalSleepMinutes / 60.0
        let durationFactor: Double
        if hours >= 7.0 {
            durationFactor = 1.0
        } else if hours >= 6.0 {
            durationFactor = 0.75  // -25% pour une heure de moins
        } else if hours >= 5.0 {
            durationFactor = 0.50  // Walker : effet dramatique sous 6h
        } else {
            durationFactor = 0.25  // privation sévère
        }
        let score = (sleep.score / 100.0) * durationFactor * 30.0
        return Int(score.rounded())
    }

    /// Activité physique — 20 pts max, intensité-consciente via METs réels
    ///
    /// Réf. Ainsworth et al. Compendium of Physical Activities (2011) :
    /// METs < 3   : léger (marche, yoga) → récupération positive
    /// METs 3-6   : modéré (footing) → bénéfice partiel
    /// METs > 6   : vigoureux/HIIT → Charge (pas récupération)
    ///
    /// Apple Watch fournit .physicalEffort en METs directement (iOS 17+).
    private static func computeActivityRecovery(_ a: DayAnalysis) -> Int {
        // --- Composante PAS ---
        let stepScore = min(10.0, (Double(a.totalSteps) / 7_500.0) * 10.0)

        // --- Composante EXERCISE : filtrée par METs réels ---
        let exerciseScore: Double
        if a.workoutMinutes > 0 {
            let mets = a.averageMETs
            if mets <= 3.0 {
                // Léger (marche, yoga) : plein bénéfice récupération
                exerciseScore = min(10.0, (a.workoutMinutes / 30.0) * 10.0)
            } else if mets <= 6.0 {
                // Modéré (footing, vélo rythme) : bénéfice partiel
                exerciseScore = min(10.0, (a.workoutMinutes / 30.0) * 10.0) * 0.5
            } else {
                // Vigoureux+ (HIIT, sprint) : charge, pas récup
                exerciseScore = 0
            }
        } else {
            exerciseScore = 0
        }

        return Int((stepScore + exerciseScore).rounded())
    }

    /// Charge physique due à l'exercise intense (zones 4-5) — 15 pts max
    ///
    /// Réf. Banister TRIMP (1991) + METs réels Apple Watch.
    /// METs > 6 = vigoureux, METs > 9 = très vigoureux (HIIT).
    private static func computeWorkoutPhysicalLoad(_ a: DayAnalysis) -> Int {
        guard a.workoutMinutes > 0, a.averageMETs > 6.0 else { return 0 }

        // TRIMP : charge ∝ intensité × durée
        let intensityFactor = min(2.0, (a.averageMETs - 6.0) / 4.5)  // 0 à 2 selon intensité au-delà de 6 METs
        let durationFactor  = min(1.0, a.workoutMinutes / 45.0)       // max atteint à 45 min
        let load = intensityFactor * durationFactor * 15.0
        return Int(load.rounded())
    }

    /// FC repos — 15 pts max
    /// Réf. Oura 2021 : resting HR faible = bonne récup cardio-vasculaire
    ///
    /// Si baseline personnelle disponible :
    ///   → compare FC repos du jour à la moyenne perso
    ///   → bonus si en dessous de ta norme, malus si au-dessus
    private static func computeRestingHRRecovery(_ a: DayAnalysis, baseline: PersonalBaseline? = nil) -> Int {
        guard let rhr = a.restingHeartRate, rhr > 0 else { return 7 }  // neutre

        // Score de base : seuils population générale
        let baseScore: Double
        switch rhr {
        case ..<50:  baseScore = 15.0
        case ..<60:  baseScore = 12.0
        case ..<70:  baseScore = 10.0
        case ..<80:  baseScore = 6.0
        default:     baseScore = 3.0  // FC repos >80 → stress ou décondition
        }

        // Ajustement personnel (si baseline fiable)
        // Pour la FC repos, c'est INVERSÉ : plus bas que ta norme = mieux
        if let b = baseline, b.isReliable, b.restingHRAvg > 0 {
            let diff = b.restingHRAvg - rhr  // positif = en dessous de ta norme = bien
            // Bonus/malus : ±3 pts max
            // diff +5 BPM en dessous → +3 pts | diff -5 BPM au-dessus → -3 pts
            let personalBonus = (diff / 5.0) * 3.0
            let clampedBonus = max(-3.0, min(3.0, personalBonus))
            let adjusted = max(0, min(15.0, baseScore + clampedBonus))
            return Int(adjusted.rounded())
        }

        return Int(baseScore)
    }

    // MARK: - LOAD components

    /// Charge de stress physiologique — 25 pts max (pénalité)
    /// Réf. Nazari et al. 2023 WESAD : épisodes stress élevé + FC pic
    /// Corroboré par les labels CoreML du modèle entrainé sur WESAD
    private static func computeStressLoad(_ a: DayAnalysis) -> Int {
        let highHours = a.highStressHours
        // Pic de stress (FC maximale) — signal le plus fort
        let peakHR = a.stressTimeline.map { $0.meanHR }.max() ?? 0
        let peakPenalty: Double = peakHR > 110 ? 10 : peakHR > 95 ? 6 : peakHR > 80 ? 3 : 0
        // Heures cumulatives : effet supra-additif (Nazari 2023)
        let hoursPenalty: Double
        switch highHours {
        case 0:     hoursPenalty = 0
        case 1:     hoursPenalty = 5
        case 2:     hoursPenalty = 10
        case 3...4: hoursPenalty = 15
        default:    hoursPenalty = 20  // 5h+ = surcharge chronique
        }
        return Int(min(25.0, peakPenalty + hoursPenalty).rounded())
    }

    /// Charge comportementale — 15 pts max (pénalité)
    /// Moins physiologique, plus comportemental — signal secondaire
    private static func computeBehavioralLoad(_ a: DayAnalysis) -> Int {
        // Charge agenda : 0-2 réunions = normé (0), 7+ = surcharge (8)
        let meetingLoad: Double
        switch a.totalMeetings {
        case 0...2: meetingLoad = 0
        case 3...4: meetingLoad = 3
        case 5...6: meetingLoad = 6
        default:    meetingLoad = 8
        }
        // Screen time : 0-2h = 0 pénalité, 6h+ = 7 pts
        let screenLoad: Double
        switch a.screenTimeMinutes {
        case ..<120: screenLoad = 0
        case ..<240: screenLoad = 2
        case ..<360: screenLoad = 4
        case ..<480: screenLoad = 6
        default:     screenLoad = 7
        }
        return Int((meetingLoad + screenLoad).rounded())
    }
}

// MARK: - Debug Mock (pour slider Julien / Yue)

/// Génère un EnergyScoreResult à partir de signaux bruts (pour le panneau debug).
/// Permet de simuler n'importe quel état sans vraies données.
struct DebugSignals {
    var sleepHours: Double = 7.0       // 0-10
    var sleepScore: Double = 75.0      // 0-100
    var steps: Int = 7000              // 0-15000
    var activeKcal: Int = 300          // 0-800
    var workoutMinutes: Double = 20    // 0-90
    var hrv: Double = 42.0             // ms SDNN
    var restingHR: Double = 65.0       // BPM
    var highStressHours: Int = 1       // 0-10
    var peakHR: Double = 88.0          // BPM pic de stress
    var averageMETs: Double = 1.6      // METs moyens (1.6 = marche légère)
    var meetings: Int = 3              // 0-12
    var screenTimeMinutes: Int = 285   // 0-600

    func toEnergyScore() -> EnergyScoreResult {

        // RECOVERY — miroir exact de EnergyScoreEngine
        let hrvRecovery = Int(min(35.0, (min(hrv, 80.0) / 80.0) * 35.0).rounded())

        let durationFactor: Double = sleepHours >= 7 ? 1.0
                                   : sleepHours >= 6 ? 0.75
                                   : sleepHours >= 5 ? 0.50 : 0.25
        let sleepRecovery = Int(((sleepScore / 100.0) * durationFactor * 30.0).rounded())

        // Activité avec filtre METs (miroir EnergyScoreEngine)
        let stepScore = min(10.0, (Double(steps) / 7_500.0) * 10.0)
        let exerciseScore: Double
        if workoutMinutes > 0 {
            if averageMETs <= 3.0 {
                exerciseScore = min(10.0, (workoutMinutes / 30.0) * 10.0)        // Léger : plein bénéfice
            } else if averageMETs <= 6.0 {
                exerciseScore = min(10.0, (workoutMinutes / 30.0) * 10.0) * 0.5 // Modéré : partiel
            } else {
                exerciseScore = 0                                                  // Vigoureux : charge, pas récup
            }
        } else {
            exerciseScore = 0
        }
        let activityRecovery = Int((stepScore + exerciseScore).rounded())

        let restingHRRecovery: Int
        switch restingHR {
        case ..<50:  restingHRRecovery = 15
        case ..<60:  restingHRRecovery = 12
        case ..<70:  restingHRRecovery = 10
        case ..<80:  restingHRRecovery = 6
        default:     restingHRRecovery = 3
        }

        let recovery = Double(hrvRecovery + sleepRecovery + activityRecovery + restingHRRecovery)

        // LOAD — miroir exact de EnergyScoreEngine
        let peakPenalty: Double = peakHR > 110 ? 10 : peakHR > 95 ? 6 : peakHR > 80 ? 3 : 0
        let hoursPenalty: Double = highStressHours == 0 ? 0 : highStressHours == 1 ? 5
                                 : highStressHours == 2 ? 10 : highStressHours <= 4 ? 15 : 20
        let stressLoad = Int(min(25.0, peakPenalty + hoursPenalty).rounded())

        // Charge physique exercise intense (TRIMP via METs)
        let workoutPhysicalLoad: Int
        if workoutMinutes > 0, averageMETs > 6.0 {
            let intensityFactor = min(2.0, (averageMETs - 6.0) / 4.5)
            let durationFactor2 = min(1.0, workoutMinutes / 45.0)
            workoutPhysicalLoad = Int((intensityFactor * durationFactor2 * 15.0).rounded())
        } else {
            workoutPhysicalLoad = 0
        }

        let meetingLoad: Double = meetings <= 2 ? 0 : meetings <= 4 ? 3 : meetings <= 6 ? 6 : 8
        let screenLoad: Double = screenTimeMinutes < 120 ? 0 : screenTimeMinutes < 240 ? 2
                               : screenTimeMinutes < 360 ? 4 : screenTimeMinutes < 480 ? 6 : 7
        let behavioralLoad = Int((meetingLoad + screenLoad).rounded())

        let totalLoad = Double(stressLoad + workoutPhysicalLoad + behavioralLoad)
        let total = Int(max(0, min(100, recovery - totalLoad)).rounded())

        return EnergyScoreResult(
            energyScore: total,
            moodLabel: EnergyScoreEngine.moodLabel(for: total),
            breakdown: ScoreBreakdown(
                hrvRecovery: hrvRecovery,
                sleepRecovery: sleepRecovery,
                activityRecovery: activityRecovery,
                restingHRRecovery: restingHRRecovery,
                stressLoad: stressLoad,
                workoutPhysicalLoad: workoutPhysicalLoad,
                behavioralLoad: behavioralLoad
            )
        )
    }
}
