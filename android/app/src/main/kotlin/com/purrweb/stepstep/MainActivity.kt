package com.purrweb.stepstep

import android.content.Context
import android.content.Intent
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges Flutter to the native step store.
 *
 * Flutter deliberately keeps no second copy of the step data — it asks for a
 * snapshot, and listens on [LIVE_CHANNEL] for fresh ones while it is open.
 * That is what keeps the UI, the widget and the lock-screen notification
 * from ever showing three different numbers.
 */
class MainActivity : FlutterActivity() {

    private val repository: StepRepository by lazy { StepRepository(this) }
    private val permissions: PermissionCoordinator by lazy {
        PermissionCoordinator(this)
    }
    private val mainHandler = Handler(Looper.getMainLooper())

    /** The open app's subscription to [StepLive], while Flutter listens. */
    private var liveListener: ((StepRepository.Snapshot) -> Unit)? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        StepNotifier.createChannels(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler(::handle)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, LIVE_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    stopLive()
                    val listener: (StepRepository.Snapshot) -> Unit = { snapshot ->
                        // StepLive calls back on the service thread; event
                        // sinks must be used on the main one.
                        mainHandler.post { events.success(snapshot.toMap()) }
                    }
                    liveListener = listener
                    StepLive.add(listener)
                }

                override fun onCancel(arguments: Any?) = stopLive()
            })
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        stopLive()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onResume() {
        super.onResume()
        // The service can be gone for reasons the app never hears about: the
        // ROM killed it, the user force-stopped the app. Opening the app is
        // the one moment a foreground-service start is always allowed, so
        // put everything back. Starting a running service just nudges it to
        // re-read and repaint.
        if (repository.isOnboarded) {
            // Opening the app is the signal to bring back a notification the
            // user swiped away.
            repository.isNotificationDismissed = false
            RefreshScheduler.ensureScheduled(this)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissionNames: Array<out String>,
        grantResults: IntArray,
    ) {
        if (permissions.onRequestPermissionsResult(requestCode)) {
            // Newly granted activity recognition is what lets the service
            // start at all, so start it without waiting for another user
            // action.
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

            // Lets the profile screen show the Xiaomi-only autostart hint:
            // HyperOS/MIUI keeps background apps from starting on their own
            // until the user allows it, on top of stock Android's rules.
            "deviceManufacturer" -> result.success(Build.MANUFACTURER.orEmpty())

            "hasStepSensor" -> result.success(hasStepSensor())

            "isLiveNotificationEnabled" ->
                result.success(repository.isLiveNotificationEnabled)

            // Off does not stop counting: the service keeps running under the
            // collapsed notification on the quiet channel instead.
            "setLiveNotificationEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") ?: true
                repository.isLiveNotificationEnabled = enabled
                repository.isNotificationDismissed = false
                if (!StepTrackingService.repaint()) RefreshScheduler.ensureScheduled(this)
                result.success(enabled)
            }

            "startTracking" -> {
                repository.isOnboarded = true
                RefreshScheduler.ensureScheduled(this)
                result.success(null)
            }

            // A freshly opened app should show steps up to this moment, not
            // up to the last batch the service happened to receive.
            "refreshFromSensor" -> {
                val viaService = StepTrackingService.refresh {
                    mainHandler.post { result.success(repository.snapshot().toMap()) }
                }
                if (!viaService) readSensorOnce(result)
            }

            else -> result.notImplemented()
        }
    }

    private fun stopLive() {
        liveListener?.let(StepLive::remove)
        liveListener = null
    }

    /** Repaints the widgets and the notification; without the service, just the widgets. */
    private fun refreshDisplays() {
        if (!StepTrackingService.repaint()) Widgets.updateAll(this)
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
     * Fallback for when [StepTrackingService] is not running (e.g. the
     * permission is still missing): registers for a single
     * `TYPE_STEP_COUNTER` reading, folds it into the repository and returns
     * the resulting snapshot. Falls back to the stored snapshot if the
     * sensor stays quiet.
     */
    private fun readSensorOnce(result: MethodChannel.Result) {
        val manager = sensorManager()
        val sensor = manager.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
        if (sensor == null) {
            result.success(repository.snapshot().toMap())
            return
        }

        var settled = false

        val listener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                if (settled) return
                settled = true
                manager.unregisterListener(this)
                mainHandler.removeCallbacksAndMessages(SENSOR_TIMEOUT_TOKEN)

                event.values.firstOrNull()?.let {
                    repository.recordRawCounter(
                        it.toLong(),
                        StepLedger.eventWallMillis(
                            timestampNanos = event.timestamp,
                            nowMillis = System.currentTimeMillis(),
                            elapsedRealtimeNanos = SystemClock.elapsedRealtimeNanos(),
                        ),
                    )
                }
                refreshDisplays()
                result.success(repository.snapshot().toMap())
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
        }

        manager.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_FASTEST)

        mainHandler.postAtTime(
            {
                if (!settled) {
                    settled = true
                    manager.unregisterListener(listener)
                    result.success(repository.snapshot().toMap())
                }
            },
            SENSOR_TIMEOUT_TOKEN,
            SystemClock.uptimeMillis() + SENSOR_READ_TIMEOUT_MS,
        )
    }

    private companion object {
        const val CHANNEL = "com.purrweb.stepstep/steps"
        const val LIVE_CHANNEL = "com.purrweb.stepstep/live"
        const val SENSOR_READ_TIMEOUT_MS = 1_500L
        const val DEFAULT_HISTORY_DAYS = 7

        /** Lets the timeout be cancelled without clearing the live channel's posts. */
        val SENSOR_TIMEOUT_TOKEN = Any()
    }
}
