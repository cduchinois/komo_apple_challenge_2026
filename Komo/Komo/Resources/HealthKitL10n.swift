//  HealthKitL10n.swift
//  Komo
//
//  Localized HealthKit insight lines, stats labels, and dynamic reflections.

import Foundation

enum HealthKitL10n {
    // MARK: - Headlines & fallbacks

    static var tapBlobAnalyze: String { loc("Tap the blob to analyze your day.") }
    static var tapBlobLoad: String { loc("Tap the blob to load today's energy.") }
    static var tapBlobStartCheckIn: String { loc("Tap the blob to start your first check-in.") }
    static var dataStaysPrivate: String { loc("Your data stays private on this device.") }
    static var readyWhenYouAre: String { loc("Ready when you are.") }
    static var loading: String { loc("Loading…") }
    static var breakdownSubtitle: String {
        loc("based on sleep, movement, stress, and calendar load")
    }

    static var breakdownExplanation: String {
        loc("Each row shows what that signal actually added or removed today.")
    }

    // MARK: - Breakdown labels & details

    static var breakdownSleep: String { loc("Sleep") }
    static var breakdownRecovery: String { loc("Recovery") }
    static var breakdownHeart: String { loc("Heart at rest") }
    static var breakdownMovement: String { loc("Movement") }
    static var breakdownStress: String { loc("Stress") }
    static var breakdownCalendar: String { loc("Calendar") }
    static var breakdownWorkoutLoad: String { loc("Workout effort") }
    static var breakdownNoData: String { loc("no data") }
    static var breakdownCalmDay: String { loc("calm all day") }
    static var breakdownNoMeetings: String { loc("no meetings") }

    static func breakdownSleepDetail(hours: String, score: Int) -> String {
        let quality: String
        switch score {
        case 80...: quality = loc("solid rest")
        case 60..<80: quality = loc("okay rest")
        default: quality = loc("short night")
        }
        return fmt("%1$@h · %2$@", hours, quality)
    }

    static func breakdownRecoveryLevel(level: Int) -> String {
        switch level {
        case 3: return loc("well recovered")
        case 2: return loc("moderate recovery")
        default: return loc("still tired")
        }
    }

    static func breakdownHeartLevel(level: Int) -> String {
        switch level {
        case 3: return loc("calm at rest")
        case 2: return loc("a little elevated")
        default: return loc("working hard at rest")
        }
    }

    static func breakdownSteps(_ steps: Int) -> String {
        fmt("%1$lld steps today", steps)
    }

    static func breakdownStressHours(_ hours: Int) -> String {
        fmt("%1$lld tense hours", hours)
    }

    static func breakdownMeetings(_ count: Int) -> String {
        count == 1
            ? loc("1 meeting")
            : fmt("%1$lld meetings", count)
    }

    static func breakdownWorkoutMinutes(_ minutes: Int) -> String {
        fmt("%1$lld min of effort", minutes)
    }

    static func breakdownFooter(recovery: String, load: String, percent: Int) -> String {
        fmt("%1$@ recovered · %2$@ drained = %3$lld%%", recovery, load, percent)
    }

    // MARK: - Personalized reflections

    static func sleepBelowThreshold(hours: String) -> String {
        fmt("only %1$@ hours of sleep last night. that's less than your body needs.", hours)
    }

    static func sleepShort(hours: String) -> String {
        fmt("you got %1$@ hours of sleep. a little short for feeling fully rested.", hours)
    }

    static func sleepSolid(hours: String) -> String {
        fmt("about %1$@ hours of sleep last night. your body had a good chance to recover.", hours)
    }

    static var sleepNoDataObservation: String {
        loc("komo couldn't read your sleep data last night.")
    }

    static var sleepNoDataSuggestion: String {
        loc("make sure your Apple Watch or iPhone is charging nearby while you sleep.")
    }

    static var sleepShortSuggestion: String {
        loc("try to be in bed 45 minutes earlier tonight to recover.")
    }

    static var sleepMediumSuggestion: String {
        loc("a 15-minute nap this afternoon or an earlier bedtime tonight would help.")
    }

    static var sleepSolidSuggestion: String {
        loc("you're rested. maybe use that good energy on something you care about.")
    }

    static func stepsLow(_ steps: String) -> String {
        fmt("you've only moved %1$@ steps so far today.", steps)
    }

