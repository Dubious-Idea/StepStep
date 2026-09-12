package com.purrweb.stepstep

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import java.util.Calendar
import java.util.concurrent.TimeUnit

/**
 * Arms and re-arms the two schedules that replace the always-on foreground
 * service: a periodic [StepRefreshWorker] run at the user's chosen interval
 * (kept fresh for the widgets and the notification), and an exact alarm at
 * 23:59 that finalises the day's total before midnight rolls it over into
 * "yesterday" — the same gap this whole scheme exists to close.
 *
 * Neither schedule depends on the process staying alive in between: the
 * periodic one is a `PeriodicWorkRequest`, which the system persists and
 * redelivers on its own even across reboots, and the daily alarm is
 * re-armed by [StepRefreshReceiver] itself every time it fires (`AlarmManager`
 * alarms do not survive a reboot, which is why [BootReceiver] also calls
 * [ensureScheduled]).
 */
object RefreshScheduler {
    private const val PERIODIC_WORK_NAME = "step_refresh_periodic"
    private const val DAILY_WORK_NAME = "step_refresh_daily"
    private const val DAILY_ALARM_REQUEST_CODE = 4712

    /** Hour/minute the daily finalisation runs at, in the device's local time. */
    private const val DAILY_HOUR = 23
    private const val DAILY_MINUTE = 59

    /** Arms both schedules from the currently saved interval. Idempotent. */
    fun ensureScheduled(context: Context) {
        schedulePeriodic(context, StepRepository(context).refreshIntervalMinutes)
        scheduleDailyAlarm(context)
    }

    /** Re-arms the periodic job with a new interval, replacing the old one. */
    fun schedulePeriodic(context: Context, intervalMinutes: Int) {
        val clamped = intervalMinutes.coerceIn(
            StepRepository.MIN_REFRESH_INTERVAL_MIN,
            StepRepository.MAX_REFRESH_INTERVAL_MIN,
        )
        val request = PeriodicWorkRequestBuilder<StepRefreshWorker>(
            clamped.toLong(),
            TimeUnit.MINUTES,
        ).build()

        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            PERIODIC_WORK_NAME,
            ExistingPeriodicWorkPolicy.UPDATE,
            request,
        )
    }

    /** Runs a refresh right away, e.g. right after onboarding or enabling the notification. */
    fun refreshNow(context: Context) {
        WorkManager.getInstance(context).enqueueUniqueWork(
            "step_refresh_immediate",
            ExistingWorkPolicy.REPLACE,
            OneTimeWorkRequestBuilder<StepRefreshWorker>().build(),
        )
    }

    /** Called by [StepRefreshReceiver] itself on each firing, and by [BootReceiver]. */
    fun scheduleDailyAlarm(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pendingIntent = dailyAlarmIntent(context)

        val triggerAt = nextDailyTriggerMillis()
        val canBeExact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            alarmManager.canScheduleExactAlarms()

        runCatching {
            if (canBeExact) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerAt,
                    pendingIntent,
                )
            } else {
                // No permission for exact alarms (Android 13+ until the user
                // grants "Alarms & reminders") — still Doze-aware, just not
                // guaranteed to the minute.
                alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
            }
        }
    }

    /** Runs the worker directly for the daily finalisation, bypassing the periodic queue. */
    fun runDailyRefresh(context: Context) {
        WorkManager.getInstance(context).enqueueUniqueWork(
            DAILY_WORK_NAME,
            ExistingWorkPolicy.REPLACE,
            OneTimeWorkRequestBuilder<StepRefreshWorker>().build(),
        )
    }

    private fun nextDailyTriggerMillis(): Long {
        val now = Calendar.getInstance()
        val target = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, DAILY_HOUR)
            set(Calendar.MINUTE, DAILY_MINUTE)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        if (!target.after(now)) target.add(Calendar.DAY_OF_YEAR, 1)
        return target.timeInMillis
    }

    private fun dailyAlarmIntent(context: Context): PendingIntent {
        val intent = Intent(context, StepRefreshReceiver::class.java)
            .setAction(StepRefreshReceiver.ACTION_DAILY_REFRESH)
        return PendingIntent.getBroadcast(
            context,
            DAILY_ALARM_REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
