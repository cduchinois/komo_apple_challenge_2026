import SwiftUI

// MARK: - Main Home View

struct ContentView: View {
    @EnvironmentObject var engine: HealthAvatarEngine
    @State private var showDetail = false
    @State private var hasAppeared = false
    @State private var energyResult: EnergyScoreResult? = nil
    @State private var bubbleText: String = ""
    @State private var isGeneratingBubble = false
    @State private var isInjecting = false
    @State private var injectionStatus = ""
    @State private var blobPromptIndex = 0
    @State private var scenarioIndex = 1  // 0=lumineux, 1=agité(actuel), 2=fatigué, 3=lourd

    // Days together — starts from hackathon day
    private var daysTogether: Int {
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 30))!
        return max(1, Calendar.current.dateComponents([.day], from: start, to: .now).day! + 1)
    }

    var body: some View {
        ZStack {
            // MARK: Background
            backgroundView

            VStack(spacing: 0) {
                // MARK: Header
                headerView
                    .padding(.top, 16)

                // MARK: Message Bubble
                if !bubbleText.isEmpty {
                    InsightBubbleView(text: bubbleText, isGenerating: isGeneratingBubble)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else if engine.isLoading {
                    loadingBubble
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                }

                Spacer()

                // MARK: Blob Creature
                KomoBlobView(moodLabel: energyResult?.moodLabel ?? .serein)
                    .frame(width: 200, height: 200)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Task { await showNextBlobPrompt() }
                    }
                    .scaleEffect(hasAppeared ? 1.0 : 0.5)
                    .opacity(hasAppeared ? 1.0 : 0)
                    .animation(.spring(response: 0.8, dampingFraction: 0.6).delay(0.2), value: hasAppeared)

                Spacer()

                // MARK: Energy Bar
                if let result = energyResult {
                    EnergyBarView(result: result, showDetail: $showDetail)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // MARK: Action Cards
                actionCardsRow
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }

            // MARK: Injection status overlay
            if isInjecting {
                injectionOverlay
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showDetail) {
            EnergyDetailView(result: energyResult)
                .environmentObject(engine)
        }
        .task {
            hasAppeared = true
            await runFullPipeline()
        }
    }

    // MARK: - Pipeline

    private func runFullPipeline() async {
        injectionStatus = "Lecture HealthKit..."
        bubbleText = ""
        blobPromptIndex = 0
        energyResult = nil

        await engine.requestPermissions()
        await engine.analyzeToday()

        guard engine.isUsingRealHealthData else {
            injectionStatus = "Aucune donnée Santé"
            withAnimation(.easeOut(duration: 0.3)) {
                bubbleText = engine.insights.first ?? "Aucune donnée HealthKit réelle trouvée pour aujourd'hui."
                isGeneratingBubble = false
            }
            return
        }

        injectionStatus = "Données Santé réelles"

        if let analysis = engine.dayAnalysis {
            // 🔍 DEBUG — à retirer avant la prod
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("📊 KOMO REAL DATA DIAGNOSTIC")
            print("  Steps        : \(analysis.totalSteps)")
            print("  Calories     : \(analysis.totalCalories) kcal")
            print("  Workout min  : \(analysis.workoutMinutes) min")
            print("  HRV avg      : \(String(format: "%.1f", analysis.averageHRV)) ms")
            print("  Resting HR   : \(analysis.restingHeartRate.map { "\(Int($0)) BPM" } ?? "N/A")")
            print("  Sleep        : \(analysis.sleepAssessment.map { "score \(Int($0.score))" } ?? "N/A")")
            print("  Stress hours : \(analysis.highStressHours)h")
            print("  Meetings     : \(analysis.totalMeetings)")
            print("  HR readings  : \(analysis.stressTimeline.count) heures")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

            let result = EnergyScoreEngine.score(from: analysis, baseline: engine.personalBaseline)
            print("🎯 Energy Score: \(result.energyScore) (\(result.moodLabel.rawValue))")
            print("  HRV recovery    : \(result.breakdown.hrvRecovery)/35")
            print("  Sleep recovery  : \(result.breakdown.sleepRecovery)/30")
            print("  Activity        : \(result.breakdown.activityRecovery)/20")
            print("  Resting HR rec  : \(result.breakdown.restingHRRecovery)/15")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

            withAnimation(.easeOut(duration: 0.5)) {
                energyResult = result
            }

            // Generate the first data-aware bubble insight.
            isGeneratingBubble = true
            let insight = await InsightGenerator.shared.generateBubbleInsight(from: analysis, mood: result.moodLabel)
            withAnimation(.easeOut(duration: 0.3)) {
                bubbleText = insight
                isGeneratingBubble = false
            }

            await SmartNotificationManager.shared.scheduleAll(from: analysis)
        }
    }

    private func refreshRealHealthData() async {
        await runFullPipeline()
    }

    private func showNextBlobPrompt() async {
        guard let analysis = engine.dayAnalysis, !isGeneratingBubble else { return }
        let mood = energyResult?.moodLabel ?? .serein
        let nextIndex = blobPromptIndex + 1

        withAnimation(.easeOut(duration: 0.2)) {
            isGeneratingBubble = true
        }

        let prompt = await InsightGenerator.shared.generateBlobTapPrompt(
            from: analysis,
            mood: mood,
            index: nextIndex
        )

        blobPromptIndex = nextIndex
        withAnimation(.easeOut(duration: 0.25)) {
            bubbleText = prompt
            isGeneratingBubble = false
        }
    }

    // MARK: - Subviews

    private var backgroundView: some View {
        LinearGradient(
            stops: [
                .init(color: Color(hex: "0F2419"), location: 0),
                .init(color: Color(hex: "1A3A20"), location: 0.3),
                .init(color: Color(hex: "0A1F10"), location: 0.7),
                .init(color: Color(hex: "071510"), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var headerView: some View {
        HStack {
            // Settings
            Button(action: {}) {
                Image(systemName: "gearshape.fill")
                    .foregroundStyle(.white.opacity(0.5))
                    .font(.system(size: 18))
            }
            .accessibilityLabel("Settings")

            Spacer()

            VStack(spacing: 2) {
                Text("Already \(daysTogether) Day\(daysTogether > 1 ? "s" : "") Together")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                if !injectionStatus.isEmpty {
                    Text(injectionStatus)
                        .font(.system(size: 10))
                        .foregroundStyle(statusColor.opacity(0.85))
                }
            }

            Spacer()

            Button(action: {
                Task { await refreshRealHealthData() }
            }) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.2))
                        .frame(width: 34, height: 34)
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(statusColor)
                        .font(.system(size: 16))
                }
            }
            .accessibilityLabel("Refresh HealthKit data")
        }
        .padding(.horizontal, 24)
    }

    private var loadingBubble: some View {
        HStack(spacing: 8) {
            ProgressView()
                .tint(.white)
                .scaleEffect(0.8)
            Text("Komo analyse tes données…")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var actionCardsRow: some View {
        HStack(spacing: 12) {
            ActionCard(
                icon: "🍎",
                title: "Feed",
                subtitle: "reward Komo with saved energy",
                color: Color(hex: "1E3A2A")
            )
            ActionCard(
                icon: "🧩",
                title: "Quest",
                subtitle: "try gentle habits to boost energy",
                color: Color(hex: "1A3020")
            )
            ActionCard(
                icon: "🌱",
                title: "Grow",
                subtitle: "play and learn to enhance energy",
                color: Color(hex: "163020")
            )
        }
    }

    private var injectionOverlay: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .tint(.green)
                    .scaleEffect(1.5)
                Text("Écriture des données\ndans HealthKit…")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            }
            .padding(32)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }

    // MARK: - Scenario color (header indicator)

    private var scenarioColor: Color {
        switch scenarioIndex {
        case 0: return .green
        case 1: return .yellow
        case 2: return .orange
        default: return .red
        }
    }

    private var statusColor: Color {
        if engine.isUsingRealHealthData {
            return .green
        }
        if engine.errorMessage != nil || injectionStatus == "Aucune donnée Santé" {
            return .orange
        }
        return .white.opacity(0.55)
    }

    // MARK: - Scenario Cycler

    /// Cycles through 4 test scenarios with very different data.
    /// Direct DayAnalysis injection — instant, no HealthKit write needed.
    private func cycleScenario() async {
        scenarioIndex = (scenarioIndex + 1) % 4
        let scenario = makeScenario(scenarioIndex)

        let label: String
        switch scenarioIndex {
        case 0: label = "🌟 Lumineux (~85%)"
        case 1: label = "⚡ Agité (~48%)"
        case 2: label = "😴 Fatigué (~28%)"
        default: label = "🔴 Lourd (~12%)"
        }
        injectionStatus = label

        let result = EnergyScoreEngine.score(from: scenario)
        withAnimation(.spring()) {
            energyResult = result
            bubbleText = ""
            blobPromptIndex = 0
        }

        isGeneratingBubble = true
        let insight = await InsightGenerator.shared.generateBubbleInsight(from: scenario, mood: result.moodLabel)
        withAnimation(.easeOut(duration: 0.4)) {
            bubbleText = insight
            isGeneratingBubble = false
        }

        // Also push to engine so detail view works
        await MainActor.run { engine.dayAnalysis = scenario }
    }

    /// Build a DayAnalysis for each test scenario
    private func makeScenario(_ index: Int) -> DayAnalysis {
        switch index {

        case 0: // LUMINEUX — top forme
            return DayAnalysis(
                date: Date(),
                stressTimeline: [
                    StressReading(hour: 9,  level: .low,  confidence: 0.90, meanHR: 68.0,  hrvSDNN: 72.0),
                    StressReading(hour: 11, level: .low,  confidence: 0.88, meanHR: 70.0,  hrvSDNN: 68.0),
                    StressReading(hour: 14, level: .low,  confidence: 0.85, meanHR: 72.0,  hrvSDNN: 65.0)
                ],
                sleepAssessment: SleepAssessment(
                    score: 91.0, category: .excellent,
                    data: SleepData(totalSleepMinutes: 495, deepSleepPct: 0.24, remSleepPct: 0.28,
                                   awakeCount: 0, awakeMinutes: 0, sleepOnsetLatencyMin: 8, restingHRDuringSleep: 52,
                                   respiratoryRate: 13, bloodOxygenAvg: 0.99, bedtimeConsistencyMin: 5)
                ),
                anomalies: [],
                totalSteps: 12_450,
                totalCalories: 650,
                totalMeetings: 2,
                workoutMinutes: 35,
                restingHeartRate: 52.0,
                screenTimeMinutes: 180,
                averageMETs: 2.2   // marche + footing léger
            )

        case 1: // AGITÉ — journée hackathon normale
            return DayAnalysis(
                date: Date(),
                stressTimeline: [
                    StressReading(hour: 10, level: .medium, confidence: 0.75, meanHR: 85.0, hrvSDNN: 40.0),
                    StressReading(hour: 14, level: .medium, confidence: 0.78, meanHR: 88.0, hrvSDNN: 38.0),
                    StressReading(hour: 15, level: .high,   confidence: 0.92, meanHR: 108.0, hrvSDNN: 22.0),
                    StressReading(hour: 16, level: .medium, confidence: 0.70, meanHR: 90.0,  hrvSDNN: 35.0)
                ],
                sleepAssessment: SleepAssessment(
                    score: 64.0, category: .fair,
                    data: SleepData(totalSleepMinutes: 375, deepSleepPct: 0.13, remSleepPct: 0.19,
                                   awakeCount: 2, awakeMinutes: 18, sleepOnsetLatencyMin: 22, restingHRDuringSleep: 60,
                                   respiratoryRate: 15, bloodOxygenAvg: 0.97, bedtimeConsistencyMin: 30)
                ),
                anomalies: [],
                totalSteps: 6_300,
                totalCalories: 320,
                totalMeetings: 4,
                workoutMinutes: 0,
                restingHeartRate: 62.0,
                screenTimeMinutes: 285,
                averageMETs: 1.6   // journée assis
            )

        case 2: // FATIGUÉ — manque de sommeil chronique
            return DayAnalysis(
                date: Date(),
                stressTimeline: [
                    StressReading(hour: 9,  level: .medium, confidence: 0.80, meanHR: 90.0, hrvSDNN: 28.0),
                    StressReading(hour: 11, level: .high,   confidence: 0.88, meanHR: 100.0, hrvSDNN: 20.0),
                    StressReading(hour: 13, level: .high,   confidence: 0.85, meanHR: 102.0, hrvSDNN: 18.0),
                    StressReading(hour: 16, level: .medium, confidence: 0.72, meanHR: 88.0,  hrvSDNN: 25.0)
                ],
                sleepAssessment: SleepAssessment(
                    score: 42.0, category: .poor,
                    data: SleepData(totalSleepMinutes: 255, deepSleepPct: 0.08, remSleepPct: 0.14,
                                   awakeCount: 4, awakeMinutes: 40, sleepOnsetLatencyMin: 45, restingHRDuringSleep: 68,
                                   respiratoryRate: 17, bloodOxygenAvg: 0.96, bedtimeConsistencyMin: 60)
                ),
                anomalies: [],
                totalSteps: 2_100,
                totalCalories: 180,
                totalMeetings: 6,
                workoutMinutes: 0,
                restingHeartRate: 72.0,
                screenTimeMinutes: 420,
                averageMETs: 1.4   // sédentaire
            )

        default: // LOURD — surcharge totale
            return DayAnalysis(
                date: Date(),
                stressTimeline: [
                    StressReading(hour: 8,  level: .high, confidence: 0.95, meanHR: 112.0, hrvSDNN: 15.0),
                    StressReading(hour: 10, level: .high, confidence: 0.92, meanHR: 115.0, hrvSDNN: 12.0),
                    StressReading(hour: 12, level: .high, confidence: 0.90, meanHR: 110.0, hrvSDNN: 14.0),
                    StressReading(hour: 14, level: .high, confidence: 0.88, meanHR: 118.0, hrvSDNN: 10.0),
                    StressReading(hour: 16, level: .high, confidence: 0.85, meanHR: 108.0, hrvSDNN: 16.0)
                ],
                sleepAssessment: SleepAssessment(
                    score: 25.0, category: .poor,
                    data: SleepData(totalSleepMinutes: 195, deepSleepPct: 0.05, remSleepPct: 0.08,
                                   awakeCount: 7, awakeMinutes: 65, sleepOnsetLatencyMin: 65, restingHRDuringSleep: 75,
                                   respiratoryRate: 18, bloodOxygenAvg: 0.95, bedtimeConsistencyMin: 90)
                ),
                anomalies: [],
                totalSteps: 820,
                totalCalories: 95,
                totalMeetings: 9,
                workoutMinutes: 0,
                restingHeartRate: 82.0,
                screenTimeMinutes: 540,
                averageMETs: 1.3   // très sédentaire
            )
        }
    }

    // MARK: - Legacy Data Injection (kept for HealthKit write test)

    private func injectAndRefresh() async {
        isInjecting = true
        injectionStatus = ""
        do {
            try await HealthKitDataInjector.shared.injectRealisticDay()
            injectionStatus = "✅ Données injectées"
            isInjecting = false
            await engine.analyzeToday()
            if let analysis = engine.dayAnalysis {
                let result = EnergyScoreEngine.score(from: analysis, baseline: engine.personalBaseline)
                withAnimation { energyResult = result }
                isGeneratingBubble = true
                let insight = await InsightGenerator.shared.generateBubbleInsight(from: analysis, mood: result.moodLabel)
                withAnimation { bubbleText = insight; isGeneratingBubble = false }
            }
        } catch {
            injectionStatus = "⚠️ \(error.localizedDescription)"
            isInjecting = false
        }
    }
}

// MARK: - Insight Bubble

struct InsightBubbleView: View {
    let text: String
    let isGenerating: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isGenerating {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.7)
                    Text(String(localized: "Komo réfléchit…"))
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.6))
                }
            } else {
                Text(text)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .accessibilityLabel("Komo says: \(text)")
    }
}

