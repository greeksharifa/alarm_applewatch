import Foundation
import Testing
@testable import AlarmCore

@Test func fixedConfigurationContainsThreeDailyPhases() {
    let configuration = AlarmConfiguration.fixedDaily

    #expect(configuration.phases.map(\.id) == ["first", "second", "third"])
    #expect(configuration.phases.map(\.hour) == [7, 7, 8])
    #expect(configuration.phases.map(\.minute) == [40, 50, 0])
    #expect(configuration.phases.map(\.second) == [0, 0, 0])
    #expect(configuration.phases.map(\.durationSeconds) == [5, 20, 300])
}

@Test func scheduleCalculatorReturnsNextPhaseTodayOrTomorrow() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!

    let calculator = AlarmScheduleCalculator(configuration: .fixedDaily, calendar: calendar)
    let beforeFirst = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 7, minute: 39)))
    let afterLast = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 8, minute: 6)))

    let first = try #require(calculator.nextPhase(after: beforeFirst))
    let tomorrow = try #require(calculator.nextPhase(after: afterLast))

    #expect(first.phase.id == "first")
    #expect(calendar.component(.day, from: first.startDate) == 14)
    #expect(tomorrow.phase.id == "first")
    #expect(calendar.component(.day, from: tomorrow.startDate) == 15)
}

@Test func scheduleCalculatorReturnsCurrentPhaseWhenNowIsInsidePhaseWindow() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!

    let calculator = AlarmScheduleCalculator(configuration: .fixedDaily, calendar: calendar)
    let duringThird = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 8, minute: 2)))

    let active = try #require(calculator.currentOrNextPhase(at: duringThird))

    #expect(active.phase.id == "third")
    #expect(active.phase.durationSeconds == 180)
    #expect(active.startDate == duringThird)
}

@Test func scheduleCalculatorPreservesDiagnosticOnePulsePerSecondCadenceWhenNowIsInsidePhaseWindow() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
    let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 1, minute: 20, second: 10)))

    let configuration = AlarmConfiguration.deviceDiagnostic(startingAt: start, calendar: calendar)
    let calculator = AlarmScheduleCalculator(configuration: configuration, calendar: calendar)
    let duringThird = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 1, minute: 21, second: 10)))

    let active = try #require(calculator.currentOrNextPhase(at: duringThird))

    #expect(active.phase.id == "diagnostic-3")
    #expect(active.phase.durationSeconds == 10)
}


@Test func hapticPulsePlanCoversRequestedDuration() {
    #expect(HapticPulsePlan(durationSeconds: 5, intervalSeconds: 1).pulseOffsets == [0, 1, 2, 3, 4])
    #expect(HapticPulsePlan(durationSeconds: 20, intervalSeconds: 1).pulseOffsets.count == 20)
    #expect(HapticPulsePlan(durationSeconds: 300, intervalSeconds: 1).pulseOffsets.count == 300)
    #expect(HapticPulsePlan(durationSeconds: 2, intervalSeconds: 1).tailDelaySeconds == 1)
    #expect(HapticPulsePlan(durationSeconds: 5, intervalSeconds: 2).tailDelaySeconds == 1)
}

@Test func hapticPulsePlanUsesOnePulsePerSecondForTheWholeDuration() {
    let plan = HapticPulsePlan(durationSeconds: 10, intervalSeconds: 1)

    #expect(plan.pulseOffsets == [0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
    #expect(plan.tailDelaySeconds == 1)
}

@Test func simulatorDiagnosticConfigurationUsesShortCurrentTimeOffsetsForVerification() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
    let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 1, minute: 20, second: 10)))

    let configuration = AlarmConfiguration.simulatorDiagnostic(startingAt: start, calendar: calendar)
    let calculator = AlarmScheduleCalculator(configuration: configuration, calendar: calendar)
    let phases = calculator.scheduledPhases(onDayContaining: start)

    #expect(phases.map(\.startDate) == [
        try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 1, minute: 20, second: 20))),
        try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 1, minute: 20, second: 40))),
        try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 1, minute: 21, second: 10)))
    ])
    #expect(configuration.phases.map(\.durationSeconds) == [2, 5, 10])
}

@Test func simulatorWakeWindowDiagnosticSchedulesAlarmsMinutesAfterLaunch() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
    let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 1, minute: 20, second: 10)))

    let configuration = AlarmConfiguration.simulatorWakeWindowDiagnostic(startingAt: start, calendar: calendar)
    let calculator = AlarmScheduleCalculator(configuration: configuration, calendar: calendar)
    let phases = calculator.scheduledPhases(onDayContaining: start)

    #expect(phases.map(\.startDate) == [
        try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 1, minute: 22, second: 10))),
        try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 1, minute: 22, second: 40))),
        try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 1, minute: 23, second: 10)))
    ])
    #expect(configuration.phases.map(\.durationSeconds) == [2, 5, 10])
}

@Test func simulatorWakeWindowDiagnosticStartsGuardBeforeFirstAlarm() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
    let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 1, minute: 20, second: 10)))
    let configuration = AlarmConfiguration.simulatorWakeWindowDiagnostic(startingAt: start, calendar: calendar)
    let policy = AlarmGuardWindowPolicy(
        configuration: configuration,
        prewarmSeconds: 60,
        cooldownSeconds: 30,
        calendar: calendar
    )

    let window = try #require(policy.currentOrNextWindow(at: start))
    let expectedStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 1, minute: 21, second: 10)))
    let expectedEnd = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 1, minute: 23, second: 50)))

    #expect(window.startDate == expectedStart)
    #expect(window.endDate == expectedEnd)
}

