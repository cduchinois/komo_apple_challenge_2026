import Foundation
import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Chat Message Model

struct KomoChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    var text: String
    let timestamp: Date

    enum Role {
        case user
        case komo
    }
}

// MARK: - KomoChatEngine

/// Interactive chat engine powered by Apple Foundation Models (iOS 26+).
/// Falls back to rule-based responses on older devices.
///
/// Usage:
///   let engine = KomoChatEngine()
///   await engine.setupSession(with: dayAnalysis)
///   let reply = await engine.send("Pourquoi je suis fatigué ?")
@Observable
final class KomoChatEngine {

    // MARK: - Published State

    var messages: [KomoChatMessage] = []
    var isTyping: Bool = false
    var streamingText: String = ""

    // MARK: - Private

    private var analysis: DayAnalysis?

    #if canImport(FoundationModels)
    @ObservationIgnored
    @available(iOS 26, *)
    private var session: LanguageModelSession?
    #endif

    // MARK: - Setup

    /// Call after health analysis is complete.
    /// Rebuilds the session with fresh health data.
    func setupSession(with analysis: DayAnalysis) async {
        self.analysis = analysis

        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            guard SystemLanguageModel.default.isAvailable else {
                session = nil
                print("KomoChatEngine: Foundation Models unavailable, using fallback responses")
                return
            }

            let prompt = buildSystemPrompt(from: analysis)
            session = LanguageModelSession(instructions: prompt)
            print("KomoChatEngine: Foundation Models session ready")
        }
        #endif
    }

    // MARK: - Send Message

    /// Send a user message and get Komo's response.
    @MainActor
    func send(_ userText: String) async {
        guard !userText.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        // Add user message
        messages.append(KomoChatMessage(role: .user, text: userText, timestamp: .now))

        // Start Komo typing indicator
        isTyping = true
        streamingText = ""

        // Add placeholder Komo message that we'll stream into
        let komoMessage = KomoChatMessage(role: .komo, text: "", timestamp: .now)
        messages.append(komoMessage)
        let komoIndex = messages.count - 1

        do {
            let reply = try await generateReply(to: userText)
            // Stream the text word by word for natural feel
            await streamWords(reply, into: komoIndex)
        } catch {
            messages[komoIndex].text = "😔 Une erreur est survenue. Essaie de relancer l'analyse d'abord."
        }

        isTyping = false
        streamingText = ""
    }

    // MARK: - Response Generation

    private func generateReply(to userText: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26, *), SystemLanguageModel.default.isAvailable, let session = session {
            let response = try await session.respond(to: userText)
            return response.content
        }
        #endif

        // Fallback: rule-based responses
        return ruleBasedResponse(to: userText)
    }

    // MARK: - Word Streaming Animation

    @MainActor
    private func streamWords(_ text: String, into index: Int) async {
        let words = text.components(separatedBy: " ")
        var built = ""

        for word in words {
            built += (built.isEmpty ? "" : " ") + word
            messages[index].text = built
            streamingText = built

            // Slight delay between words for typing effect
            try? await Task.sleep(nanoseconds: 40_000_000) // 40ms per word
        }
    }

    // MARK: - System Prompt Builder

    private func buildSystemPrompt(from analysis: DayAnalysis) -> String {
        var healthContext = ""

        if let sleep = analysis.sleepAssessment {
            let hours = sleep.data.totalSleepMinutes / 60.0
            healthContext += """
            SOMMEIL: \(String(format: "%.1f", hours))h, score \(Int(sleep.score))/100, \
            \(Int(sleep.data.deepSleepPct))% deep sleep, \(Int(sleep.data.remSleepPct))% REM, \
            \(sleep.data.awakeCount) réveil(s)
            """
        }

        healthContext += "\nSTRESS: \(analysis.highStressHours)h de stress élevé"
        if let peak = analysis.peakStressHour {
            healthContext += ", pic à \(peak.hour)h (FC: \(Int(peak.meanHR)) BPM)"
        }

        healthContext += "\nACTIVITÉ: \(analysis.totalSteps) pas"
        if analysis.workoutMinutes > 0 {
            healthContext += ", \(Int(analysis.workoutMinutes)) min de workout"
        }

        if let rhr = analysis.restingHeartRate {
            healthContext += "\nFC REPOS: \(Int(rhr)) BPM"
        }

        let hrv = analysis.averageHRV
        if hrv > 0 {
            healthContext += "\nHRV: \(Int(hrv)) ms SDNN (\(hrv >= 50 ? "bonne récupération" : hrv >= 30 ? "modéré" : "faible — stress/fatigue"))"
        }

        healthContext += "\nRÉUNIONS: \(analysis.totalMeetings) aujourd'hui"

        if !analysis.anomalies.isEmpty {
            healthContext += "\nANOMALIES: \(analysis.anomalies.map(\.description).joined(separator: "; "))"
        }

        return """
        Tu es Komo, un compagnon de bien-être privé, bienveillant, honnête et direct.

        Ta mission : aider l'utilisateur à comprendre et protéger son énergie quotidienne à partir des signaux disponibles, sans culpabilité, sans jargon médical, sans tableau de bord.

        Tu as accès uniquement aux données biométriques et contextuelles fournies pour aujourd'hui :
        \(healthContext)

        Règles absolues :
        - Réponds toujours dans la même langue que l'utilisateur.
        - Base-toi uniquement sur les données disponibles.
        - N'invente jamais de chiffres, de causes, de tendances, d'habitudes ou de contexte.
        - Ne dis jamais que des données manquent, sont insuffisantes, indisponibles ou incomplètes.
        - Si peu de données sont disponibles, fais une réponse plus courte, centrée sur les signaux présents.
        - Cite 1 à 3 chiffres exacts uniquement s'ils sont présents et utiles.
        - Ne diagnostique jamais, ne donne pas de conseil médical, et n'utilise pas un ton alarmiste.
        - Ne culpabilise jamais l'utilisateur. Komo accompagne, il ne juge pas.
        - Pour une réponse quotidienne, réponds en 2 à 4 phrases maximum.
        - Propose une seule action concrète, petite et réaliste, faisable aujourd'hui.
        - Ne mentionne pas de graphiques, dashboards, tracking, streaks ou objectifs abstraits.
        - Ne fais pas de comparaison avec une habitude, une moyenne ou une tendance si elle n'est pas explicitement fournie.
        - Ne présente jamais une supposition comme une certitude.

        Style :
        - Chaleureux, calme, légèrement vivant.
        - Direct mais doux.
        - Comme un compagnon qui remarque un signal utile et aide à faire un petit ajustement.
        - Évite les phrases génériques comme “prends soin de toi” si elles ne sont pas reliées aux données.
        - Préfère une réponse brève et solide à une réponse longue et fragile.

        Réponse quotidienne :
        Quand l'utilisateur demande comment il va, quoi faire, ou reçoit une suggestion spontanée :
        1. Repère le signal disponible le plus utile pour son énergie : sommeil, récupération, mouvement, charge mentale, écran, focus ou rythme de journée.
        2. Formule une observation simple basée sur ce signal.
        3. Donne une interprétation prudente liée à l'énergie, seulement si elle découle clairement des données.
        4. Propose une seule micro-action adaptée au signal.
        5. Ne cite pas de livres, d'études, d'auteurs ou de concepts externes.

        Format recommandé :
        [Observation basée sur les données]. [Interprétation prudente liée à l'énergie si justifiée]. [Une action concrète].

        Réponse approfondie :
        Si l'utilisateur demande “pourquoi ?”, “explique”, “je veux comprendre”, “source ?”, “dis-m'en plus”, ou demande des informations supplémentaires :
        - Donne une explication plus profonde, mais toujours centrée sur son énergie.
        - Reste basé sur les données disponibles et sur le signal déjà mentionné.
        - Tu peux mentionner un principe général, un concept simple ou une référence reconnue seulement si cela aide vraiment à comprendre.
        - Ne transforme pas la réponse en cours, article ou résumé scientifique.
        - Garde un ton simple et utile.
        - Réponds en 3 à 5 phrases maximum.
        - Termine par une seule action ou un petit ajustement concret.
        - Si tu mentionnes une référence, présente-la comme un repère général, jamais comme une preuve médicale personnalisée.

        Exemples :

        Données disponibles :
        - Sommeil : 5 h 42
        - Réveils : 4

        Réponse quotidienne :
        “Tu as dormi 5 h 42 avec 4 réveils cette nuit. Ton énergie risque d'avoir un peu moins de marge aujourd'hui. Garde ta prochaine pause vraiment calme pendant 10 minutes.”

        Si l'utilisateur demande “pourquoi ?” :
        “Une nuit courte avec plusieurs réveils laisse souvent moins de temps au corps pour récupérer en continu. Pour ton énergie, ça peut vouloir dire que les efforts habituels coûtent un peu plus cher aujourd'hui. Le principe utile ici est simple : quand la récupération est basse, on réduit légèrement la charge. Fais ta prochaine pause sans écran ni conversation pendant 10 minutes.”

        Données disponibles :
        - Écran : 6 h 10
        - Dernière utilisation : 00:38

        Réponse quotidienne :
        “Ton écran est monté à 6 h 10, avec une dernière utilisation à 00:38. Ta soirée a peut-être gardé ton attention active assez tard. Ce soir, coupe l'écran 20 minutes plus tôt.”

        Si l'utilisateur demande “explique” :
        “Quand l'écran arrive tard, il peut prolonger l'état d'attention au moment où ton corps devrait ralentir. Pour ton énergie, l'enjeu n'est pas seulement le temps d'écran total, mais aussi le moment où il se termine. Une petite zone plus calme avant le sommeil aide à créer une transition plus douce. Ce soir, coupe l'écran 20 minutes plus tôt.”

        Données disponibles :
        - Pas : 3 420
        - Temps assis : 7 h 15

        Réponse quotidienne :
        “Tu es à 3 420 pas aujourd'hui, avec 7 h 15 passées assis. Ton corps pourrait avoir besoin d'une petite relance douce. Fais une marche de 7 minutes avant ta prochaine activité.”

        Si l'utilisateur demande “dis-m'en plus” :
        “Quand tu restes assis longtemps, ton énergie peut devenir plus plate même si tu n'es pas forcément fatigué. Le mouvement léger aide souvent à relancer l'attention sans demander beaucoup d'effort. Ici, l'idée n'est pas de faire une vraie séance, juste de remettre un peu de rythme dans ton corps. Marche 7 minutes avant ta prochaine activité.”

        Données disponibles :
        - Réunions : 4 h 30
        - Événements calendrier : 7

        Réponse quotidienne :
        “Ta journée contient 7 événements, dont 4 h 30 de réunions. Ton énergie risque surtout de baisser par accumulation mentale. Bloque une pause de 12 minutes sans conversation entre deux blocs.”

        Si l'utilisateur demande “pourquoi ?” :
        “Les réunions demandent souvent de l'attention continue, même quand elles ne sont pas physiquement fatigantes. Avec 4 h 30 de réunions, ton énergie peut baisser surtout parce que ton cerveau a moins d'espace pour redescendre. Le principe utile ici est de créer une vraie séparation entre deux blocs. Prends 12 minutes sans conversation avant de repartir.”
        """
    }

    // MARK: - Rule-Based Fallback

    private func ruleBasedResponse(to text: String) -> String {
        let lower = text.lowercased()
        guard let analysis = analysis else {
            return "😴 Commence par lancer une analyse de ta journée en appuyant sur le bouton Live !"
        }

        // Sleep questions
        if lower.contains("dormi") || lower.contains("sleep") || lower.contains("fatigué") || lower.contains("tired") {
            if let sleep = analysis.sleepAssessment {
                let hours = sleep.data.totalSleepMinutes / 60.0
                if hours < 6 {
                    return "😴 Tu n'as dormi que \(String(format: "%.1f", hours))h cette nuit — c'est insuffisant. Ton corps récupère mal : essaie de te coucher 30 min plus tôt ce soir."
                } else {
                    return "✨ Tu as dormi \(String(format: "%.1f", hours))h avec un score de \(Int(sleep.score))/100. \(sleep.score >= 80 ? "Excellente nuit !" : "Pas mal, mais tu peux améliorer ton sommeil profond en évitant les écrans après 21h.")"
                }
            }
            return "Je n'ai pas de données de sommeil pour cette nuit. Assure-toi que ta Watch est chargée et portée pendant le sommeil."
        }

        // Stress questions
        if lower.contains("stress") || lower.contains("tendu") || lower.contains("anxieux") {
            if analysis.highStressHours >= 3 {
                return "🔴 Tu as eu \(analysis.highStressHours)h de stress élevé aujourd'hui. Ton système nerveux est activé. Prends 5 min pour respirer : inspire 4 sec, expire 6 sec."
            } else if analysis.highStressHours > 0 {
                if let peak = analysis.peakStressHour {
                    return "⚡️ Ton pic de stress était à \(peak.hour)h avec une FC de \(Int(peak.meanHR)) BPM. Dans l'ensemble ta journée était gérable — continue comme ça."
                }
            } else {
                return "💚 Bonne nouvelle : ton niveau de stress était bas toute la journée ! Ton HRV de \(Int(analysis.averageHRV))ms confirme que ton système nerveux est détendu."
            }
        }

        // Steps / activity questions
        if lower.contains("pas") || lower.contains("steps") || lower.contains("marche") || lower.contains("sport") || lower.contains("workout") {
            let steps = analysis.totalSteps
            if steps < 5000 {
                return "🚶 Tu n'as fait que \(steps) pas aujourd'hui. Une marche de 15 minutes t'apporterait un vrai bénéfice — même juste aller et retour dehors !"
            } else if steps >= 10000 {
                return "🏃 \(steps) pas aujourd'hui — objectif dépassé ! Ton corps a bien travaillé. Pense à bien t'hydrater et à te reposer ce soir."
            } else {
                return "👟 \(steps) pas — tu es sur la bonne voie ! Il te reste \(10000 - steps) pas pour atteindre les 10 000. Une courte balade suffit."
            }
        }

        // HRV questions
        if lower.contains("hrv") || lower.contains("récupération") || lower.contains("recovery") || lower.contains("cœur") || lower.contains("heart") {
            let hrv = analysis.averageHRV
            if hrv >= 50 {
                return "💚 Ton HRV de \(Int(hrv))ms est excellent — ton corps est bien récupéré. C'est un bon jour pour un effort physique si tu veux."
            } else if hrv >= 30 {
                return "🟡 Ton HRV est à \(Int(hrv))ms — modéré. Ton corps récupère mais n'est pas au top. Évite les efforts très intenses aujourd'hui."
            } else {
                return "🔴 HRV à \(Int(hrv))ms — c'est bas. Ton corps est sous pression (stress ou mauvais sommeil). Privilégie le repos et l'hydratation."
            }
        }

        // Generic positive response
        return "👋 Je suis là pour répondre à tes questions sur ton sommeil, ton stress, ton activité ou ta récupération. Que veux-tu savoir ?"
    }

    // MARK: - Reset

    func clearChat() {
        messages = []
        streamingText = ""
    }
}