    static func stepsMid(_ steps: String) -> String {
        fmt("%1$@ steps so far. you're about halfway to your daily goal.", steps)
    }

    static func stepsHigh(_ steps: String) -> String {
        fmt("you walked a lot today. %1$@ steps, well above your usual goal.", steps)
    }

    static var stepsLowSuggestion: String {
        loc("a 10-minute walk right now would reset your body and your focus.")
    }

    static var stepsMidSuggestion: String {
        loc("try a short walk before your next task to hit 5,000.")
    }

    static var stepsHighSuggestion: String {
        loc("you moved a lot. let the evening be for rest, not another big effort.")
    }

    static func hrvLow(_: Int) -> String {
        loc("your body seems tired today. recovery looks lower than usual.")
    }

    static func hrvHigh(_: Int) -> String {
        loc("your body recovered well. you have good energy reserves today.")
    }

    static var hrvLowSuggestion: String {
        loc("keep today light and protect your sleep tonight.")
    }

    static var hrvHighSuggestion: String {
        loc("this is a good window for a workout or deep focus work.")
    }

    static func rhrElevated(_: Int) -> String {
        loc("your heart is working a bit harder than usual at rest.")
    }

    static func rhrStrong(_: Int) -> String {
        loc("your heart looks calm at rest. a good sign your body is recovering.")
    }

    static var rhrElevatedSuggestion: String {
        loc("this can signal fatigue or stress. slow the pace today if you can.")
    }

    static var rhrStrongSuggestion: String {
        loc("a calm heart at rest is a good sign. your body is adapting well.")
    }

    static func stressHigh(hours: Int) -> String {
        fmt("your heart rate has been elevated for %1$lld hours today.", hours)
    }

    static var stressHighSuggestion: String {
        loc("take 3 minutes now to breathe. your nervous system will thank you.")
    }

    static var stressLowObservation: String {
        loc("your stress levels have been low all day.")
    }

    static var stressLowSuggestion: String {
        loc("a calm day is a gift. notice what made it easier and try to repeat it.")
    }

    static func meetingsHeavy(_ count: Int) -> String {
        fmt("you have %1$lld meetings today. it's a full day for your head.", count)
    }

    static var meetingsHeavySuggestion: String {
        loc("block a 10-minute gap between your meetings to decompress.")
    }

    static var meetingsClearObservation: String {
        loc("no meetings on your calendar today. a clear runway.")
    }

    static var meetingsClearSuggestion: String {
        loc("protect the focus time. start with the one thing that matters most.")
    }

    // MARK: - Stats

    static var statHeartRate: String { loc("Heart Rate") }
    static var statSteps: String { loc("Steps") }
    static var statSleep: String { loc("Sleep") }
    static var statStress: String { loc("Stress") }
    static var statHRV: String { loc("Recovery") }
    static var statActivity: String { loc("Activity") }
    static var statCalendar: String { loc("Calendar Load") }
    static var unitBPM: String { loc("bpm") }
    static var unitCal: String { loc("cal") }
    static var stressValueLow: String { loc("Low") }
    static var stressValueHigh: String { loc("High") }
    static var restingCalm: String { loc("Resting · calm") }
    static var restingElevated: String { loc("Resting · a little elevated") }
    static func stepsGoalPercent(_ pct: Int) -> String {
        fmt("%1$lld%% of your goal", pct)
    }
    static func sleepScoreSub(score: Int) -> String {
        fmt("Last night · score %1$lld/100", score)
    }
    static var stressNone: String { loc("No stress spikes") }
    static var stressMild: String { loc("Mild tension") }
    static var stressModerate: String { loc("Moderate load") }
    static var stressHighLabel: String { loc("High stress") }
    static var hrvWellRecovered: String { loc("Well recovered") }
    static var hrvModerate: String { loc("Moderate") }
    static var hrvLowRecovery: String { loc("Low recovery") }
    static var activityRingAlmost: String { loc("Move ring almost closed") }
    static var activityKeepMoving: String { loc("Keep moving") }
    static var calendarHeavy: String { loc("Heavy meeting day") }
    static var calendarManageable: String { loc("Manageable load") }
    static func calendarEventUnit(_ count: Int) -> String {
        count == 1 ? loc("event") : loc("events")
    }

    // MARK: - Breakdown

    static var noSignificantLoad: String { loc("No significant load") }
    static var calmDayDetail: String {
        loc("calm day. stress, calendar and workout all low.")
    }

