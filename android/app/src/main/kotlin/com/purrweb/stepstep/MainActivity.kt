package com.purrweb.stepstep

import android.content.Context
import android.content.Intent
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges Flutter to the native step store.
 *
 * Flutter deliberately keeps no second copy of the step data — it asks for a
 * snapshot. That is what keeps the UI, the widget and the lock-screen
 * notification from ever showing three different numbers.
 */
class MainActivity : FlutterActivity() {

    private val repository: StepRepository by lazy { StepRepository(this) }
    private val permissions: PermissionCoordinator by lazy {
        PermissionCoordinator(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        StepNotifier.createChannel(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler(::handle)
    }

    override fun onResume() {
        super.onResume()
        // The schedule can be gone for reasons the app never hears about: the
        // system reclaimed the alarm, the package was replaced. Opening the
        // app is the one moment we know we can put it back. Re-arming an
        // already-armed schedule is a no-op beyond replacing it with itself.
        if (repository.isOnboarded) {
            RefreshScheduler.ensureScheduled(this)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissionNames: Array<out String>,
        grantResults: IntArray,
    ) {
        if (permissions.onRequestPermissionsResult(requestCode)) {
            // Newly granted activity recognition means the schedule can
            // finally do something useful, so arm it without waiting for
            // another user action.
            if (repository.isOnboarded) {
                RefreshScheduler.ensureScheduled(this)
            }
            return
        }
        super.onRequestPermissionsResult(requestCode, permissionNames, grantResults)
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getSnapshot" -> result.success(repository.snapshot().toMap())

            "getHistory" -> {
                val days = call.argument<Int>("days") ?: DEFAULT_HISTORY_DAYS
                val entries = repository
                    .history(days.coerceIn(1, StepRepository.HISTORY_DAYS))
                    .map { it.toMap() }
                result.success(entries)
            }

            // Arbitrary date range, for the month/year browser — unlike
            // getHistory this is not anchored to today.
            "getHistoryRange" -> {
                val start = call.argument<String>("start")
                val end = call.argument<String>("end")
                if (start == null || end == null) {
                    result.success(emptyList<Map<String, Any>>())
                } else {
                    result.success(repository.historyRange(start, end).map { it.toMap() })
                }
            }

            "saveProfile" -> {
                repository.heightCm = call.argument<Int>("heightCm") ?: repository.heightCm
                repository.weightKg = call.argument<Double>("weightKg") ?: repository.weightKg
                repository.goal = call.argument<Int>("goal") ?: repository.goal
                repository.isOnboarded = true
                // Both outside surfaces show calories, so they go stale the
                // moment weight or height changes.
                refreshDisplays()
                RefreshScheduler.ensureScheduled(this)
                result.success(repository.snapshot().toMap())
            }

            "isOnboarded" -> result.success(repository.isOnboarded)

            // Read from the package rather than pubspec, so the number always
            // matches the APK actually installed — that is what the update
            // check compares against the latest GitHub release.
            "appVersion" -> result.success(
                runCatching {
                    packageManager.getPackageInfo(packageName, 0).versionName
                }.getOrNull(),
            )

            "skippedUpdateVersion" -> result.success(repository.skippedUpdateVersion)

            "setSkippedUpdateVersion" -> {
                repository.skippedUpdateVersion = call.argument<String>("version")
                result.success(null)
            }

            "isAutoUpdateCheckEnabled" -> result.success(repository.isAutoUpdateCheckEnabled)

            "setAutoUpdateCheckEnabled" -> {
                repository.isAutoUpdateCheckEnabled = call.argument<Boolean>("enabled") ?: true
                result.success(null)
            }

            "lastAutoUpdateCheckMillis" -> result.success(repository.lastAutoUpdateCheckMillis)

            "setLastAutoUpdateCheckMillis" -> {
                repository.lastAutoUpdateCheckMillis =
                    (call.argument<Number>("millis"))?.toLong() ?: System.currentTimeMillis()
                result.success(null)
            }

            "openUrl" -> {
                val url = call.argument<String>("url").orEmpty()
                result.success(openExternally(url))
            }

            "permissionStatus" -> result.success(permissions.status())

            "requestPermissions" -> permissions.request(result::success)

            "openAppSettings" -> {
                permissions.openAppSettings()
                result.success(null)
            }

            "isIgnoringBatteryOptimizations" ->
                result.success(permissions.isIgnoringBatteryOptimizations())

            "requestIgnoreBatteryOptimizations" -> {
                permissions.requestIgnoreBatteryOptimizations()
                result.success(null)
            }

            "hasStepSensor" -> result.success(hasStepSensor())

            "isLiveNotificationEnabled" ->
                result.success(repository.isLiveNotificationEnabled)

            "setLiveNotificationEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") ?: true
                repository.isLiveNotificationEnabled = enabled
                if (enabled) {
                    StepNotifier.post(this, repository.snapshot())
                } else {
                    StepNotifier.cancel(this)
                }
                result.success(enabled)
            }

            "startTracking" -> {
                repository.isOnboarded = true
                RefreshScheduler.ensureScheduled(this)
                RefreshScheduler.refreshNow(this)
                result.success(null)
            }

            "refreshIntervalMinutes" -> result.success(repository.refreshIntervalMinutes)

            "setRefreshIntervalMinutes" -> {
                val minutes = call.argument<Int>("minutes") ?: StepRepository.DEFAULT_REFRESH_INTERVAL_MIN
                repository.refreshIntervalMinutes = minutes
                RefreshScheduler.schedulePeriodic(this, repository.refreshIntervalMinutes)
                result.success(repository.refreshIntervalMinutes)
            }

            // Pulls the hardware counter directly so a freshly opened app shows
            // steps taken since the last scheduled read, without waiting for
            // the next one.
            "refreshFromSensor" -> readSensorOnce(result)

            else -> result.notImplemented()
        }
    }

