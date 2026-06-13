package com.noop.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.noop.analytics.RecoveryForecast
import com.noop.analytics.RecoveryForecaster
import com.noop.data.DailyMetric
import java.time.LocalDate
import java.util.Calendar
import kotlin.math.roundToInt

/**
 * Intelligence — NOOP's own Charge / Effort / Rest scores, presented with the
 * WHOOP-model explanation so the read-out is legible rather than a black box.
 *
 * Ports macOS Strand/Screens/IntelligenceView.swift. The macOS build runs an
 * on-device IntelligenceEngine that recomputes these scores from the strap's raw
 * streams (HR, R-R, accelerometer) using the WHOOP model shape. That raw-compute
 * port is later work on Android; until it lands this screen reads the cached
 * `DailyMetric` values the strap/store already provide and shows the same model
 * explainer + per-day breakdown — matching the macOS sparse-data contract of
 * surfacing real data with an honest note, never a fabricated score.
 */
@Composable
fun IntelligenceScreen(vm: AppViewModel) {
    val days by vm.recentDays.collectAsStateWithLifecycle()
    val live by vm.live.collectAsStateWithLifecycle()

    // Effort display scale (#268) — routes every Effort value/label on this screen. Display-only.
    val effortScale = UnitPrefs.effortScale(LocalContext.current)

    // Newest first for the per-day list (macOS ForEach renders most-recent at top).
    val ordered = remember(days) { days.reversed() }

    // Evening forecast of tomorrow-morning Charge from tonight's known levers. `days` is
    // already OLDEST→NEWEST (what the forecaster wants); today's Effort is the newest day.
    // null (and the card hidden) until there are enough scored nights to anchor honestly.
    val forecast = remember(days) {
        val charge = days.mapNotNull { it.recovery }
        val effort = days.mapNotNull { it.strain }
        val sleeps = days.mapNotNull { it.totalSleepMin }
        val plannedHours = if (sleeps.isEmpty()) RecoveryForecaster.defaultNeedHours
            else (sleeps.sum() / sleeps.size) / 60.0
        RecoveryForecaster.forecast(
            recentCharge = charge,
            recentEffort = effort,
            todayEffort = ordered.firstOrNull()?.strain,
            plannedSleepHours = plannedHours,
        )
    }

    ScreenScaffold(
        title = "Intelligence",
        subtitle = "Charge, effort and rest — scored with the model, explained in plain terms.",
    ) {
        forecast?.let { ForecastCard(it) }
        ExplainerCard(effortScale)
        ModelBreakdownCard(effortScale)

        if (ordered.isEmpty()) {
            // While the strap is mid-offload, say so — an empty list reads as final otherwise (#77).
            if (live.backfilling) SyncingHistoryNote(chunks = live.syncChunksThisSession)
            EmptyNote()
        } else {
            var range by remember { mutableStateOf(IntelRange.Month) }
            val filtered = remember(ordered, range) {
                val n = range.days ?: return@remember ordered
                val cutoff = LocalDate.now().minusDays((n - 1).toLong()).toString()
                ordered.filter { it.day >= cutoff }
            }

            // Header row: section label left, range control right. Lets you narrow the
            // per-day list to a recent window (lexicographic YYYY-MM-DD compare == chronological).
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(Metrics.gap),
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Overline("Recent")
                    Text("By Day", style = NoopType.title2, color = Palette.textPrimary)
                }
                SegmentedPillControl(
                    items = IntelRange.entries.toList(),
                    selection = range,
                    label = { it.label },
                    onSelect = { range = it },
                )
            }
            Text(
                "${filtered.size} ${if (filtered.size == 1) "day" else "days"}",
                style = NoopType.footnote,
                color = Palette.textTertiary,
            )

            if (filtered.isEmpty()) {
                NoopCard(padding = 18.dp) {
                    Text(
                        "No scored days in this window. Widen the range or import more history.",
                        style = NoopType.subhead,
                        color = Palette.textSecondary,
                    )
                }
            } else {
                filtered.forEach { day -> DayCard(day, effortScale) }
            }
        }
    }
}

// MARK: - Tomorrow's Charge forecast (ported from IntelligenceView.forecastCard)
//
// An evening ESTIMATE of tomorrow-morning Charge from tonight's known levers —
// today's Effort vs your norm, your typical sleep, and the recent recovery baseline.
// Labelled an estimate with a ± band; the real Charge is scored from tomorrow's HRV.

