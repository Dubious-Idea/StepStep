package com.purrweb.stepstep

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.PowerManager

/**
 * Two app-internal broadcasts, both via explicit PendingIntents:
 *
 * - the exact alarm [RefreshScheduler] arms for 23:59 — hands the day's
 *   finalisation to [StepTrackingService] (starting it if it was killed) and
 *   re-arms tomorrow's alarm, since `AlarmManager` alarms are one-shot;
 * - the notification's delete intent, which fires when the user swipes it
 *   away — see [StepRepository.isNotificationDismissed].
 */
class StepRefreshReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_DAILY_REFRESH -> {
                // The alarm's wake lock ends when this method returns; keep
                // the CPU up long enough for the service to take over.
                val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
                powerManager
                    .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "StepStep:alarm")
                    .acquire(HANDOFF_WAKE_LOCK_MS)

                RefreshScheduler.scheduleDailyAlarm(context)
                StepTrackingService.finaliseDay(context)
            }

            ACTION_NOTIFICATION_DISMISSED ->
                StepRepository(context).isNotificationDismissed = true
        }
    }

    companion object {
        const val ACTION_DAILY_REFRESH = "com.purrweb.stepstep.DAILY_REFRESH"
        const val ACTION_NOTIFICATION_DISMISSED = "com.purrweb.stepstep.NOTIFICATION_DISMISSED"

        private const val HANDOFF_WAKE_LOCK_MS = 5_000L
    }
}
