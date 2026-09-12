package com.purrweb.stepstep

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Re-arms the two refresh schedules after a reboot.
 *
 * A reboot also resets the hardware step counter to zero;
 * [StepRepository.recordRawCounter] detects that as a backwards jump, so no
 * special handling is needed here beyond that. `AlarmManager` alarms in
 * particular do not survive a reboot on their own — the periodic
 * `PeriodicWorkRequest` does, via WorkManager's own boot receiver, but
 * re-enqueueing it here too is a harmless no-op and costs nothing to keep.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED &&
            intent.action != Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            return
        }
        if (StepRepository(context).isOnboarded) {
            RefreshScheduler.ensureScheduled(context)
        }
    }
}