    /** Repaints the widgets and, if enabled, the ongoing notification. */
    private fun refreshDisplays() {
        Widgets.updateAll(this)
        if (repository.isLiveNotificationEnabled) {
            StepNotifier.post(this, repository.snapshot())
        }
    }

    private fun hasStepSensor(): Boolean =
        sensorManager().getDefaultSensor(Sensor.TYPE_STEP_COUNTER) != null

    /**
     * Hands a URL to whatever app handles it — the browser for a release page,
     * the download manager for an APK.
     *
     * @return false when nothing on the device can open it, so the caller can
     *   say so instead of appearing to do nothing.
     */
    private fun openExternally(url: String): Boolean {
        if (url.isBlank()) return false
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return runCatching { startActivity(intent) }.isSuccess
    }

    private fun sensorManager(): SensorManager =
        getSystemService(Context.SENSOR_SERVICE) as SensorManager

    /**
     * Registers for a single `TYPE_STEP_COUNTER` reading, folds it into the
     * repository and returns the resulting snapshot. Falls back to the stored
     * snapshot if the sensor stays quiet.
     */
    private fun readSensorOnce(result: MethodChannel.Result) {
        val manager = sensorManager()
        val sensor = manager.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
        if (sensor == null) {
            result.success(repository.snapshot().toMap())
            return
        }

        val handler = Handler(Looper.getMainLooper())
        var settled = false

        val listener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                if (settled) return
                settled = true
                manager.unregisterListener(this)
                handler.removeCallbacksAndMessages(null)

                event.values.firstOrNull()?.let {
                    repository.recordRawCounter(it.toLong())
                }
                refreshDisplays()
                result.success(repository.snapshot().toMap())
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
        }

        manager.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_FASTEST)

        handler.postDelayed({
            if (settled) return@postDelayed
            settled = true
            manager.unregisterListener(listener)
            result.success(repository.snapshot().toMap())
        }, SENSOR_READ_TIMEOUT_MS)
    }

    private companion object {
        const val CHANNEL = "com.purrweb.stepstep/steps"
        const val SENSOR_READ_TIMEOUT_MS = 1_500L
        const val DEFAULT_HISTORY_DAYS = 7
    }
}