// MARK: - Blob Creature (SwiftUI)

struct KomoBlobView: View {
    let moodLabel: MoodLabel
    @State private var pulsate = false
    @State private var wobble = false

    private var blobColor: (Color, Color) {
        switch moodLabel {
        case .lumineux: return (Color(hex: "7FFFD4"), Color(hex: "00FA9A"))
        case .serein:   return (Color(hex: "48D1CC"), Color(hex: "20B2AA"))
        case .agité:    return (Color(hex: "FFD700"), Color(hex: "FFA500"))
        case .fatigué:  return (Color(hex: "FF8C69"), Color(hex: "FF6347"))
        case .lourd:    return (Color(hex: "9370DB"), Color(hex: "6A0DAD"))
        }
    }

    private var pulseSpeed: Double {
        switch moodLabel {
        case .lumineux: return 1.2
        case .serein:   return 1.8
        case .agité:    return 0.7
        case .fatigué:  return 2.5
        case .lourd:    return 3.0
        }
    }

    var body: some View {
        ZStack {
            // Glow
            Ellipse()
                .fill(blobColor.0.opacity(0.3))
                .frame(width: 160, height: 80)
                .blur(radius: 20)
                .offset(y: 70)

            // Blob body
            BlobShape(wobble: wobble ? 1.0 : 0.0)
                .fill(
                    LinearGradient(
                        colors: [blobColor.0, blobColor.1],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 160, height: 160)
                .scaleEffect(pulsate ? 1.05 : 0.97)
                .overlay(
                    // Eyes
                    HStack(spacing: 24) {
                        EyeView()
                        EyeView()
                    }
                    .offset(y: -10)
                )
                // Sparkles on lumineux
                .overlay(
                    moodLabel == .lumineux ?
                    AnyView(SparkleOverlay()) : AnyView(EmptyView())
                )
        }
        .onAppear {
            withAnimation(.easeInOut(duration: pulseSpeed).repeatForever(autoreverses: true)) {
                pulsate = true
            }
            withAnimation(.easeInOut(duration: pulseSpeed * 1.3).repeatForever(autoreverses: true).delay(0.3)) {
                wobble = true
            }
        }
        .onChange(of: moodLabel) { _, _ in
            // Reset animations on mood change
            pulsate = false
            wobble = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: pulseSpeed).repeatForever(autoreverses: true)) {
                    pulsate = true
                }
            }
        }
        .accessibilityLabel("Komo is feeling \(moodLabel.rawValue)")
    }
}

