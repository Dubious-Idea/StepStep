package com.purrweb.stepstep

import android.app.AlarmManager
import android.app.PendingIntent
import android.app.job.JobScheduler
import android.content.Context
import android.content.Intent
import android.os.Build
import java.util.Calendar

/**
 * Keeps [StepTrackingService] running and arms the one alarm it relies on:
 * 23:59 every day, which finalises the day's total before midnight and
 * restarts the service if the system or the ROM killed it in between.
 *
 * The alarm is exact. `USE_EXACT_ALARM` is granted at install and cannot be
 * revoked, which is what makes this work without asking the user for
 * anything: an inexact alarm may arrive up to an hour late, i.e. after
 * midnight — exactly when it is useless. Google Play limits that permission
 * to alarm and calendar apps, but this app ships through GitHub Releases;
 * moving to Play would mean going back to `SCHEDULE_EXACT_ALARM` plus a
 * screen asking the user to grant it.
 */
object RefreshScheduler {
    private const val DAILY_ALARM_REQUEST_CODE = 4712

    /** Hour/minute the daily finalisation runs at, in the device's local time. */
    private const val DAILY_HOUR = 23
    private const val DAILY_MINUTE = 59

    /** Starts (or nudges) the counter and arms the daily alarm. Idempotent. */
    fun ensureScheduled(context: Context) {
        clearLegacyWork(context)
        scheduleDailyAlarm(context)
        StepTrackingService.start(context)
    }

    /** Called by [StepRefreshReceiver] itself on each firing, and on every [ensureScheduled]. */
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
                // Only reachable if the exact-alarm permission is somehow
                // missing. Still Doze-aware, just not guaranteed to the minute.
                alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
            }
        }
    }

    /**
     * 1.4.x scheduled a periodic WorkManager job. The library is gone, but
     * JobScheduler keeps the persisted job across the update, so cancel it
     * once. Nothing else in the app uses JobScheduler.
     *
     * On Android 14+ WorkManager schedules into its own JobScheduler
     * namespace ("androidx.work.systemjobscheduler"), which a plain
     * cancelAll() does not reach — 1.5.0 missed it exactly that way.
     */
    private fun clearLegacyWork(context: Context) {
        val repository = StepRepository(context)
        if (repository.isLegacyWorkCleared) return
        runCatching {
            val jobs = context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as JobScheduler
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                jobs.cancelInAllNamespaces()
            } else {
                jobs.cancelAll()
            }
        }
        repository.isLegacyWorkCleared = true
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
