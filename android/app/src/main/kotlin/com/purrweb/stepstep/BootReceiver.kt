package com.purrweb.stepstep

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Restarts the counter after a reboot.
 *
 * A reboot also resets the hardware step counter to zero;
 * [StepRepository.recordRawCounter] detects that as a backwards jump, so no
 * special handling is needed here beyond getting the service running again.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED &&
            intent.action != Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            return
        }
        if (StepRepository(context).isOnboarded) {
            StepService.start(context)
        }
    }
}
