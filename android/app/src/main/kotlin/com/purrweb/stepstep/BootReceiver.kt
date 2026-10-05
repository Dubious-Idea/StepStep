package com.purrweb.stepstep

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Restarts the counter and re-arms the daily alarm after a reboot or an app
 * update. Both broadcasts are exempt from the background limits on starting
 * a foreground service, and Android 15's restriction on doing so from
 * `BOOT_COMPLETED` does not cover the `health` type.
 *
 * A reboot also resets the hardware step counter to zero; [StepLedger]
 * notices through the boot count, so nothing special is needed here.
 * On HyperOS/MIUI this broadcast only arrives with "Autostart" allowed for
 * the app — the profile screen points there.
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
