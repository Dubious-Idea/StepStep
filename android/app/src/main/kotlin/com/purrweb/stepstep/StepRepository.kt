package com.purrweb.stepstep

import android.content.Context
import android.content.SharedPreferences
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlin.math.ceil

/**
 * Single source of truth for step data.
 *
 * The hardware `TYPE_STEP_COUNTER` reports steps since boot and keeps counting
 * while the app is dead, so the repository never tries to count anything
 * itself — it converts the raw counter into per-day totals by accumulating
 * deltas, which survives both reboots (counter resets to 0) and long periods
 * with no listener registered (one large delta arrives at the next reading).
 *
 * Flutter reads through [MainActivity]'s method channel rather than keeping a
 * second copy, so the widget, the notification and the UI can never disagree.
 */
class StepRepository(context: Context) {

    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    // ---------------------------------------------------------------- profile

    var heightCm: Int
        get() = prefs.getInt(KEY_HEIGHT, DEFAULT_HEIGHT_CM)
        set(value) = prefs.edit().putInt(KEY_HEIGHT, value.coerceIn(100, 250)).apply()

    var weightKg: Double
        get() = prefs.getFloat(KEY_WEIGHT, DEFAULT_WEIGHT_KG.toFloat()).toDouble()
        set(value) = prefs.edit()
            .putFloat(KEY_WEIGHT, value.coerceIn(30.0, 300.0).toFloat()).apply()

    var goal: Int
        get() = prefs.getInt(KEY_GOAL, DEFAULT_GOAL)
        set(value) = prefs.edit().putInt(KEY_GOAL, value.coerceIn(1000, 50000)).apply()

    /** True once onboarding has written real measurements. */
    var isOnboarded: Boolean
        get() = prefs.getBoolean(KEY_ONBOARDED, false)
        set(value) = prefs.edit().putBoolean(KEY_ONBOARDED, value).apply()

    /**
     * Release the user chose to skip, so the update prompt stays dismissed
     * across launches instead of reappearing every time the app opens.
     */
    var skippedUpdateVersion: String?
        get() = prefs.getString(KEY_SKIPPED_VERSION, null)
        set(value) = prefs.edit().putString(KEY_SKIPPED_VERSION, value).apply()

    /** Whether the ongoing lock-screen notification should be running. */
    var isLiveNotificationEnabled: Boolean
        get() = prefs.getBoolean(KEY_LIVE_NOTIFICATION, true)
        set(value) = prefs.edit().putBoolean(KEY_LIVE_NOTIFICATION, value).apply()

    // ------------------------------------------------------------ today state

    val todayKey: String get() = dayKey(System.currentTimeMillis())

    fun stepsOn(dayKey: String): Int = prefs.getInt(stepsKey(dayKey), 0)

    fun activeMinutesOn(dayKey: String): Int = prefs.getInt(activeKey(dayKey), 0)

    val todaySteps: Int get() = stepsOn(todayKey)

    val todayActiveMinutes: Int get() = activeMinutesOn(todayKey)

    /**
     * Folds a raw `TYPE_STEP_COUNTER` reading into today's total.
     *
     * @return the new total for today.
     */
    @Synchronized
    fun recordRawCounter(raw: Long, nowMillis: Long = System.currentTimeMillis()): Int {
        val lastRaw = prefs.getLong(KEY_LAST_RAW, NO_RAW)

        val delta = when {
            // First reading ever: we have no baseline, so claim nothing.
            lastRaw == NO_RAW -> 0L
            // Counter went backwards => the device rebooted and restarted from
            // zero. Everything it has counted since then is new to us.
            raw < lastRaw -> raw
            else -> raw - lastRaw
        }

        prefs.edit().putLong(KEY_LAST_RAW, raw).apply()

        // A jump this large is a corrupt reading, not a person walking.
        if (delta <= 0 || delta > MAX_PLAUSIBLE_DELTA) return todaySteps

        return addSteps(delta.toInt(), nowMillis)
    }

    @Synchronized
    fun addSteps(delta: Int, nowMillis: Long): Int {
        if (delta <= 0) return todaySteps

        val day = dayKey(nowMillis)
        val newTotal = prefs.getInt(stepsKey(day), 0) + delta

        val editor = prefs.edit().putInt(stepsKey(day), newTotal)
        creditActiveMinutes(editor, day, delta, nowMillis)
        editor.apply()

        if (prefs.getString(KEY_CURRENT_DAY, null) != day) {
            prefs.edit().putString(KEY_CURRENT_DAY, day).apply()
            pruneHistory(nowMillis)
        }
        return newTotal
    }

