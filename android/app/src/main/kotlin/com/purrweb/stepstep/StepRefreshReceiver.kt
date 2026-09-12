package com.purrweb.stepstep

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Fired by the exact alarm [RefreshScheduler] arms for 23:59. Delegates the
 * actual sensor read to [StepRefreshWorker] (a `BroadcastReceiver` should
 * return in milliseconds, not block on a sensor callback) and immediately
 * re-arms tomorrow's alarm — `AlarmManager` alarms are one-shot even when set
 * with a "repeating" API, so rescheduling on every firing is the reliable
 * pattern rather than a drift-prone fixed-period repeat.
 */
class StepRefreshReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_DAILY_REFRESH) return

        RefreshScheduler.runDailyRefresh(context)
        RefreshScheduler.scheduleDailyAlarm(context)
    }

    companion object {
        const val ACTION_DAILY_REFRESH = "com.purrweb.stepstep.DAILY_REFRESH"
    }
}
