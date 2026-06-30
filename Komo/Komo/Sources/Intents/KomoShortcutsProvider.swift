import AppIntents

struct KomoShortcutsProvider: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckEnergyScoreIntent(),
            phrases: [
                "Quel est mon niveau d'énergie sur \(.applicationName)",
                "Quelle est mon énergie sur \(.applicationName)",
                "Demande à \(.applicationName) comment je vais",
                "Donne mon score \(.applicationName)",
                "Donne mon score d'énergie sur \(.applicationName)"
            ],
            shortTitle: "Énergie",
            systemImageName: "bolt.fill"
        )

        AppShortcut(
            intent: CheckSleepQualityIntent(),
            phrases: [
                "Quel est mon niveau de sommeil sur \(.applicationName)",
                "Comment est mon sommeil sur \(.applicationName)",
                "Donne mon score de sommeil sur \(.applicationName)",
                "Demande à \(.applicationName) mon sommeil"
            ],
            shortTitle: "Sommeil",
            systemImageName: "bed.double.fill"
        )

        AppShortcut(
            intent: CheckStressLevelIntent(),
            phrases: [
                "Quel est mon niveau de stress sur \(.applicationName)",
                "Comment est mon stress sur \(.applicationName)",
                "Demande à \(.applicationName) mon stress",
                "Donne mon stress sur \(.applicationName)"
            ],
            shortTitle: "Stress",
            systemImageName: "heart.fill"
        )

        AppShortcut(
            intent: GetActivitySummaryIntent(),
            phrases: [
                "Quelle est mon activité sur \(.applicationName)",
                "Donne mon activité sur \(.applicationName)",
                "Combien de pas sur \(.applicationName)",
                "Demande à \(.applicationName) mon activité"
            ],
            shortTitle: "Activité",
            systemImageName: "figure.walk"
        )

        AppShortcut(
            intent: CheckKomoHealthMetricIntent(),
            phrases: [
                "Quel est mon \(\.$metric) sur \(.applicationName)",
                "Quelle est mon \(\.$metric) sur \(.applicationName)",
                "Donne mon \(\.$metric) sur \(.applicationName)",
                "Demande à \(.applicationName) mon \(\.$metric)",
                "Comment est mon \(\.$metric) sur \(.applicationName)"
            ],
            shortTitle: "Donnée Komo",
            systemImageName: "sparkles"
        )

        AppShortcut(
            intent: GetHealthInsightIntent(),
            phrases: [
                "Quels sont mes conseils santé \(.applicationName)",
                "Demande à \(.applicationName) un conseil santé",
                "Qu'est-ce que je dois faire selon \(.applicationName)",
                "Donne moi un conseil sur \(.applicationName)"
            ],
            shortTitle: "Conseil Santé",
            systemImageName: "heart.text.square"
        )
    }
}
