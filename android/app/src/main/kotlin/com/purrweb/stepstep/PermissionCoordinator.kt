package com.purrweb.stepstep

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

/**
 * Runtime permissions for the counter.
 *
 * The two are not equally important and are reported separately:
 * ACTIVITY_RECOGNITION is what makes counting possible at all, while
 * POST_NOTIFICATIONS only decides whether the result reaches the lock screen.
 * Collapsing them into one boolean would make a working app look broken.
 */
class PermissionCoordinator(private val activity: Activity) {

    private val prefs: SharedPreferences =
        activity.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private var pending: ((Map<String, Any>) -> Unit)? = null

    fun status(): Map<String, Any> {
        val activityGranted = isGranted(Manifest.permission.ACTIVITY_RECOGNITION)
        return mapOf(
            "canCountSteps" to activityGranted,
            "canShowNotification" to isGranted(notificationPermission),
            "isPermanentlyDenied" to isPermanentlyDenied(activityGranted),
        )
    }

    /**
     * Prompts for anything still missing and reports the outcome once the
     * system dialogs have been dismissed.
     *
     * If nothing is missing the callback fires immediately — Android shows no
     * dialog for already-granted permissions, so there would be no result
     * callback to wait for.
     */
    fun request(onResult: (Map<String, Any>) -> Unit) {
        val missing = buildList {
            if (!isGranted(Manifest.permission.ACTIVITY_RECOGNITION)) {
                add(Manifest.permission.ACTIVITY_RECOGNITION)
            }
            if (!isGranted(notificationPermission)) add(notificationPermission)
        }

        if (missing.isEmpty()) {
            onResult(status())
            return
        }

        prefs.edit().putBoolean(KEY_HAS_ASKED, true).apply()
        pending = onResult
        ActivityCompat.requestPermissions(
            activity,
            missing.toTypedArray(),
            REQUEST_CODE,
        )
    }

    /** @return true when this result belonged to us. */
    fun onRequestPermissionsResult(requestCode: Int): Boolean {
        if (requestCode != REQUEST_CODE) return false
        pending?.invoke(status())
        pending = null
        return true
    }

    /** Opens this app's system settings page, for the "don't ask again" case. */
    fun openAppSettings() {
        activity.startActivity(
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.fromParts("package", activity.packageName, null),
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
    }

    private fun isGranted(permission: String): Boolean =
        ContextCompat.checkSelfPermission(activity, permission) ==
            PackageManager.PERMISSION_GRANTED

    /**
     * Android exposes no "permanently denied" flag. The reliable signal is the
     * combination the system itself uses: we have asked at least once, the
     * permission is still denied, and the platform no longer wants us to show
     * a rationale — which only happens after "don't ask again".
     */
    private fun isPermanentlyDenied(granted: Boolean): Boolean {
        if (granted) return false
        if (!prefs.getBoolean(KEY_HAS_ASKED, false)) return false
        return !ActivityCompat.shouldShowRequestPermissionRationale(
            activity,
            Manifest.permission.ACTIVITY_RECOGNITION,
        )
    }

    /**
     * Before Android 13 notifications needed no runtime grant. Probing a
     * permission that does not exist yet always reports denied, so map it to
     * one that is always held instead.
     */
    private val notificationPermission: String
        get() = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.POST_NOTIFICATIONS
        } else {
            Manifest.permission.FOREGROUND_SERVICE
        }

    private companion object {
        const val REQUEST_CODE = 4711
        const val PREFS_NAME = StepRepository.PREFS_NAME
        const val KEY_HAS_ASKED = "permission_has_asked"
    }
}
