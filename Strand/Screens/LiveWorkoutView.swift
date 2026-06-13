import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// Live workout mode (#238) — the in-exercise screen: a big live heart rate, the current HR zone,
/// elapsed time, and live effort building, all from the SAME live feed and scorers the rest of the
/// app uses (no invented numbers). Presented while a manual workout is active, entered from the
/// Start-workout control on Live. End stops the workout and dismisses.
///
/// Live HR is the smoothed `AppModel.bpm`; the zone is derived from the user's HR-max via the shared
/// `HRZones` model; elapsed time ticks from the workout's start (a TimelineView, no manual Timer);
/// effort is the running `ActiveWorkout.liveStrain` (StrainScorer over the captured window).
struct LiveWorkoutView: View {
    @EnvironmentObject private var model: AppModel
    let onClose: () -> Void

    /// Effort display scale (#268) — routes the live Effort read-out through the shared helper so it
    /// matches every other surface. Display-only; the captured value stays stored 0–100.
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    private var effortScale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }

    private var zoneSet: HRZoneSet { HRZones.zones(maxHR: Double(model.profile.hrMax)) }
    private var zone: Int { model.bpm.map { zoneSet.zoneNumber(forBPM: Double($0)) } ?? 0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                heroHeartRate
                zoneRail
                statsGrid
                Spacer(minLength: 12)
                endButton
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(StrandPalette.surfaceBase.ignoresSafeArea())
        // If the workout ended elsewhere (process restart cleared it), close the screen.
        .onChange(of: model.activeWorkout == nil) { gone in if gone { onClose() } }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("RECORDING WORKOUT")
                    .font(StrandFont.overline).tracking(StrandFont.overlineTracking)
                    .foregroundStyle(StrandPalette.metricRose)
                Text("Workout")
                    .font(StrandFont.title1).foregroundStyle(StrandPalette.textPrimary)
            }
            Spacer()
            if let start = model.activeWorkout?.start {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(Self.elapsed(since: start))
                        .font(StrandFont.number(34)).monospacedDigit()
                        .foregroundStyle(StrandPalette.textPrimary)
                }
            }
        }
    }

    private var heroHeartRate: some View {
        let tint = zone >= 1 ? StrandPalette.hrZoneColor(zone) : StrandPalette.textSecondary
        return NoopCard(padding: 24) {
            VStack(spacing: 6) {
                Text("HEART RATE")
                    .font(StrandFont.overline).tracking(StrandFont.overlineTracking)
                    .foregroundStyle(StrandPalette.textSecondary)
                Text(model.bpm.map { "\($0)" } ?? "—")
                    .font(StrandFont.number(80)).monospacedDigit()
                    .foregroundStyle(tint)
                Text("bpm").font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                Text(zone >= 1 ? "Zone \(zone) · \(Self.zoneName(zone))" : "Below Zone 1")
                    .font(StrandFont.captionNumber)
                    .foregroundStyle(tint)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var zoneRail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HR ZONE")
                .font(StrandFont.overline).tracking(StrandFont.overlineTracking)
                .foregroundStyle(StrandPalette.textSecondary)
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { z in
                    let active = z == zone
                    let color = StrandPalette.hrZoneColor(z)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(active ? color : color.opacity(0.18))
                        .frame(height: active ? 44 : 34)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(active ? color : StrandPalette.hairline, lineWidth: 1)
                        )
                        .overlay(
                            Text("Z\(z)")
                                .font(StrandFont.captionNumber)
                                .foregroundStyle(active ? StrandPalette.surfaceBase : StrandPalette.textTertiary)
                        )
                }
            }
            if let band = zoneSet.zones.first(where: { $0.number == zone }) {
                Text("Zone \(zone): \(Int(band.lower))–\(Int(band.upper)) bpm (\(Int(band.lowerPct * 100))–\(Int(band.upperPct * 100))% max HR)")
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            } else {
                Text("Warming up — keep moving to climb into Zone 1.")
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            }
        }
    }

    private var statsGrid: some View {
        let w = model.activeWorkout
        return HStack(spacing: NoopMetrics.gap) {
            stat("AVG", (w?.avgHr ?? 0) > 0 ? "\(w!.avgHr)" : "—")
            stat("PEAK", (w?.peakHr ?? 0) > 0 ? "\(w!.peakHr)" : "—")
            stat("EFFORT", UnitFormatter.effortDisplay(w?.liveStrain ?? 0, scale: effortScale))
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        NoopCard(padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(StrandFont.overline).tracking(StrandFont.overlineTracking)
                    .foregroundStyle(StrandPalette.textSecondary)
                Text(value)
                    .font(StrandFont.number(26)).monospacedDigit()
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var endButton: some View {
        Button(role: .destructive) {
            model.endWorkout()
            onClose()
        } label: {
            Text("End workout")
                .font(StrandFont.headline)
                .frame(maxWidth: .infinity).padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .tint(StrandPalette.statusCritical)
    }

    // MARK: - Helpers

    private static func elapsed(since start: Date) -> String {
        let s = max(0, Int(Date().timeIntervalSince(start)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private static func zoneName(_ zone: Int) -> String {
        switch zone {
        case 1: return "Recovery"
        case 2: return "Fat burn"
        case 3: return "Aerobic"
        case 4: return "Threshold"
        case 5: return "Maximum"
        default: return ""
        }
    }
}