// MARK: - Blob Shape

struct BlobShape: Shape {
    var wobble: Double

    var animatableData: Double { get { wobble } set { wobble = newValue } }

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let cx = rect.midX, cy = rect.midY
        let offset = wobble * 8.0

        var path = Path()
        path.move(to: CGPoint(x: cx, y: cy - h * 0.48))
        path.addCurve(
            to: CGPoint(x: cx + w * 0.48 + offset, y: cy - h * 0.1),
            control1: CGPoint(x: cx + w * 0.3, y: cy - h * 0.5),
            control2: CGPoint(x: cx + w * 0.5, y: cy - h * 0.3)
        )
        path.addCurve(
            to: CGPoint(x: cx + w * 0.35, y: cy + h * 0.42),
            control1: CGPoint(x: cx + w * 0.5 + offset, y: cy + h * 0.1),
            control2: CGPoint(x: cx + w * 0.45, y: cy + h * 0.35)
        )
        path.addCurve(
            to: CGPoint(x: cx - w * 0.35, y: cy + h * 0.42),
            control1: CGPoint(x: cx + w * 0.1, y: cy + h * 0.5),
            control2: CGPoint(x: cx - w * 0.1, y: cy + h * 0.5)
        )
        path.addCurve(
            to: CGPoint(x: cx - w * 0.48 - offset, y: cy - h * 0.1),
            control1: CGPoint(x: cx - w * 0.45, y: cy + h * 0.35),
            control2: CGPoint(x: cx - w * 0.5, y: cy + h * 0.1)
        )
        path.addCurve(
            to: CGPoint(x: cx, y: cy - h * 0.48),
            control1: CGPoint(x: cx - w * 0.5, y: cy - h * 0.3),
            control2: CGPoint(x: cx - w * 0.3, y: cy - h * 0.5)
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Eye

struct EyeView: View {
    @State private var blink = false
    var body: some View {
        Ellipse()
            .fill(Color(hex: "1A2A1A"))
            .frame(width: 14, height: blink ? 2 : 16)
            .overlay(
                Circle()
                    .fill(.white)
                    .frame(width: 5, height: 5)
                    .offset(x: 2, y: -2)
                    .opacity(blink ? 0 : 1)
            )
            .onAppear {
                // Blink every 4-6 seconds
                let interval = Double.random(in: 4...6)
                Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
                    withAnimation(.easeInOut(duration: 0.1)) { blink = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation(.easeInOut(duration: 0.1)) { blink = false }
                    }
                }
            }
    }
}

// MARK: - Sparkle Overlay (lumineux state)

struct SparkleOverlay: View {
    @State private var animate = false
    var body: some View {
        ForEach(0..<5, id: \.self) { i in
            Image(systemName: "sparkle")
                .font(.system(size: CGFloat.random(in: 8...14)))
                .foregroundStyle(.white.opacity(0.6))
                .offset(
                    x: CGFloat.random(in: -60...60),
                    y: CGFloat.random(in: -60...60)
                )
                .opacity(animate ? 0.8 : 0.1)
                .animation(
                    .easeInOut(duration: Double.random(in: 1.0...2.0))
                    .repeatForever(autoreverses: true)
                    .delay(Double(i) * 0.3),
                    value: animate
                )
        }
        .onAppear { animate = true }
    }
}

// MARK: - Energy Bar

struct EnergyBarView: View {
    let result: EnergyScoreResult
    @Binding var showDetail: Bool
    @State private var animatedProgress: CGFloat = 0

