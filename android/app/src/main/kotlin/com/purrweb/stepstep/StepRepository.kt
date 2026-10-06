package com.purrweb.stepstep

import android.content.Context
import android.content.SharedPreferences
import android.provider.Settings
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Single source of truth for step data.
 *
 * The hardware `TYPE_STEP_COUNTER` reports steps since boot and keeps counting
 * while the app is dead, so the repository never tries to count anything
 * itself — it converts the raw counter into per-day totals by accumulating
 * deltas, which survives both reboots (counter resets to 0) and long periods
 * with no listener registered (one large delta arrives at the next reading).
 * The arithmetic itself lives in [StepLedger]; this class only loads and
 * stores its state.
 *
 * Flutter reads through [MainActivity]'s method channel rather than keeping a
 * second copy, so the widget, the notification and the UI can never disagree.
 */
class StepRepository(context: Context) {

    private val appContext: Context = context.applicationContext

    private val prefs: SharedPreferences =
        appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

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

    /**
     * Whether the foreground notification is the full lock-screen one with
     * the ring. Off does not stop counting — the service still needs *a*
     * notification — it switches to the collapsed one on the quiet channel.
     */
    var isLiveNotificationEnabled: Boolean
        get() = prefs.getBoolean(KEY_LIVE_NOTIFICATION, true)
        set(value) = prefs.edit().putBoolean(KEY_LIVE_NOTIFICATION, value).apply()

    /**
     * Set when the user swipes the notification away (allowed for foreground
     * services since Android 13). Until the app is opened again the service
     * stops re-posting it, instead of bringing it back on every screen-on.
     */
    var isNotificationDismissed: Boolean
        get() = prefs.getBoolean(KEY_NOTIFICATION_DISMISSED, false)
        set(value) = prefs.edit().putBoolean(KEY_NOTIFICATION_DISMISSED, value).apply()

    /** True once the WorkManager job left over from 1.4.x has been cancelled. */
    var isLegacyWorkCleared: Boolean
        get() = prefs.getBoolean(KEY_LEGACY_WORK_CLEARED, false)
        set(value) = prefs.edit().putBoolean(KEY_LEGACY_WORK_CLEARED, value).apply()

    /** Whether the app should check GitHub for a new release on launch. */
    var isAutoUpdateCheckEnabled: Boolean
        get() = prefs.getBoolean(KEY_AUTO_UPDATE_CHECK, true)
        set(value) = prefs.edit().putBoolean(KEY_AUTO_UPDATE_CHECK, value).apply()

    /**
     * When the auto-check last ran, so it can be throttled to once a day —
     * a manual check from the profile screen ignores this and always runs.
     */
    var lastAutoUpdateCheckMillis: Long
        get() = prefs.getLong(KEY_LAST_AUTO_UPDATE_CHECK, 0L)
        set(value) = prefs.edit().putLong(KEY_LAST_AUTO_UPDATE_CHECK, value).apply()

    // ------------------------------------------------------------ today state

    val todayKey: String get() = dayKey(System.currentTimeMillis())

    fun stepsOn(dayKey: String): Int = prefs.getInt(stepsKey(dayKey), 0)

    fun activeMinutesOn(dayKey: String): Int = prefs.getInt(activeKey(dayKey), 0)

    val todaySteps: Int get() = stepsOn(todayKey)

    val todayActiveMinutes: Int get() = activeMinutesOn(todayKey)

    /**
     * Folds one raw `TYPE_STEP_COUNTER` reading, taken at [atMillis], into
     * the totals.
     *
     * @return the new total for today.
     */
    fun recordRawCounter(raw: Long, atMillis: Long = System.currentTimeMillis()): Int =
        recordReadings(listOf(StepLedger.Reading(raw, atMillis)))

    /**
     * Folds a batch of readings (oldest first) in one transaction — a sensor
     * batch can hold hundreds of events, and committing each one separately
     * would copy the whole preference map hundreds of times.
     *
     * Synchronized across instances, not just this one: the service thread
     * and the activity each build their own repository.
     *
     * @return the new total for today.
     */
    fun recordReadings(
        readings: List<StepLedger.Reading>,
        nowMillis: Long = System.currentTimeMillis(),
    ): Int {
        if (readings.isEmpty()) return todaySteps
        synchronized(LOCK) { fold(readings, nowMillis) }
        return todaySteps
    }

