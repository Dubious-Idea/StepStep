package com.purrweb.stepstep

import kotlin.math.max
import kotlin.math.min

/**
 * The bookkeeping behind [StepRepository]: folds a run of raw
 * `TYPE_STEP_COUNTER` readings into per-day step and active-time credits.
 *
 * Kept free of Android types on purpose. The cases that actually go wrong on
 * a phone — a reboot resetting the counter, a batch delivered after a fresher
 * reading, a batch straddling midnight — are covered by plain JVM tests in
 * `StepLedgerTest` instead of only ever being exercised on a device.
 */
object StepLedger {

    const val NO_RAW = -1L
    const val NO_TIME = -1L
    const val UNKNOWN_BOOT = -1

    /** ~7 hours of continuous fast walking; beyond this it is a bad read. */
    const val MAX_PLAUSIBLE_DELTA = 60_000L

    /**
     * Sensor timestamps older than this are treated as broken rather than
     * real: no FIFO holds two days of steps, but a device stamping events on
     * the wrong clock easily produces such ages.
     */
    const val MAX_EVENT_AGE_MS = 2 * 24 * 60 * 60 * 1000L

    private const val MILLIS_PER_MINUTE = 60_000L

    /** One sensor event: the cumulative counter and when that step really happened. */
    data class Reading(val raw: Long, val atMillis: Long)

    /** What the ledger carries between calls; persisted by [StepRepository]. */
    data class State(
        val lastRaw: Long = NO_RAW,
        val lastEventMillis: Long = NO_TIME,
        val bootCount: Int = UNKNOWN_BOOT,
        /** Active time already earned today but short of a whole minute. */
        val activeCarryMillis: Long = 0L,
        val activeCarryDay: String? = null,
    )

    data class Result(
        val state: State,
        /** Steps to add, per day key. */
        val steps: Map<String, Int>,
        /** Whole active minutes to add, per day key. */
        val activeMinutes: Map<String, Int>,
    )

    /**
     * Credits [readings] (oldest first) against [state].
     *
     * Each step lands on the day of its *own* timestamp, not the day it was
     * delivered on — a batch the sensor hub held overnight and handed over at
     * 07:00 still puts the 23:40 steps into yesterday.
     *
     * @param bootCount `Settings.Global.BOOT_COUNT` right now, or
     *   [UNKNOWN_BOOT] where the platform does not provide it.
     */
    fun apply(
        state: State,
        readings: List<Reading>,
        bootCount: Int,
        dayKey: (Long) -> String,
    ): Result {
        var lastRaw = state.lastRaw
        var lastEvent = state.lastEventMillis
        var carry = state.activeCarryMillis
        var carryDay = state.activeCarryDay
        // The counter restarts from zero on every boot. Unknown on either side
        // (first run after upgrading, a ROM without the setting) falls back to
        // the timestamp test below.
        var rebooted = bootCount != UNKNOWN_BOOT &&
            state.bootCount != UNKNOWN_BOOT &&
            bootCount != state.bootCount

        val steps = HashMap<String, Int>()
        val active = HashMap<String, Int>()

        for (reading in readings) {
            val delta = when {
                // First reading ever: no baseline, so claim nothing.
                lastRaw == NO_RAW -> 0L
                rebooted -> reading.raw
                reading.raw >= lastRaw -> reading.raw - lastRaw
                // Lower than what we already hold *and* older: a batched event
                // that arrived after a fresher reading. Its steps are already
                // inside the fresher one, so it changes nothing.
                lastEvent != NO_TIME && reading.atMillis < lastEvent -> continue
                // Lower but newer: the counter restarted without a reboot we
                // could see. Everything it has counted since is new to us.
                else -> reading.raw
            }
            rebooted = false

            val previousEvent = lastEvent
            lastRaw = reading.raw
            lastEvent = if (lastEvent == NO_TIME) reading.atMillis else max(lastEvent, reading.atMillis)

            if (delta <= 0 || delta > MAX_PLAUSIBLE_DELTA) continue

            val day = dayKey(reading.atMillis)
            steps[day] = (steps[day] ?: 0) + delta.toInt()

            // Walking time is what these steps would take at a plausible
            // cadence, capped by the time that actually passed since the
            // previous reading. With per-step events that cap is the real
            // gap between steps, so the sum is real time on the move; for one
            // big delta (a FIFO that overflowed) it degrades to the cadence
            // estimate instead of claiming the whole gap.
            val walkingMillis = (delta * MILLIS_PER_MINUTE / Metrics.FALLBACK_CADENCE_STEPS_PER_MIN).toLong()
            val elapsedMillis = if (previousEvent == NO_TIME) {
                walkingMillis
            } else {
                (reading.atMillis - previousEvent).coerceAtLeast(0L)
            }

            if (carryDay != day) {
                carry = 0L
                carryDay = day
            }
            carry += min(walkingMillis, elapsedMillis)
            val wholeMinutes = (carry / MILLIS_PER_MINUTE).toInt()
            if (wholeMinutes > 0) {
                active[day] = (active[day] ?: 0) + wholeMinutes
                carry -= wholeMinutes * MILLIS_PER_MINUTE
            }
        }

        return Result(
            state = State(
                lastRaw = lastRaw,
                lastEventMillis = lastEvent,
                bootCount = if (bootCount != UNKNOWN_BOOT) bootCount else state.bootCount,
                activeCarryMillis = carry,
                activeCarryDay = carryDay,
            ),
            steps = steps,
            activeMinutes = active,
        )
    }

    /**
     * Converts a `SensorEvent.timestamp` (nanoseconds on the
     * `elapsedRealtimeNanos` clock, marking when the step happened) to wall
     * time. A timestamp from the future or from days ago means this device
     * stamps events on some other clock, so the delivery time is the safer
     * guess.
     */
    fun eventWallMillis(timestampNanos: Long, nowMillis: Long, elapsedRealtimeNanos: Long): Long {
        val ageMillis = (elapsedRealtimeNanos - timestampNanos) / 1_000_000L
        return if (ageMillis < 0 || ageMillis > MAX_EVENT_AGE_MS) nowMillis else nowMillis - ageMillis
    }
}