    private var barColor: Color {
        switch result.moodLabel {
        case .lumineux: return .green
        case .serein:   return Color(hex: "48D1CC")
        case .agité:    return .yellow
        case .fatigué:  return .orange
        case .lourd:    return .red
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(String(localized: "Today's Energy Bar"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 22)

                    // Progress fill
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [barColor.opacity(0.7), barColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * animatedProgress, height: 22)

                    // Lightning bolt
                    HStack {
                        Spacer()
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.trailing, 8)
                    }
                    .frame(width: geo.size.width * animatedProgress, height: 22)

                    // Percentage label (outside bar)
                    Text("\(result.energyScore)%")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.leading, geo.size.width * animatedProgress + 8)
                }
            }
            .frame(height: 22)
            .onAppear {
                withAnimation(.easeOut(duration: 1.0).delay(0.3)) {
                    animatedProgress = CGFloat(result.energyScore) / 100.0
                }
            }
            .onChange(of: result.energyScore) { _, newVal in
                withAnimation(.easeOut(duration: 0.6)) {
                    animatedProgress = CGFloat(newVal) / 100.0
                }
            }
            .accessibilityLabel("Energy score: \(result.energyScore) percent, mood: \(result.moodLabel.rawValue)")

            // See detail
            Button(action: { showDetail = true }) {
                HStack(spacing: 4) {
                    Text(String(localized: "See Detail"))
                        .font(.system(size: 13, weight: .medium))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11))
                    Text(String(localized: "More"))
                        .font(.system(size: 13))
                }
                .foregroundStyle(barColor)
            }
            .accessibilityLabel(String(localized: "See Detail"))
        }
    }
}