    private fun fold(readings: List<StepLedger.Reading>, nowMillis: Long) {
        val result = StepLedger.apply(loadLedgerState(), readings, currentBootCount()) { dayKey(it) }

        val editor = prefs.edit()
        result.steps.forEach { (day, added) ->
            editor.putInt(stepsKey(day), stepsOn(day) + added)
        }
        result.activeMinutes.forEach { (day, added) ->
            editor.putInt(activeKey(day), activeMinutesOn(day) + added)
        }
        saveLedgerState(editor, result.state)

        val today = dayKey(nowMillis)
        val dayChanged = prefs.getString(KEY_CURRENT_DAY, null) != today
        if (dayChanged) editor.putString(KEY_CURRENT_DAY, today)
        editor.apply()

        if (dayChanged) pruneHistory(nowMillis)
    }

    private fun loadLedgerState() = StepLedger.State(
        lastRaw = prefs.getLong(KEY_LAST_RAW, StepLedger.NO_RAW),
        lastEventMillis = prefs.getLong(KEY_LAST_EVENT_MILLIS, StepLedger.NO_TIME),
        bootCount = prefs.getInt(KEY_LAST_BOOT_COUNT, StepLedger.UNKNOWN_BOOT),
        activeCarryMillis = prefs.getLong(KEY_ACTIVE_CARRY_MILLIS, 0L),
        activeCarryDay = prefs.getString(KEY_ACTIVE_CARRY_DAY, null),
    )

    private fun saveLedgerState(editor: SharedPreferences.Editor, state: StepLedger.State) {
        editor
            .putLong(KEY_LAST_RAW, state.lastRaw)
            .putLong(KEY_LAST_EVENT_MILLIS, state.lastEventMillis)
            .putInt(KEY_LAST_BOOT_COUNT, state.bootCount)
            .putLong(KEY_ACTIVE_CARRY_MILLIS, state.activeCarryMillis)
            .putString(KEY_ACTIVE_CARRY_DAY, state.activeCarryDay)
    }

    /**
     * Increments on every boot, which is exactly when the hardware counter
     * restarts from zero — a sturdier reboot signal than "the counter went
     * down", which a late-delivered batch can fake.
     */
    private fun currentBootCount(): Int = runCatching {
        Settings.Global.getInt(
            appContext.contentResolver,
            Settings.Global.BOOT_COUNT,
            StepLedger.UNKNOWN_BOOT,
        )
    }.getOrDefault(StepLedger.UNKNOWN_BOOT)

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

        /** Guards read-modify-write of the step totals across all instances. */
        private val LOCK = Any()

        private const val DEFAULT_HEIGHT_CM = 175
        private const val DEFAULT_WEIGHT_KG = 70.0
        private const val DEFAULT_GOAL = 10_000

        private const val KEY_HEIGHT = "profile_height_cm"
        private const val KEY_WEIGHT = "profile_weight_kg"
        private const val KEY_GOAL = "profile_goal"
        private const val KEY_ONBOARDED = "profile_onboarded"
        private const val KEY_LIVE_NOTIFICATION = "profile_live_notification"
        private const val KEY_NOTIFICATION_DISMISSED = "notification_dismissed"
        // v2: 1.5.0 set the original flag without reaching WorkManager's
        // JobScheduler namespace, so the cleanup has to run once more.
        private const val KEY_LEGACY_WORK_CLEARED = "legacy_work_cleared_v2"
        private const val KEY_SKIPPED_VERSION = "update_skipped_version"
        private const val KEY_AUTO_UPDATE_CHECK = "update_auto_check_enabled"
        private const val KEY_LAST_AUTO_UPDATE_CHECK = "update_last_auto_check_millis"

        private const val KEY_LAST_RAW = "sensor_last_raw"
        private const val KEY_LAST_EVENT_MILLIS = "sensor_last_event_millis"
        private const val KEY_LAST_BOOT_COUNT = "sensor_last_boot_count"
        private const val KEY_ACTIVE_CARRY_MILLIS = "sensor_active_carry_millis"
        private const val KEY_ACTIVE_CARRY_DAY = "sensor_active_carry_day"
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