    // MARK: - Rule-based insight lines

    static func insightSleepRecovered(hours: String) -> String {
        fmt("about %1$@ hours of sleep last night. your body had time to recover.", hours)
    }

    static func insightSleepShort(hours: String) -> String {
        fmt("Only %1$@ hours of sleep. A short nap this afternoon could help.", hours)
    }

    static func insightSleepDeep(hours: String, deepPct: Int) -> String {
        fmt("%1$@ hours of sleep. decent rest, but deep sleep was only %2$lld%%.", hours, deepPct)
    }

    static func insightStressLogged(hours: Int) -> String {
        fmt("stress was high for about %1$lld hours today. a short breath break could help.", hours)
    }

    static var insightStressLow: String {
        loc("low stress all day. that's rare. notice how it feels.")
    }

    static func insightStressPeak(hour: Int, bpm: Int) -> String {
        fmt("stress peaked around %1$lld:00 today.", hour)
    }

    static func insightStepsStrong(_ steps: Int) -> String {
        fmt("you walked a lot today. %1$lld steps, one of your stronger days.", steps)
    }

    static func insightStepsProgress(steps: Int, pct: Int) -> String {
        fmt("At %1$lld steps you're %2$lld%% of the way to your goal.", steps, pct)
    }

    static var insightTapBlob: String {
        loc("Tap the blob to load today's energy data.")
    }

    // MARK: - AI fallback (when Foundation Models unavailable)

    static func aiFallbackObservationSleep(detail: String, energyWord: String) -> String {
        fmt("your energy feels %1$@ today. sleep is the main reason.", energyWord)
    }

    static func aiFallbackObservationHRV(detail: String) -> String {
        loc("how well your body recovered is the main thing shaping today.")
    }

    static func aiFallbackObservationRHR(detail: String) -> String {
        loc("your heart at rest is shaping how you feel today.")
    }

    static func aiFallbackObservationActivity(detail: String) -> String {
        loc("how much you moved today is your biggest lever.")
    }

    static func aiFallbackObservationStress(detail: String) -> String {
        loc("stress is weighing on your energy today.")
    }

    static func aiFallbackObservationMeetings(detail: String) -> String {
        loc("your calendar is adding a lot to your day.")
    }

    static func aiFallbackObservationWorkout(detail: String) -> String {
        loc("today's workout is part of how tired or recovered you feel.")
    }

    static var aiFallbackSuggestionSleepRecover: String {
        loc("Protect an earlier wind-down tonight to recover.")
    }

    static var aiFallbackSuggestionSleepUse: String {
        loc("Use this recovery window for something that matters.")
    }

    static var aiFallbackSuggestionHRVRest: String {
        loc("keep today lighter. your body needs a gentler pace.")
    }

    static var aiFallbackSuggestionHRVFocus: String {
        loc("This is a good window for focus or movement.")
    }

    static var aiFallbackSuggestionRHR: String {
        loc("Slow the pace where you can and hydrate.")
    }

    static var aiFallbackSuggestionActivityHigh: String {
        loc("A short walk could keep momentum without draining you.")
    }

    static var aiFallbackSuggestionActivityLow: String {
        loc("Try 7 minutes of easy movement, no phone.")
    }

    static var aiFallbackSuggestionStress: String {
        loc("Take 3 minutes to breathe before your next task.")
    }

    static var aiFallbackSuggestionMeetings: String {
        loc("Block 10 minutes between meetings to decompress.")
    }

    static var aiFallbackSuggestionWorkout: String {
        loc("prioritize recovery tonight. sleep and quiet time.")
    }

    // MARK: - Recharged / used by

    static var partSleep: String { loc("sleep") }
    static var partMovement: String { loc("movement") }
    static var partHRV: String { loc("recovery") }
    static var partRest: String { loc("rest") }
    static var partStress: String { loc("stress") }
    static var partMeetings: String { loc("meetings") }
    static var partPoorSleep: String { loc("poor sleep") }
    static var partNormalActivity: String { loc("normal activity") }

    // MARK: - Helpers

    private static func loc(_ key: String.LocalizationValue) -> String {
        String(localized: key)
    }

    private static func fmt(_ key: String.LocalizationValue, _ args: CVarArg...) -> String {
        String(format: String(localized: key), locale: Locale.current, arguments: args)
    }
}
