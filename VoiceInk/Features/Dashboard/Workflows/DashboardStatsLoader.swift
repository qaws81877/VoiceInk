import Foundation
import SwiftData

enum DashboardStatsLoader {
    static func load(from modelContainer: ModelContainer) async throws -> DashboardStatsSummary {
        let task = Task.detached(priority: .utility) {
            try Task.checkCancellation()

            let backgroundContext = ModelContext(modelContainer)
            let count = try backgroundContext.fetchCount(FetchDescriptor<SessionMetric>())

            try Task.checkCancellation()

            var allTime = PeriodAccumulator()
            var today = PeriodAccumulator()
            var recentSevenDay = PeriodAccumulator()
            var previousSevenDay = DashboardMetricTotals()
            var lastThirtyDay = PeriodAccumulator()
            var thisYear = PeriodAccumulator()
            var allTimeMonthWords: [Date: Int] = [:]
            var allTimeDayWords: [Date: Int] = [:]
            var firstMetricDate: Date?
            let windows = DashboardPeriodWindows()
            let now = windows.now
            let calendar = windows.calendar
            var todayProductivity = Self.hourlyProductivityPoints(now: now, calendar: calendar)
            var lastSevenDayProductivity = Self.productivityPoints(
                dayCount: 7, now: now, calendar: calendar, labelStyle: .weekday)
            var lastThirtyDayProductivity = Self.productivityPoints(
                dayCount: 30, now: now, calendar: calendar, labelStyle: .dayOfMonth)
            var thisYearProductivity = Self.monthlyProductivityPoints(
                from: windows.thisYearStart, through: now, calendar: calendar)
            var thisYearDailyActivity = Self.dailyProductivityPoints(
                from: windows.thisYearStart, through: now, calendar: calendar)
            let todayHourIndices = Self.indexMap(for: todayProductivity) { startOfHour(for: $0, calendar: calendar) }
            let sevenDayIndices = Self.indexMap(for: lastSevenDayProductivity) { calendar.startOfDay(for: $0) }
            let thirtyDayIndices = Self.indexMap(for: lastThirtyDayProductivity) { calendar.startOfDay(for: $0) }
            let thisYearMonthIndices = Self.indexMap(for: thisYearProductivity) {
                startOfMonth(for: $0, calendar: calendar)
            }
            let thisYearDayIndices = Self.indexMap(for: thisYearDailyActivity) { calendar.startOfDay(for: $0) }
            // Only metrics inside the span of today's hour buckets can match `todayHourIndices`,
            // so the per-metric hour lookup is skipped outside it. Without a span, every metric is looked up.
            let todayHourSpan: Range<Date>? = {
                guard let first = todayProductivity.first?.date,
                    let last = todayProductivity.last?.date,
                    let lastEnd = calendar.dateInterval(of: .hour, for: last)?.end,
                    first < lastEnd
                else {
                    return nil
                }
                return first..<lastEnd
            }()
            var offset = 0

            while offset < count {
                try Task.checkCancellation()

                var descriptor = FetchDescriptor<SessionMetric>(
                    sortBy: [SortDescriptor(\SessionMetric.timestamp, order: .forward)]
                )
                descriptor.fetchLimit = 5_000
                descriptor.fetchOffset = offset

                let records = try backgroundContext.fetch(descriptor)
                if records.isEmpty {
                    break
                }

                if firstMetricDate == nil {
                    firstMetricDate = records.first?.timestamp
                }

                for metric in records {
                    let timestamp = metric.timestamp
                    let isToday = windows.todayInterval.contains(timestamp)
                    let isRecentSevenDay = windows.recentSevenDayInterval.contains(timestamp)
                    let isLastThirtyDay = windows.recentThirtyDayInterval.contains(timestamp)
                    let isThisYear = windows.thisYearInterval.contains(timestamp)

                    if isRecentSevenDay == false, windows.previousSevenDayInterval.contains(timestamp) {
                        previousSevenDay.add(metric)
                    }

                    if todayHourSpan?.contains(timestamp) ?? true,
                        let todayHourIndex = todayHourIndices[startOfHour(for: timestamp, calendar: calendar)]
                    {
                        todayProductivity[todayHourIndex].words += metric.wordCount
                    }

                    let metricDay = calendar.startOfDay(for: timestamp)
                    let metricMonth = startOfMonth(for: timestamp, calendar: calendar)
                    if let weekIndex = sevenDayIndices[metricDay] {
                        lastSevenDayProductivity[weekIndex].words += metric.wordCount
                    }
                    if let monthIndex = thirtyDayIndices[metricDay] {
                        lastThirtyDayProductivity[monthIndex].words += metric.wordCount
                    }
                    if isThisYear {
                        if let thisYearIndex = thisYearMonthIndices[metricMonth] {
                            thisYearProductivity[thisYearIndex].words += metric.wordCount
                        }
                        if let thisYearDayIndex = thisYearDayIndices[metricDay] {
                            thisYearDailyActivity[thisYearDayIndex].words += metric.wordCount
                        }
                    }
                    allTimeMonthWords[metricMonth, default: 0] += metric.wordCount
                    allTimeDayWords[metricDay, default: 0] += metric.wordCount

                    let sample = PeriodSample(
                        metric: metric,
                        transcriptionModelName: sanitizedModelName(metric.transcriptionModelName),
                        enhancementModelName: sanitizedModelName(metric.aiEnhancementModelName),
                        hour: calendar.component(.hour, from: timestamp),
                        day: metricDay
                    )
                    if isToday { today.add(sample) }
                    if isRecentSevenDay { recentSevenDay.add(sample) }
                    if isLastThirtyDay { lastThirtyDay.add(sample) }
                    if isThisYear { thisYear.add(sample) }
                    allTime.add(sample)
                }

                offset += records.count
            }

            try Task.checkCancellation()

            let allTimeProductivity: [DashboardProductivityPoint] = {
                guard let firstMetricDate else { return [] }
                return Self.monthlyProductivityPoints(
                    from: firstMetricDate,
                    through: now,
                    calendar: calendar,
                    wordsByMonth: allTimeMonthWords
                )
            }()
            let allTimeDailyActivity: [DashboardProductivityPoint] = {
                guard let firstMetricDate else { return [] }
                return Self.dailyProductivityPoints(
                    from: firstMetricDate,
                    through: now,
                    calendar: calendar,
                    wordsByDay: allTimeDayWords
                )
            }()

            return DashboardStatsSummary(
                totalCount: count,
                totalWords: allTime.totals.words,
                totalDuration: allTime.totals.duration,
                todayCount: today.totals.count,
                todayWords: today.totals.words,
                todayDuration: today.totals.duration,
                recentSevenDayCount: recentSevenDay.totals.count,
                recentSevenDayWords: recentSevenDay.totals.words,
                recentSevenDayDuration: recentSevenDay.totals.duration,
                previousSevenDayCount: previousSevenDay.count,
                previousSevenDayWords: previousSevenDay.words,
                previousSevenDayDuration: previousSevenDay.duration,
                lastThirtyDayCount: lastThirtyDay.totals.count,
                lastThirtyDayWords: lastThirtyDay.totals.words,
                lastThirtyDayDuration: lastThirtyDay.totals.duration,
                thisYearCount: thisYear.totals.count,
                thisYearWords: thisYear.totals.words,
                thisYearDuration: thisYear.totals.duration,
                todayProductivity: todayProductivity,
                lastSevenDayProductivity: lastSevenDayProductivity,
                lastThirtyDayProductivity: lastThirtyDayProductivity,
                thisYearProductivity: thisYearProductivity,
                allTimeProductivity: allTimeProductivity,
                thisYearDailyActivity: thisYearDailyActivity,
                allTimeDailyActivity: allTimeDailyActivity,
                todayModelPerformance: today.modelPerformance,
                lastSevenDayModelPerformance: recentSevenDay.modelPerformance,
                lastThirtyDayModelPerformance: lastThirtyDay.modelPerformance,
                thisYearModelPerformance: thisYear.modelPerformance,
                allTimeModelPerformance: allTime.modelPerformance,
                todayModelUsage: today.modelUsage,
                lastSevenDayModelUsage: recentSevenDay.modelUsage,
                lastThirtyDayModelUsage: lastThirtyDay.modelUsage,
                thisYearModelUsage: thisYear.modelUsage,
                allTimeModelUsage: allTime.modelUsage,
                todayPeakHours: today.peakHours,
                lastSevenDayPeakHours: recentSevenDay.peakHours,
                lastThirtyDayPeakHours: lastThirtyDay.peakHours,
                thisYearPeakHours: thisYear.peakHours,
                allTimePeakHours: allTime.peakHours
            )
        }

        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private static func monthlyProductivityPoints(
        from startDate: Date,
        through endDate: Date,
        calendar: Calendar,
        wordsByMonth: [Date: Int] = [:]
    ) -> [DashboardProductivityPoint] {
        let startMonth = startOfMonth(for: startDate, calendar: calendar)
        let endMonth = startOfMonth(for: endDate, calendar: calendar)
        guard let monthCount = calendar.dateComponents([.month], from: startMonth, to: endMonth).month else {
            return []
        }

        let labelFormatter = dateFormatter(calendar: calendar)
        labelFormatter.dateFormat = "MMM"

        let accessibilityFormatter = dateFormatter(calendar: calendar)
        accessibilityFormatter.dateFormat = "MMMM yyyy"

        return (0...max(monthCount, 0)).compactMap { offset in
            guard let date = calendar.date(byAdding: .month, value: offset, to: startMonth) else {
                return nil
            }

            return DashboardProductivityPoint(
                date: startOfMonth(for: date, calendar: calendar),
                label: labelFormatter.string(from: date),
                accessibilityLabel: accessibilityFormatter.string(from: date),
                words: wordsByMonth[startOfMonth(for: date, calendar: calendar), default: 0]
            )
        }
    }

    private static func dailyProductivityPoints(
        from startDate: Date,
        through endDate: Date,
        calendar: Calendar,
        wordsByDay: [Date: Int] = [:]
    ) -> [DashboardProductivityPoint] {
        let firstDay = calendar.startOfDay(for: startDate)
        let lastDay = calendar.startOfDay(for: endDate)
        guard let dayCount = calendar.dateComponents([.day], from: firstDay, to: lastDay).day else {
            return []
        }

        let labelFormatter = dateFormatter(calendar: calendar)
        labelFormatter.setLocalizedDateFormatFromTemplate("MMM d")

        let accessibilityFormatter = dateFormatter(calendar: calendar)
        accessibilityFormatter.dateStyle = .full

        return (0...max(dayCount, 0)).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: firstDay) else {
                return nil
            }

            let day = calendar.startOfDay(for: date)
            return DashboardProductivityPoint(
                date: day,
                label: labelFormatter.string(from: day),
                accessibilityLabel: accessibilityFormatter.string(from: day),
                words: wordsByDay[day, default: 0]
            )
        }
    }

    private static func hourlyProductivityPoints(
        now: Date,
        calendar: Calendar
    ) -> [DashboardProductivityPoint] {
        let todayStart = calendar.startOfDay(for: now)
        // Label and accessibility label use the same localized hour format.
        let hourFormatter = Formatters.localizedHourFormatter(calendar: calendar)

        return (0..<24).compactMap { offset in
            guard let date = calendar.date(byAdding: .hour, value: offset, to: todayStart) else {
                return nil
            }

            return DashboardProductivityPoint(
                date: startOfHour(for: date, calendar: calendar),
                label: hourFormatter.string(from: date),
                accessibilityLabel: hourFormatter.string(from: date)
            )
        }
    }

    private static func productivityPoints(
        dayCount: Int,
        now: Date,
        calendar: Calendar,
        labelStyle: DashboardProductivityLabelStyle
    ) -> [DashboardProductivityPoint] {
        guard let startDate = calendar.date(byAdding: .day, value: -(dayCount - 1), to: calendar.startOfDay(for: now))
        else {
            return []
        }

        let labelFormatter = dateFormatter(calendar: calendar)
        labelFormatter.dateFormat = labelStyle.dateFormat

        let accessibilityFormatter = dateFormatter(calendar: calendar)
        accessibilityFormatter.dateStyle = .medium

        return (0..<dayCount).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: startDate) else {
                return nil
            }

            return DashboardProductivityPoint(
                date: calendar.startOfDay(for: date),
                label: labelFormatter.string(from: date),
                accessibilityLabel: accessibilityFormatter.string(from: date)
            )
        }
    }

    /// A formatter with the dashboard calendar and current locale; callers set the format.
    private static func dateFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current
        return formatter
    }

    /// Maps each point's bucket key (from `key`) to its index in `points`.
    private static func indexMap(
        for points: [DashboardProductivityPoint],
        key: (Date) -> Date
    ) -> [Date: Int] {
        Dictionary(
            uniqueKeysWithValues: points.enumerated().map { index, point in
                (key(point.date), index)
            })
    }

    private static func modelPerformance(
        transcription: [String: ModelPerformanceAccumulator],
        enhancement: [String: ModelPerformanceAccumulator]
    ) -> [ModelPerformanceSummary] {
        let transcriptionSummaries = transcription.map { name, accumulator in
            accumulator.summary(kind: .transcription, name: name)
        }
        let enhancementSummaries = enhancement.map { name, accumulator in
            accumulator.summary(kind: .enhancement, name: name)
        }

        return transcriptionSummaries.sortedForPerformanceDisplay() + enhancementSummaries.sortedForPerformanceDisplay()
    }

    private static func modelUsage(
        transcriptionAudio: [String: TranscriptionAudioUsageAccumulator],
        enhancementTokens: [String: EnhancementTokenUsageAccumulator]
    ) -> ModelUsageSummary {
        let transcriptionSummaries =
            transcriptionAudio
            .map { name, accumulator in accumulator.summary(name: name) }
            .sorted { lhs, rhs in
                if lhs.totalAudioDuration != rhs.totalAudioDuration {
                    return lhs.totalAudioDuration > rhs.totalAudioDuration
                }

                if lhs.sessionCount != rhs.sessionCount {
                    return lhs.sessionCount > rhs.sessionCount
                }

                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

        let enhancementSummaries =
            enhancementTokens
            .map { name, accumulator in accumulator.summary(name: name) }
            .sorted { lhs, rhs in
                if lhs.estimatedTokens != rhs.estimatedTokens {
                    return lhs.estimatedTokens > rhs.estimatedTokens
                }

                if lhs.sessionCount != rhs.sessionCount {
                    return lhs.sessionCount > rhs.sessionCount
                }

                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

        return ModelUsageSummary(
            transcriptionModels: transcriptionSummaries,
            enhancementModels: enhancementSummaries
        )
    }

    private static func peakHoursSummary(from peakHours: [Int: DashboardPeakHourAccumulator])
        -> DashboardPeakHoursSummary
    {
        let hourlyActivity = (0..<24).map { hour in
            peakHours[hour, default: DashboardPeakHourAccumulator()].point(hour: hour)
        }

        var bestStartHour = 0
        var bestWordCount = 0
        var bestSessionCount = 0

        for startHour in 0..<24 {
            let first = peakHours[startHour, default: DashboardPeakHourAccumulator()]
            let second = peakHours[(startHour + 1) % 24, default: DashboardPeakHourAccumulator()]
            let windowWordCount = first.wordCount + second.wordCount
            let windowSessionCount = first.sessionCount + second.sessionCount

            if windowWordCount > bestWordCount
                || (windowWordCount == bestWordCount && windowSessionCount > bestSessionCount)
            {
                bestStartHour = startHour
                bestWordCount = windowWordCount
                bestSessionCount = windowSessionCount
            }
        }

        return DashboardPeakHoursSummary(
            startHour: bestStartHour,
            endHour: (bestStartHour + 2) % 24,
            wordCount: bestWordCount,
            sessionCount: bestSessionCount,
            hourlyActivity: hourlyActivity
        )
    }

    /// One metric with the per-metric values every period needs, computed once.
    private struct PeriodSample {
        let metric: SessionMetric
        let transcriptionModelName: String?
        let enhancementModelName: String?
        let hour: Int
        let day: Date
    }

    /// Totals, model performance/usage and peak hours for one dashboard period.
    private struct PeriodAccumulator {
        var totals = DashboardMetricTotals()
        var transcriptionPerformance: [String: ModelPerformanceAccumulator] = [:]
        var enhancementPerformance: [String: ModelPerformanceAccumulator] = [:]
        var transcriptionAudioUsage: [String: TranscriptionAudioUsageAccumulator] = [:]
        var enhancementTokenUsage: [String: EnhancementTokenUsageAccumulator] = [:]
        var peakHourBuckets: [Int: DashboardPeakHourAccumulator] = [:]

        mutating func add(_ sample: PeriodSample) {
            let metric = sample.metric
            totals.add(metric)

            if let modelName = sample.transcriptionModelName {
                if let transcriptionDuration = metric.transcriptionDuration, transcriptionDuration > 0 {
                    transcriptionPerformance[modelName, default: ModelPerformanceAccumulator()].add(
                        processingDuration: transcriptionDuration,
                        audioDuration: metric.audioDuration
                    )
                }
                if metric.audioDuration > 0 {
                    transcriptionAudioUsage[modelName, default: TranscriptionAudioUsageAccumulator()].add(
                        audioDuration: metric.audioDuration
                    )
                }
            }

            if let modelName = sample.enhancementModelName {
                if let enhancementDuration = metric.enhancementDuration, enhancementDuration > 0 {
                    enhancementPerformance[modelName, default: ModelPerformanceAccumulator()].add(
                        processingDuration: enhancementDuration
                    )
                }
                let tokens = max(metric.enhancementEstimatedTokenCount ?? 0, 0)
                enhancementTokenUsage[modelName, default: EnhancementTokenUsageAccumulator()].add(
                    tokens: tokens
                )
            }

            peakHourBuckets[sample.hour, default: DashboardPeakHourAccumulator()].add(
                words: metric.wordCount,
                audioDuration: metric.audioDuration,
                day: sample.day
            )
        }

        var modelPerformance: [ModelPerformanceSummary] {
            DashboardStatsLoader.modelPerformance(
                transcription: transcriptionPerformance,
                enhancement: enhancementPerformance
            )
        }

        var modelUsage: ModelUsageSummary {
            DashboardStatsLoader.modelUsage(
                transcriptionAudio: transcriptionAudioUsage,
                enhancementTokens: enhancementTokenUsage
            )
        }

        var peakHours: DashboardPeakHoursSummary {
            DashboardStatsLoader.peakHoursSummary(from: peakHourBuckets)
        }
    }
}

private extension DashboardMetricTotals {
    mutating func add(_ metric: SessionMetric) {
        count += 1
        words += metric.wordCount
        duration += metric.audioDuration
    }
}

private func startOfMonth(for date: Date, calendar: Calendar) -> Date {
    calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
}

private func startOfHour(for date: Date, calendar: Calendar) -> Date {
    calendar.dateInterval(of: .hour, for: date)?.start ?? date
}

private enum DashboardProductivityLabelStyle {
    case weekday
    case dayOfMonth

    var dateFormat: String {
        switch self {
        case .weekday: return "E"
        case .dayOfMonth: return "d"
        }
    }
}

private struct ModelPerformanceAccumulator {
    var sessionCount = 0
    var totalProcessingDuration: TimeInterval = 0
    var totalAudioDuration: TimeInterval = 0

    mutating func add(processingDuration: TimeInterval, audioDuration: TimeInterval = 0) {
        sessionCount += 1
        totalProcessingDuration += processingDuration
        totalAudioDuration += max(audioDuration, 0)
    }

    func summary(kind: ModelInsightKind, name: String) -> ModelPerformanceSummary {
        ModelPerformanceSummary(
            kind: kind,
            name: name,
            sessionCount: sessionCount,
            averageProcessingDuration: sessionCount > 0 ? totalProcessingDuration / Double(sessionCount) : nil,
            averageSpeedFactor: totalProcessingDuration > 0 && totalAudioDuration > 0
                ? totalAudioDuration / totalProcessingDuration : nil
        )
    }
}

private struct TranscriptionAudioUsageAccumulator {
    var sessionCount = 0
    var totalAudioDuration: TimeInterval = 0

    mutating func add(audioDuration: TimeInterval) {
        sessionCount += 1
        totalAudioDuration += audioDuration
    }

    func summary(name: String) -> TranscriptionModelUsage {
        TranscriptionModelUsage(
            name: name,
            sessionCount: sessionCount,
            totalAudioDuration: totalAudioDuration
        )
    }
}

private struct EnhancementTokenUsageAccumulator {
    var sessionCount = 0
    var estimatedTokens = 0

    mutating func add(tokens: Int) {
        sessionCount += 1
        estimatedTokens += tokens
    }

    func summary(name: String) -> EnhancementTokenUsage {
        EnhancementTokenUsage(
            name: name,
            sessionCount: sessionCount,
            estimatedTokens: estimatedTokens
        )
    }
}

private struct DashboardPeakHourAccumulator {
    var wordCount = 0
    var sessionCount = 0
    var audioDuration: TimeInterval = 0
    var activeDays: Set<Date> = []

    mutating func add(words: Int, audioDuration: TimeInterval, day: Date) {
        wordCount += words
        sessionCount += 1
        self.audioDuration += audioDuration
        activeDays.insert(day)
    }

    func point(hour: Int) -> DashboardHourlyActivityPoint {
        DashboardHourlyActivityPoint(
            hour: hour,
            wordCount: wordCount,
            sessionCount: sessionCount,
            audioDuration: audioDuration,
            activeDayCount: activeDays.count
        )
    }
}

private func sanitizedModelName(_ name: String?) -> String? {
    guard let name else {
        return nil
    }

    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