@Composable
private fun ForecastCard(f: RecoveryForecast) {
    val charge = f.charge.roundToInt()
    val band = f.band.roundToInt()
    NoopCard(padding = 20.dp) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.weight(1f),
                ) {
                    Icon(
                        Icons.Filled.WbSunny,
                        contentDescription = null,
                        tint = Palette.accent,
                        modifier = Modifier.size(20.dp),
                    )
                    Text("Tomorrow's Charge", style = NoopType.headline, color = Palette.textPrimary)
                }
                SourceBadge("Estimate")
            }
            Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("$charge", style = NoopType.number(40f), color = recoveryStatColor(f.charge))
                Text("± $band", style = NoopType.number(20f), color = Palette.textTertiary)
            }
            Text(
                "You'll likely wake around $charge ± $band Charge if you sleep about " +
                    "${sleepHoursLabel(f.plannedSleepHours)} tonight.",
                style = NoopType.subhead,
                color = Palette.textSecondary,
            )
            Text(
                "Estimate from today's effort, your typical sleep and your ${f.nights}-night " +
                    "recovery baseline — not a measurement. Your real Charge is scored from " +
                    "tomorrow's HRV when you wake.",
                style = NoopType.footnote,
                color = Palette.textTertiary,
            )
        }
    }
}

/** "~7h" / "~7h 30m" for the planned-sleep assumption (rounded to the nearest 30 min). */
private fun sleepHoursLabel(hours: Double): String {
    val half = (hours * 2).roundToInt() / 2.0
    val h = half.toInt()
    val m = ((half - h) * 60).roundToInt()
    return if (m == 0) "${h}h" else "${h}h ${m}m"
}

// MARK: - Explainer (ported from IntelligenceView.explainerCard)

@Composable
private fun ExplainerCard(effortScale: EffortScale) {
    NoopCard(padding = 20.dp) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    Icons.Filled.AutoAwesome,
                    contentDescription = null,
                    tint = Palette.accent,
                    modifier = Modifier.size(20.dp),
                )
                Text("How this works", style = NoopType.headline, color = Palette.textPrimary)
            }
            Text(
                "Charge weighs your heart-rate variability against your personal baseline " +
                    "(~55%), resting heart rate (~20%), rest quality (~15%), respiration (~5%) " +
                    "and skin-temperature deviation (~5%). Effort is a 0–${UnitFormatter.effortScaleMax(effortScale)} " +
                    "cardiovascular load from time spent in each heart-rate zone. Rest is staged " +
                    "from movement and heart rate. The full on-device recompute from the strap's raw " +
                    "streams is a later port; the scores below are read from each day's cached metrics.",
                style = NoopType.subhead,
                color = Palette.textSecondary,
            )
        }
    }
}

// MARK: - Empty note

@Composable
private fun EmptyNote() {
    NoopCard(padding = 20.dp) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.Top,
        ) {
            Icon(
                Icons.Filled.AutoAwesome,
                contentDescription = null,
                tint = Palette.accent,
                modifier = Modifier.size(18.dp),
            )
            Text(
                "No scored days yet. Sync your strap to collect raw streams — charge, " +
                    "effort and rest are scored once a day's data is in.",
                style = NoopType.subhead,
                color = Palette.textSecondary,
            )
        }
    }
}

// MARK: - Model weighting breakdown
//
// Makes the Charge formula concrete: the five weighted inputs plus the 0–100
// Effort scale. Pure presentation of the model the macOS engine uses — no per-day
// data, so it's always legible even before any day is scored.

@Composable
private fun ModelBreakdownCard(effortScale: EffortScale) {
    NoopCard(padding = 20.dp) {
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Overline("Charge model")
            WeightRow("Heart-rate variability", "~55%", 0.55f, Palette.metricPurple)
            WeightRow("Resting heart rate", "~20%", 0.20f, Palette.metricRose)
            WeightRow("Rest quality", "~15%", 0.15f, Palette.metricCyan)
            WeightRow("Respiration", "~5%", 0.05f, Palette.accent)
            WeightRow("Skin-temperature deviation", "~5%", 0.05f, Palette.metricAmber)

            Row(
                modifier = Modifier.fillMaxWidth().padding(top = 2.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    "Effort",
                    style = NoopType.subhead,
                    color = Palette.textSecondary,
                    modifier = Modifier.weight(1f),
                )
                Text(
                    "0–${UnitFormatter.effortScaleMax(effortScale)} scale",
                    style = NoopType.captionNumber,
                    color = Palette.metricCyan,
                )
            }
        }
    }
}