    /**
     * Turns a step total into walking *time*, which the calorie model needs
     * — see [Metrics.activeKcal].
     *
     * `TYPE_STEP_COUNTER` events are batched by the OS and can arrive minutes
     * apart, each carrying every step taken since the last one. Crediting a
     * flat one minute per callback (the previous behaviour) badly undercounts
     * a burst delivered after the app sat quiet for a while, and just as
     * badly overcounts a trickle of noise events spread one-per-minute.
     * Instead this estimates how many of the minutes since the last reading
     * were actually spent walking, from the step delta at a plausible
     * cadence, then caps that estimate by how much wall-clock time really
     * passed — so a reading can never claim more active time than elapsed,
     * regardless of how sparsely events arrive. That cap is what makes this
     * safe to run purely off whatever events the sensor happens to deliver,
     * without needing a service kept alive to poll more often.
     */
    private fun creditActiveMinutes(
        editor: SharedPreferences.Editor,
        day: String,
        delta: Int,
        nowMillis: Long,
    ) {
        val minuteStamp = nowMillis / 60_000L
        val lastEventMillis = prefs.getLong(KEY_LAST_EVENT_MILLIS, -1L)
        val lastCreditedMinute = prefs.getLong(KEY_LAST_ACTIVE_MINUTE, -1L)

        val estimatedMinutes = ceil(delta / Metrics.FALLBACK_CADENCE_STEPS_PER_MIN)
            .toLong()
            .coerceAtLeast(1L)
        val elapsedMinutes = if (lastEventMillis < 0) {
            1L
        } else {
            ((nowMillis - lastEventMillis) / 60_000L).coerceAtLeast(1L)
        }
        val minutesToCredit = minOf(estimatedMinutes, elapsedMinutes)

        // Minutes already credited by a previous call must not be counted
        // again, so the credited range starts right after them.
        val rangeStart = minuteStamp - minutesToCredit + 1
        val creditFrom = maxOf(rangeStart, lastCreditedMinute + 1)

        if (creditFrom <= minuteStamp) {
            val newlyCredited = (minuteStamp - creditFrom + 1).toInt()
            editor.putInt(activeKey(day), prefs.getInt(activeKey(day), 0) + newlyCredited)
        }

        editor.putLong(KEY_LAST_ACTIVE_MINUTE, minuteStamp)
        editor.putLong(KEY_LAST_EVENT_MILLIS, nowMillis)
    }

    // --------------------------------------------------------------- history

    /** Steps for the last [days] days, oldest first, ending with today. */
    fun history(days: Int, nowMillis: Long = System.currentTimeMillis()): List<DayEntry> {
        val calendar = midnightCalendar(nowMillis)
        calendar.add(Calendar.DAY_OF_YEAR, -(days - 1))

        return (0 until days).map {
            val key = dayKey(calendar.timeInMillis)
            val entry = DayEntry(
                dayKey = key,
                steps = stepsOn(key),
                activeMinutes = activeMinutesOn(key),
                weekday = calendar.get(Calendar.DAY_OF_WEEK),
            )
            calendar.add(Calendar.DAY_OF_YEAR, 1)
            entry
        }
    }

    /**
     * Steps for every day from [startDayKey] to [endDayKey], inclusive,
     * oldest first — unlike [history], not anchored to today. Backs the
     * month/year browser, which needs arbitrary ranges rather than "the last
     * N days". Days outside the retained [HISTORY_DAYS] window read back as
     * zero rather than failing, so a gap shows as an honest empty day.
     */
    fun historyRange(startDayKey: String, endDayKey: String): List<DayEntry> {
        val calendar = Calendar.getInstance().apply { time = formatter().parse(startDayKey)!! }
        val end = formatter().parse(endDayKey)!!

        val entries = mutableListOf<DayEntry>()
        while (!calendar.time.after(end)) {
            val key = dayKey(calendar.timeInMillis)
            entries += DayEntry(
                dayKey = key,
                steps = stepsOn(key),
                activeMinutes = activeMinutesOn(key),
                weekday = calendar.get(Calendar.DAY_OF_WEEK),
            )
            calendar.add(Calendar.DAY_OF_YEAR, 1)
        }
        return entries
    }