// MARK: - Action Card

struct ActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(icon)
                .font(.system(size: 22))
            Text(title + ":")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Energy Detail Sheet

struct EnergyDetailView: View {
    let result: EnergyScoreResult?
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var engine: HealthAvatarEngine

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "0A1510").ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        if let result = result {
                            // Score display
                            VStack(spacing: 8) {
                                Text("\(result.energyScore)")
                                    .font(.system(size: 72, weight: .bold, design: .rounded))
                                    .foregroundStyle(.green)
                                Text(result.moodLabel.localizedName.capitalized)
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.8))
                                Text(result.moodLabel.firstPersonContext)
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                            .padding(.top, 20)

                            Divider().background(.white.opacity(0.1))

                            // Score breakdown
                            VStack(alignment: .leading, spacing: 14) {
                                Text(String(localized: "Score Breakdown"))
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white)

                                ScoreRow(label: "Récupération", value: result.breakdown.recoveryTotal, max: 100, color: .green, isBonus: true)
                                ScoreRow(label: "HRV", value: result.breakdown.hrvRecovery, max: 35, color: .cyan, isBonus: true)
                                ScoreRow(label: "Sommeil", value: result.breakdown.sleepRecovery, max: 30, color: .indigo, isBonus: true)
                                ScoreRow(label: "Activité douce", value: result.breakdown.activityRecovery, max: 20, color: .teal, isBonus: true)
                                ScoreRow(label: "FC repos", value: result.breakdown.restingHRRecovery, max: 15, color: .mint, isBonus: true)
                                ScoreRow(label: "Charge totale", value: result.breakdown.loadTotal, max: 55, color: .orange, isBonus: false)
                                ScoreRow(label: "Stress CoreML", value: result.breakdown.stressLoad, max: 25, color: .red, isBonus: false)
                                ScoreRow(label: "Effort intense (HIIT)", value: result.breakdown.workoutPhysicalLoad, max: 15, color: .orange, isBonus: false)
                                ScoreRow(label: "Charge comportementale", value: result.breakdown.behavioralLoad, max: 15, color: .purple, isBonus: false)
                            }
                            .padding(.horizontal, 24)
                        } else {
                            Text("Lance une analyse d'abord")
                                .foregroundStyle(.white.opacity(0.5))
                                .padding(.top, 60)
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "Energy Score"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(String(localized: "Fermer")) { dismiss() }
                        .foregroundStyle(.green)
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}

struct ScoreRow: View {
    let label: String
    let value: Int
    let max: Int
    let color: Color
    let isBonus: Bool

    init(label: String, value: Int, max: Int = 0, color: Color, isBonus: Bool) {
        self.label = label; self.value = value; self.max = max
        self.color = color; self.isBonus = isBonus
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            if max > 0 {
                Text("\(isBonus ? "+" : "-")\(value) / \(max)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isBonus ? color : .orange)
            } else {
                Text("\(value)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.gray)
            }
        }
    }
}

private extension Color {
    init(hex: String) {
        let cleanedHex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var rgbValue: UInt64 = 0
        Scanner(string: cleanedHex).scanHexInt64(&rgbValue)

        let red = Double((rgbValue & 0xFF0000) >> 16) / 255
        let green = Double((rgbValue & 0x00FF00) >> 8) / 255
        let blue = Double(rgbValue & 0x0000FF) / 255

        self.init(red: red, green: green, blue: blue)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(HealthAvatarEngine.shared)
}
