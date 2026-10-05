package com.purrweb.stepstep

import com.purrweb.stepstep.StepLedger.Reading
import com.purrweb.stepstep.StepLedger.State
import java.time.Instant
import java.time.ZoneOffset
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class StepLedgerTest {

    private val dayKey: (Long) -> String = {
        Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate().toString()
    }

    private fun at(iso: String): Long = Instant.parse(iso).toEpochMilli()

    private fun apply(state: State, vararg readings: Reading, boot: Int = 1) =
        StepLedger.apply(state, readings.toList(), boot, dayKey)

    private val evening = at("2026-10-05T20:00:00Z")

    @Test
    fun `first reading only sets the baseline`() {
        val result = apply(State(), Reading(raw = 12_345, atMillis = evening))

        assertTrue(result.steps.isEmpty())
        assertEquals(12_345L, result.state.lastRaw)
        assertEquals(evening, result.state.lastEventMillis)
    }

    @Test
    fun `delta lands on the day the step happened`() {
        val state = State(lastRaw = 1_000, lastEventMillis = evening, bootCount = 1)

        val result = apply(state, Reading(raw = 1_250, atMillis = evening + 60_000))

        assertEquals(mapOf("2026-10-05" to 250), result.steps)
    }

    @Test
    fun `batch delivered after midnight is split by event time`() {
        // The hub held these overnight and handed them over together.
        val state = State(lastRaw = 100, lastEventMillis = at("2026-10-05T23:40:00Z"), bootCount = 1)

        val result = apply(
            state,
            Reading(raw = 150, atMillis = at("2026-10-05T23:50:00Z")),
            Reading(raw = 200, atMillis = at("2026-10-06T00:10:00Z")),
        )

        assertEquals(mapOf("2026-10-05" to 50, "2026-10-06" to 50), result.steps)
    }

    @Test
    fun `changed boot count means the counter restarted from zero`() {
        val state = State(lastRaw = 5_000, lastEventMillis = evening, bootCount = 5)

        val result = apply(state, Reading(raw = 300, atMillis = evening + 60_000), boot = 6)

        assertEquals(mapOf("2026-10-05" to 300), result.steps)
        assertEquals(6, result.state.bootCount)
    }

    @Test
    fun `reboot is credited once, later readings are plain deltas`() {
        val state = State(lastRaw = 5_000, lastEventMillis = evening, bootCount = 5)

        val result = apply(
            state,
            Reading(raw = 300, atMillis = evening + 60_000),
            Reading(raw = 340, atMillis = evening + 120_000),
            boot = 6,
        )

        assertEquals(mapOf("2026-10-05" to 340), result.steps)
    }

    @Test
    fun `older lower reading arriving late is ignored, not taken for a reboot`() {
        // The app read 1 000 directly; the service's batch then delivers an
        // older 900 that is already inside it.
        val state = State(lastRaw = 1_000, lastEventMillis = evening, bootCount = 1)

        val result = apply(
            state,
            Reading(raw = 900, atMillis = evening - 60_000),
            Reading(raw = 1_100, atMillis = evening + 60_000),
        )

        assertEquals(mapOf("2026-10-05" to 100), result.steps)
        assertEquals(1_100L, result.state.lastRaw)
    }

    @Test
    fun `newer lower reading is a counter reset even without a boot count`() {
        val state = State(lastRaw = 1_000, lastEventMillis = evening)

        val result = apply(
            state,
            Reading(raw = 20, atMillis = evening + 60_000),
            boot = StepLedger.UNKNOWN_BOOT,
        )

        assertEquals(mapOf("2026-10-05" to 20), result.steps)
    }

    @Test
    fun `implausible jump is dropped but becomes the new baseline`() {
        val state = State(lastRaw = 1_000, lastEventMillis = evening, bootCount = 1)

        val result = apply(
            state,
            Reading(raw = 1_000 + StepLedger.MAX_PLAUSIBLE_DELTA + 1, atMillis = evening + 60_000),
        )

        assertTrue(result.steps.isEmpty())
        assertEquals(1_000 + StepLedger.MAX_PLAUSIBLE_DELTA + 1, result.state.lastRaw)
    }

    @Test
    fun `per-step events add up to real time on the move`() {
        // 200 steps, one event each, 0.6 s apart: two minutes of walking.
        val readings = (1..200).map { Reading(raw = it.toLong(), atMillis = evening + it * 600L) }
        val state = State(lastRaw = 0, lastEventMillis = evening, bootCount = 1)

        val result = StepLedger.apply(state, readings, 1, dayKey)

        assertEquals(mapOf("2026-10-05" to 200), result.steps)
        assertEquals(mapOf("2026-10-05" to 2), result.activeMinutes)
        assertEquals(0L, result.state.activeCarryMillis)
    }

    @Test
    fun `one big delta after a long gap falls back to the cadence estimate`() {
        val state = State(lastRaw = 0, lastEventMillis = evening, bootCount = 1)

        val result = apply(state, Reading(raw = 1_000, atMillis = evening + 3 * 3_600_000L))

        // 1 000 steps at 100 steps/min, not the three hours that passed.
        assertEquals(mapOf("2026-10-05" to 10), result.activeMinutes)
    }

    @Test
    fun `a few stray steps do not add whole minutes`() {
        val state = State(lastRaw = 0, lastEventMillis = evening, bootCount = 1)

        val result = apply(
            state,
            Reading(raw = 1, atMillis = evening + 60_000),
            Reading(raw = 2, atMillis = evening + 120_000),
            Reading(raw = 3, atMillis = evening + 180_000),
        )

        assertTrue(result.activeMinutes.isEmpty())
        assertEquals(1_800L, result.state.activeCarryMillis)
    }

    @Test
    fun `active carry does not leak into the next day`() {
        val state = State(
            lastRaw = 0,
            lastEventMillis = at("2026-10-05T23:59:00Z"),
            bootCount = 1,
            activeCarryMillis = 59_000,
            activeCarryDay = "2026-10-05",
        )

        val result = apply(state, Reading(raw = 1, atMillis = at("2026-10-06T00:01:00Z")))

        assertTrue(result.activeMinutes.isEmpty())
        assertEquals("2026-10-06", result.state.activeCarryDay)
        assertEquals(600L, result.state.activeCarryMillis)
    }

    @Test
    fun `event time comes from the sensor timestamp`() {
        val now = evening
        val elapsedNanos = 1_000_000_000_000L
        val twoMinutesAgo = elapsedNanos - 120_000_000_000L

        assertEquals(now - 120_000, StepLedger.eventWallMillis(twoMinutesAgo, now, elapsedNanos))
    }

    @Test
    fun `implausible sensor timestamps fall back to the delivery time`() {
        val now = evening
        val elapsedNanos = 1_000_000_000_000L

        val fromTheFuture = elapsedNanos + 5_000_000_000L
        val daysOld = elapsedNanos - (StepLedger.MAX_EVENT_AGE_MS + 1) * 1_000_000L

        assertEquals(now, StepLedger.eventWallMillis(fromTheFuture, now, elapsedNanos))
        assertEquals(now, StepLedger.eventWallMillis(daysOld, now, elapsedNanos))
    }
}