@Composable
private fun WeightRow(label: String, percent: String, fraction: Float, color: Color) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                label,
                style = NoopType.subhead,
                color = Palette.textPrimary,
                modifier = Modifier.weight(1f),
            )
            Text(percent, style = NoopType.captionNumber, color = color)
        }
        Meter(fraction = fraction, color = color)
    }
}

/** A thin, rounded proportional meter on the inset well. */
@Composable
private fun Meter(fraction: Float, color: Color) {
    val shape = RoundedCornerShape(50)
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(6.dp)
            .clip(shape)
            .background(Palette.surfaceInset),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth(fraction.coerceIn(0f, 1f))
                .height(6.dp)
                .clip(shape)
                .background(color),
        )
    }
}

// MARK: - Per-day card (ported from IntelligenceView.dayCard)
//
// Header = the day + a NOOP-computed source badge; a row of the five headline
// scores (Charge / Effort / Rest / HRV / RHR) tinted to the design-system metric
// colors, then a thin Effort meter for at-a-glance load.

@Composable
private fun DayCard(d: DailyMetric, effortScale: EffortScale) {
    NoopCard(padding = 18.dp) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    prettyDay(d.day),
                    style = NoopType.headline,
                    color = Palette.textPrimary,
                    modifier = Modifier.weight(1f),
                )
                SourceBadge("NOOP-computed")
            }

            Row(modifier = Modifier.fillMaxWidth()) {
                DayStat(
                    "Charge",
                    d.recovery?.let { "${it.roundToInt()}%" } ?: "—",
                    d.recovery?.let { recoveryStatColor(it) } ?: Palette.textSecondary,
                    Modifier.weight(1f),
                )
                DayStat(
                    "Effort",
                    d.strain?.let { UnitFormatter.effortDisplay(it, effortScale) } ?: "—",
                    Palette.metricCyan,
                    Modifier.weight(1f),
                )
                DayStat(
                    "Rest",
                    sleepValue(d.totalSleepMin),
                    Palette.metricPurple,
                    Modifier.weight(1f),
                )
                DayStat(
                    "HRV",
                    d.avgHrv?.let { "${it.roundToInt()}" } ?: "—",
                    Palette.metricPurple,
                    Modifier.weight(1f),
                )
                DayStat(
                    "RHR",
                    d.restingHr?.toString() ?: "—",
                    Palette.metricRose,
                    Modifier.weight(1f),
                )
            }

            // Effort load meter (0–100), tinted along the strain ramp.
            d.strain?.let { s ->
                Meter(
                    fraction = (s / 100.0).toFloat(),
                    color = Palette.strainColor(s),
                )
            }
        }
    }
}

@Composable
private fun DayStat(label: String, value: String, color: Color, modifier: Modifier = Modifier) {
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Text(
            label.uppercase(),
            style = NoopType.footnote,
            color = Palette.textTertiary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        Text(
            value,
            style = NoopType.number(19f),
            color = color,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

// MARK: - Derived helpers

/** Recovery-band status color, mirroring IntelligenceView.recoveryColor (67 / 34 cuts). */
private fun recoveryStatColor(r: Double): Color = when {
    r >= 67 -> Palette.statusPositive
    r >= 34 -> Palette.statusWarning
    else -> Palette.statusCritical
}

private fun sleepValue(totalMin: Double?): String {
    val m = totalMin ?: return "—"
    val total = m.roundToInt()
    return "${total / 60}h ${total % 60}m"
}

/** Recent-window options for the By Day list. `days == null` means show everything. */
private enum class IntelRange(val days: Int?, val label: String) {
    Week(7, "W"), Month(30, "M"), Quarter(90, "3M"),
    Half(180, "6M"), Year(365, "1Y"), All(null, "ALL"),
}

/** "YYYY-MM-DD" → "Mon 5 Jun"; falls back to the raw key if it doesn't parse. */
private fun prettyDay(day: String): String {
    return try {
        val parts = day.split("-")
        val y = parts[0].toInt()
        val mo = parts[1].toInt()
        val da = parts[2].toInt()
        val cal = Calendar.getInstance().apply { set(y, mo - 1, da) }
        val dow = arrayOf("Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat")[
            cal.get(Calendar.DAY_OF_WEEK) - 1,
        ]
        val month = arrayOf(
            "Jan", "Feb", "Mar", "Apr", "May", "Jun",
            "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
        )[mo - 1]
        "$dow $da $month"
    } catch (_: Exception) {
        day
    }
}