    /** Drops day records older than [HISTORY_DAYS] so prefs cannot grow forever. */
    private fun pruneHistory(nowMillis: Long) {
        val keep = history(HISTORY_DAYS, nowMillis).map { it.dayKey }.toSet()
        val editor = prefs.edit()
        var removed = false

        prefs.all.keys
            .filter { it.startsWith(PREFIX_STEPS) || it.startsWith(PREFIX_ACTIVE) }
            .forEach { key ->
                val day = key.substringAfter('_')
                if (day !in keep) {
                    editor.remove(key)
                    removed = true
                }
            }

        if (removed) editor.apply()
    }

    // -------------------------------------------------------------- snapshot

    /** Everything the widget, the notification and Flutter need in one read. */
    fun snapshot(): Snapshot {
        val steps = todaySteps
        val activeMinutes = todayActiveMinutes
        val height = heightCm
        val weight = weightKg

        return Snapshot(
            steps = steps,
            goal = goal,
            activeMinutes = activeMinutes,
            heightCm = height,
            weightKg = weight,
            distanceKm = Metrics.distanceKm(steps, height),
            kcal = Metrics.activeKcal(steps, height, weight, activeMinutes.toDouble()),
        )
    }

    data class Snapshot(
        val steps: Int,
        val goal: Int,
        val activeMinutes: Int,
        val heightCm: Int,
        val weightKg: Double,
        val distanceKm: Double,
        val kcal: Double,
    ) {
        val progress: Float get() = Metrics.goalProgress(steps, goal)

        fun toMap(): Map<String, Any> = mapOf(
            "steps" to steps,
            "goal" to goal,
            "activeMinutes" to activeMinutes,
            "heightCm" to heightCm,
            "weightKg" to weightKg,
            "distanceKm" to distanceKm,
            "kcal" to kcal,
        )
    }

    data class DayEntry(
        val dayKey: String,
        val steps: Int,
        val activeMinutes: Int,
        val weekday: Int,
    ) {
        fun toMap(): Map<String, Any> = mapOf(
            "dayKey" to dayKey,
            "steps" to steps,
            "activeMinutes" to activeMinutes,
            "weekday" to weekday,
        )
    }

    companion object {
        const val PREFS_NAME = "stepstep_data"

        /** ~13 months: enough for the year browser to cover "this month last
         * year" even right after the year rolls over. */
        const val HISTORY_DAYS = 400

        private const val NO_RAW = -1L

        /** ~7 hours of continuous fast walking; beyond this it is a bad read. */
        private const val MAX_PLAUSIBLE_DELTA = 60_000L

        private const val DEFAULT_HEIGHT_CM = 175
        private const val DEFAULT_WEIGHT_KG = 70.0
        private const val DEFAULT_GOAL = 10_000

        private const val KEY_HEIGHT = "profile_height_cm"
        private const val KEY_WEIGHT = "profile_weight_kg"
        private const val KEY_GOAL = "profile_goal"
        private const val KEY_ONBOARDED = "profile_onboarded"
        private const val KEY_LIVE_NOTIFICATION = "profile_live_notification"
        private const val KEY_SKIPPED_VERSION = "update_skipped_version"
        private const val KEY_LAST_RAW = "sensor_last_raw"
        private const val KEY_LAST_ACTIVE_MINUTE = "sensor_last_active_minute"
        private const val KEY_LAST_EVENT_MILLIS = "sensor_last_event_millis"
        private const val KEY_CURRENT_DAY = "sensor_current_day"

        private const val PREFIX_STEPS = "steps_"
        private const val PREFIX_ACTIVE = "active_"

        private fun stepsKey(day: String) = "$PREFIX_STEPS$day"
        private fun activeKey(day: String) = "$PREFIX_ACTIVE$day"

        private fun formatter(): SimpleDateFormat =
            SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
                timeZone = TimeZone.getDefault()
            }

        fun dayKey(millis: Long): String = formatter().format(Date(millis))

        private fun midnightCalendar(millis: Long): Calendar =
            Calendar.getInstance().apply {
                timeInMillis = millis
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
    }
}
