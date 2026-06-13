import SwiftUI
import StrandDesign
import StrandAnalytics

/// Intelligence — NOOP's own recovery/strain/sleep scores, computed on-device from raw strap data
/// using the WHOOP model shape. Makes the app independent of WHOOP's cloud for live-collected days.
struct IntelligenceView: View {
    @EnvironmentObject var intelligence: IntelligenceEngine
    @EnvironmentObject var live: LiveState

    @State private var range: IntelRange = .month

    // Effort display scale (#268) — routes every Effort value/label on this screen. Display-only.
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    private var effortScale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }

    var body: some View {
        ScreenScaffold(title: "Intelligence",
                       subtitle: "NOOP scores your charge, effort and rest itself — on-device, no cloud.") {
            if let f = forecast { forecastCard(f) }
            explainerCard
            if intelligence.computing {
                StrandCard(padding: 20) {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Crunching your raw streams…").font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                }
            } else if let note = intelligence.note {
                StrandCard(padding: 20) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "moon.zzz.fill").foregroundStyle(StrandPalette.accent)
                            .accessibilityHidden(true)
                        Text(note).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else if intelligence.results.isEmpty {
                // While the strap is mid-offload, say so — "no days" reads as final otherwise (#77).
                if live.backfilling { SyncingHistoryNote(chunks: live.syncChunksThisSession) }
                DataPendingNote(
                    title: "Building from your strap",
                    message: "This builds from the strap as it syncs. Effort and rest appear after you have worn it and slept a night. Charge needs about a week of nights to learn your baseline, or import your WHOOP export to skip the wait.",
                    symbol: "brain.head.profile"
                )
            } else {
                // Header row: section label left, range control right. Narrows the per-day
                // list to a recent window (lexicographic yyyy-MM-dd compare == chronological).
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recent").strandOverline()
                        Text("By Day").font(StrandFont.title2).foregroundStyle(StrandPalette.textPrimary)
                    }
                    Spacer()
                    SegmentedPillControl(IntelRange.allCases, selection: $range) { $0.label }
                }
                Text("\(filtered.count) \(filtered.count == 1 ? "day" : "days")")
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if filtered.isEmpty {
                    StrandCard(padding: 18) {
                        Text("No scored days in this window. Widen the range or import more history.")
                            .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    ForEach(filtered) { day in
                        dayCard(day)
                    }
                }
            }
        }
        .task { if intelligence.results.isEmpty { await intelligence.analyzeRecent() } }
        .toolbar {
            ToolbarItem {
                Button { Task { await intelligence.analyzeRecent() } } label: {
                    Label("Recompute", systemImage: "arrow.clockwise")
                }
                .disabled(intelligence.computing)
            }
        }
    }

    /// The day list narrowed to the selected window. `nil` cutoff (ALL) shows everything.
    private var filtered: [IntelligenceEngine.Computed] {
        guard let n = range.days else { return intelligence.results }
        let date = Calendar.current.date(byAdding: .day, value: -(n - 1), to: Date()) ?? Date()
        let cutoff = Self.dayFmt.string(from: date)
        return intelligence.results.filter { $0.day >= cutoff }
    }

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Evening forecast of tomorrow-morning Charge from tonight's known levers. Anchored to
    /// the recent Charge baseline, nudged by today's Effort vs your norm and how much sleep
    /// you typically bank, then mean-reverted. `results` is newest-first; the forecaster wants
    /// oldest→newest, so each series is reversed. `nil` (and the card hidden) until there are
    /// enough scored nights to anchor honestly — never a fabricated number.
    private var forecast: RecoveryForecast? {
        let charge = intelligence.results.compactMap { $0.recovery }.reversed()
        let effort = intelligence.results.compactMap { $0.strain }.reversed()
        // Planned sleep tonight = the recent typical night (the honest "if you sleep ~Xh"
        // assumption surfaced in the card), from the scored nights that have a sleep total.
        let sleeps = intelligence.results.compactMap { $0.sleepMin }
        let plannedHours = sleeps.isEmpty ? RecoveryForecaster.defaultNeedHours
            : (sleeps.reduce(0, +) / Double(sleeps.count)) / 60.0
        return RecoveryForecaster.forecast(recentCharge: Array(charge),
                                           recentEffort: Array(effort),
                                           todayEffort: intelligence.results.first?.strain,
                                           plannedSleepHours: plannedHours)
    }

    private func forecastCard(_ f: RecoveryForecast) -> some View {
        StrandCard(padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    HStack(spacing: 10) {
                        Image(systemName: "sunrise.fill").foregroundStyle(StrandPalette.accent)
                            .accessibilityHidden(true)
                        Text("Tomorrow's Charge").font(StrandFont.headline)
                            .foregroundStyle(StrandPalette.textPrimary)
                    }
                    Spacer()
                    SourceBadge("Estimate")
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(Int(f.charge.rounded()))").font(StrandFont.number(40))
                        .foregroundStyle(recoveryColor(f.charge))
                    Text("± \(Int(f.band.rounded()))").font(StrandFont.number(20))
                        .foregroundStyle(StrandPalette.textTertiary)
                    Spacer()
                }
                Text("You'll likely wake around \(Int(f.charge.rounded())) ± \(Int(f.band.rounded())) Charge if you sleep about \(sleepHoursLabel(f.plannedSleepHours)) tonight.")
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Estimate from today's effort, your typical sleep and your \(f.nights)-night recovery baseline — not a measurement. Your real Charge is scored from tomorrow's HRV when you wake.")
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// "~7h" / "~7h 30m" for the planned-sleep assumption (hours rounded to the nearest 30 min).
    private func sleepHoursLabel(_ hours: Double) -> String {
        let half = (hours * 2).rounded() / 2
        let h = Int(half)
        let m = Int((half - Double(h)) * 60)
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    private var explainerCard: some View {
        StrandCard(padding: 20) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "brain.head.profile").foregroundStyle(StrandPalette.accent)
                        .accessibilityHidden(true)
                    Text("How this works").font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                }
                Text("Charge weighs your HRV against your personal baseline (~55%), resting heart rate (~20%), rest quality (~15%), respiration (~5%) and skin-temperature deviation (~5%). Effort is a 0–\(UnitFormatter.effortScaleMax(effortScale)) cardiovascular load from time in heart-rate zones. Rest is staged from movement and heart rate. Everything is computed here from the strap's raw data — it works for any day NOOP collected raw streams.")
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func dayCard(_ d: IntelligenceEngine.Computed) -> some View {
        StrandCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(d.day).font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                    Spacer()
                    SourceBadge("NOOP-computed")
                }
                HStack(spacing: 0) {
                    stat("Charge", d.recovery.map { "\(Int($0.rounded()))%" } ?? "—", recoveryColor(d.recovery))
                    stat("Effort", d.strain.map { UnitFormatter.effortDisplay($0, scale: effortScale) } ?? "—", StrandPalette.metricCyan)
                    stat("Rest", d.sleepMin.map { "\(Int($0 / 60))h \(Int($0.truncatingRemainder(dividingBy: 60)))m" } ?? "—", StrandPalette.metricPurple)
                    stat("HRV", d.hrv.map { "\(Int($0.rounded()))" } ?? "—", StrandPalette.metricPurple)
                    stat("RHR", d.rhr.map { "\($0)" } ?? "—", StrandPalette.metricRose)
                }
            }
        }
    }

    private func stat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased()).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            Text(value).font(StrandFont.number(20)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recoveryColor(_ r: Double?) -> Color {
        guard let r else { return StrandPalette.textSecondary }
        if r >= 67 { return StrandPalette.statusPositive }
        if r >= 34 { return StrandPalette.statusWarning }
        return StrandPalette.statusCritical
    }
}

/// Recent-window options for the By Day list. `days == nil` means show everything.
private enum IntelRange: Int, CaseIterable, Hashable {
    case week = 7, month = 30, quarter = 90, half = 180, year = 365, all = 0

    /// Trailing days the window spans; `nil` for ALL.
    var days: Int? { self == .all ? nil : rawValue }

    var label: String {
        switch self {
        case .week: return "W"
        case .month: return "M"
        case .quarter: return "3M"
        case .half: return "6M"
        case .year: return "1Y"
        case .all: return "ALL"
        }
    }
}