@Test func deviceDiagnosticConfigurationUsesShortCurrentTimeOffsetsForPhysicalTesting() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
    let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 1, minute: 20, second: 10)))

    let configuration = AlarmConfiguration.deviceDiagnostic(startingAt: start, calendar: calendar)
    let calculator = AlarmScheduleCalculator(configuration: configuration, calendar: calendar)
    let phases = calculator.scheduledPhases(onDayContaining: start)

    #expect(phases.map(\.startDate) == [
        try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 1, minute: 20, second: 20))),
        try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 1, minute: 20, second: 40))),
        try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 1, minute: 21, second: 10)))
    ])
    #expect(configuration.phases.map(\.durationSeconds) == [2, 5, 10])
}

@Test func manualHapticTestPhasesMatchOnePulsePerSecondDiagnosticPattern() {
    let phases = AlarmConfiguration.manualHapticTestPhases

    #expect(phases.map(\.id) == ["manual-test-1", "manual-test-2", "manual-test-3"])
    #expect(phases.map(\.title) == ["Manual Test 1", "Manual Test 2", "Manual Test 3"])
    #expect(phases.map(\.durationSeconds) == [2, 5, 10])
}

@Test func chargerDiagnosticConfigurationUsesLongPhaseForPhysicalChargerTesting() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
    let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 1, minute: 20, second: 10)))

    let configuration = AlarmConfiguration.chargerDiagnostic(startingAt: start, calendar: calendar)
    let calculator = AlarmScheduleCalculator(configuration: configuration, calendar: calendar)
    let phase = try #require(calculator.scheduledPhases(onDayContaining: start).first)
    let expectedStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 1, minute: 20, second: 20)))

    #expect(phase.startDate == expectedStart)
    #expect(phase.phase.id == "charger-diagnostic")
    #expect(phase.phase.durationSeconds == 90)
}


@Test func batteryStopPolicyStopsOnlyChargingOrFullStates() {
    #expect(BatteryStopPolicy.shouldStop(for: .charging))
    #expect(BatteryStopPolicy.shouldStop(for: .full))
    #expect(!BatteryStopPolicy.shouldStop(for: .unplugged))
    #expect(!BatteryStopPolicy.shouldStop(for: .unknown))
}

@Test func notificationPlanCreatesThreeStableDailyFallbacks() {
    let plan = AlarmNotificationPlan(configuration: .fixedDaily)

    #expect(plan.descriptors.map(\.identifier) == [
        "alarm_applewatch.daily.first",
        "alarm_applewatch.daily.second",
        "alarm_applewatch.daily.third"
    ])
    #expect(plan.descriptors.map(\.hour) == [7, 7, 8])
    #expect(plan.descriptors.map(\.minute) == [40, 50, 0])
}

@Test func guardWindowStartsBeforeFirstAlarmAndEndsAfterLastAlarm() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
    let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 1)))
    let policy = AlarmGuardWindowPolicy(
        configuration: .fixedDaily,
        prewarmSeconds: 300,
        cooldownSeconds: 60,
        calendar: calendar
    )

    let window = try #require(policy.window(onDayContaining: date))
    let expectedStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 7, minute: 35)))
    let expectedEnd = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 8, minute: 6)))

    #expect(window.startDate == expectedStart)
    #expect(window.endDate == expectedEnd)
}

@Test func guardWindowPolicyReturnsCurrentWindowOnlyInsideMorningRange() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
    let policy = AlarmGuardWindowPolicy(configuration: .fixedDaily, calendar: calendar)
    let night = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 2)))
    let inside = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 7, minute: 36)))
    let after = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 8, minute: 6)))
    let expectedStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 7, minute: 35)))

    #expect(policy.currentWindow(at: night) == nil)
    #expect(policy.currentWindow(at: inside)?.startDate == expectedStart)
    #expect(policy.currentWindow(at: after) == nil)
}

@Test func guardWindowPolicyReturnsNextWindowWithoutKeepingWorkoutAliveOvernight() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
    let policy = AlarmGuardWindowPolicy(configuration: .fixedDaily, calendar: calendar)
    let previousNight = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 2)))
    let afterMorning = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 9)))

    let todayWindow = try #require(policy.currentOrNextWindow(at: previousNight))
    let tomorrowWindow = try #require(policy.currentOrNextWindow(at: afterMorning))
    let expectedTodayStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 7, minute: 35)))
    let expectedTomorrowStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 7, minute: 35)))

    #expect(todayWindow.startDate == expectedTodayStart)
    #expect(tomorrowWindow.startDate == expectedTomorrowStart)
}

@Test func aggressiveModeDefaultsOnWhenNoStoredPreferenceExists() {
    #expect(AggressiveModePreference.resolve(storedValue: nil, forceEnabled: false) == true)
}

@Test func aggressiveModeRespectsExplicitStoredPreference() {
    #expect(AggressiveModePreference.resolve(storedValue: false, forceEnabled: false) == false)
    #expect(AggressiveModePreference.resolve(storedValue: true, forceEnabled: false) == true)
}

@Test func aggressiveModeForceEnabledOverridesStoredPreference() {
    #expect(AggressiveModePreference.resolve(storedValue: false, forceEnabled: true) == true)
}
