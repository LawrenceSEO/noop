package com.noop.location

import com.noop.analytics.RouteMath
import com.noop.analytics.RouteMath.LatLng
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Process-level holder for the in-flight GPS workout's route, owned by [com.noop.NoopApplication]
 * and driven by [com.noop.ble.WhoopConnectionService] — NOT by the Activity-scoped AppViewModel.
 *
 * Why this exists: the route used to be collected in `AppViewModel.viewModelScope`, which Android
 * cancels the moment the ViewModel is cleared (screen off / Activity backgrounded). The collection
 * stopped mid-ride and distance froze (#215 — a 2.84 km ride banked as 0.38 km). The track now lives
 * here, at the process level, and the always-on foreground service feeds it from the platform
 * LocationManager, so it survives the UI going away. The ViewModel observes [state] for live display
 * and reads the final [State.track] when ending the workout; it no longer owns the location stream.
 *
 * Distance/pace are derived here (off the same [RouteMath] helpers AppViewModel used) so the running
 * totals are correct even across periods when no UI is observing.
 */
object GpsSession {

    /** A GPS workout's accumulated route. [startMs] anchors pace; [active] gates the service collector.
     *  [sportName] lets the UI rehydrate the active-workout card if the ViewModel was cleared mid-ride. */
    data class State(
        val active: Boolean = false,
        val startMs: Long = 0L,
        val sportName: String = "",
        val track: List<LatLng> = emptyList(),
        val distanceM: Double = 0.0,
        val paceSecPerKm: Double? = null,
    )

    private val _state = MutableStateFlow(State())
    /** The live route, observed by the UI (via AppViewModel) and the service's collect-gate. */
    val state: StateFlow<State> = _state.asStateFlow()

    /** Begin a route for [sportName]'s workout started at [startMs]. A re-arm just resets the track. */
    fun start(startMs: Long, sportName: String) {
        _state.value = State(active = true, startMs = startMs, sportName = sportName)
    }

    /** Fold one accepted fix into the route, recomputing distance + pace. No-op when not active. */
    fun append(pt: LatLng) {
        val s = _state.value
        if (!s.active) return
        val track = s.track + pt
        val dist = RouteMath.totalMeters(track)
        val secs = (System.currentTimeMillis() - s.startMs) / 1000.0
        _state.value = s.copy(track = track, distanceM = dist, paceSecPerKm = RouteMath.paceSecPerKm(dist, secs))
    }

    /** End the route and clear it. Returns the final accumulated track for the saved WorkoutRow. */
    fun stop(): List<LatLng> {
        val track = _state.value.track
        _state.value = State()
        return track
    }
}
