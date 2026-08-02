package com.purrweb.stepstep

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Keeps the step counter alive, and with it the two surfaces that live outside
 * the app: the ongoing notification (which is what the user actually sees on
 * the lock screen — Android phones have had no lock-screen widgets since
 * Lollipop) and the home-screen widget.
 *
 * The hardware counter keeps ticking without us, so the service is not what
 * makes counting work; it is what makes the *display* stay current while the
 * app is closed.
 */
class StepService : Service(), SensorEventListener {

    private lateinit var repository: StepRepository
    private lateinit var sensorManager: SensorManager
    private var stepSensor: Sensor? = null

    private val handler = Handler(Looper.getMainLooper())

    /** False once onCreate has given up, so later callbacks stay quiet. */
    private var isActive = false
    private var lastNotifiedSteps = -1
    private var lastNotifiedAt = 0L
    private var lastWidgetSteps = -1
    private var lastWidgetAt = 0L

    /** Refreshes the display even on a still day, and rolls over at midnight. */
    private val tick = object : Runnable {
        override fun run() {
            refresh(force = true)
            handler.postDelayed(this, TICK_INTERVAL_MS)
        }
    }

    override fun onCreate() {
        super.onCreate()
        repository = StepRepository(this)
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        stepSensor = sensorManager.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)

        createChannel()

        // A "health" foreground service is rejected outright without
        // ACTIVITY_RECOGNITION on Android 14+. Degrade to not running rather
        // than letting the SecurityException take the process down.
        if (!startInForeground()) {
            stopSelf()
            return
        }
        isActive = true

        if (stepSensor == null) {
            Log.w(TAG, "TYPE_STEP_COUNTER unavailable on this device")
        } else {
            sensorManager.registerListener(this, stepSensor, SensorManager.SENSOR_DELAY_NORMAL)
        }

        handler.postDelayed(tick, TICK_INTERVAL_MS)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP || !isActive) {
            stopSelf()
            return START_NOT_STICKY
        }
        refresh(force = true)
        // The system should bring the counter back after it reclaims memory.
        return START_STICKY
    }

    override fun onDestroy() {
        isActive = false
        handler.removeCallbacks(tick)
        stepSensor?.let { sensorManager.unregisterListener(this) }
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // --------------------------------------------------------------- sensor

    override fun onSensorChanged(event: SensorEvent) {
        if (!isActive || event.sensor.type != Sensor.TYPE_STEP_COUNTER) return
        repository.recordRawCounter(event.values.firstOrNull()?.toLong() ?: return)
        refresh(force = false)
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    // -------------------------------------------------------------- display

    /**
     * Pushes the current snapshot to the notification and the widget.
     *
     * Both are rate-limited: `NotificationManager` throttles callers that post
     * too often, and widget updates cross a process boundary, so a step-by-step
     * refresh would cost battery for changes nobody can perceive.
     */
    private fun refresh(force: Boolean) {
        val snapshot = repository.snapshot()
        val now = System.currentTimeMillis()

        val stepsMoved = abs(snapshot.steps - lastNotifiedSteps)
        val notificationDue = force ||
            lastNotifiedSteps < 0 ||
            (stepsMoved >= NOTIFICATION_STEP_THRESHOLD &&
                now - lastNotifiedAt >= NOTIFICATION_MIN_INTERVAL_MS)

        if (notificationDue) {
            lastNotifiedSteps = snapshot.steps
            lastNotifiedAt = now
            notificationManager().notify(NOTIFICATION_ID, buildNotification(snapshot))
        }

        val widgetDue = force ||
            lastWidgetSteps < 0 ||
            (abs(snapshot.steps - lastWidgetSteps) >= WIDGET_STEP_THRESHOLD &&
                now - lastWidgetAt >= WIDGET_MIN_INTERVAL_MS)

        if (widgetDue) {
            lastWidgetSteps = snapshot.steps
            lastWidgetAt = now
            StepWidgetProvider.updateAll(this)
        }
    }

    /** @return true when the service successfully entered the foreground. */
    private fun startInForeground(): Boolean {
        val notification = buildNotification(repository.snapshot())

        return runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        }.onFailure {
            Log.w(TAG, "Could not start foreground service", it)
        }.isSuccess
    }

    private fun buildNotification(snapshot: StepRepository.Snapshot): Notification {
        val goalReached = snapshot.steps >= snapshot.goal
        val ring = RingRenderer.render(
            sizePx = RING_BITMAP_PX,
            progress = snapshot.progress,
            goalReached = goalReached,
        )

        val openApp = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val collapsed = RemoteViews(packageName, R.layout.notification_steps).apply {
            setImageViewBitmap(R.id.notification_ring, ring)
            setTextViewText(R.id.notification_steps, Metrics.formatSteps(snapshot.steps))
            setTextViewText(
                R.id.notification_summary,
                summaryLine(snapshot, goalReached),
            )
        }

        val expanded = RemoteViews(packageName, R.layout.notification_steps_expanded).apply {
            setImageViewBitmap(R.id.notification_ring, ring)
            setTextViewText(R.id.notification_steps, Metrics.formatSteps(snapshot.steps))
            setTextViewText(
                R.id.notification_summary,
                summaryLine(snapshot, goalReached),
            )
            setTextViewText(R.id.notification_kcal, "${snapshot.kcal.roundToInt()}")
            setTextViewText(R.id.notification_distance, Metrics.formatDistance(snapshot.distanceKm))
            setTextViewText(
                R.id.notification_goal,
                "${(snapshot.progress * 100).roundToInt()}%",
            )
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_steps)
            .setContentTitle(Metrics.formatSteps(snapshot.steps))
            .setContentText(summaryLine(snapshot, goalReached))
            // No setLargeIcon: DecoratedCustomViewStyle renders the large icon
            // itself, next to a custom view that already draws the ring, so
            // setting both puts two rings on the same row.
            .setCustomContentView(collapsed)
            .setCustomBigContentView(expanded)
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .setContentIntent(openApp)
            .setColor(if (goalReached) GOLD else ACCENT)
            .setOngoing(true)
            .setSilent(true)
            .setShowWhen(false)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_WORKOUT)
            // Without this the ring is hidden behind "sensitive content" on a
            // locked screen, which is exactly where we want it visible.
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun summaryLine(
        snapshot: StepRepository.Snapshot,
        goalReached: Boolean,
    ): String {
        if (goalReached) {
            return "Цель выполнена · ${snapshot.kcal.roundToInt()} ккал"
        }
        val left = snapshot.goal - snapshot.steps
        return "${snapshot.kcal.roundToInt()} ккал · ещё ${Metrics.formatSteps(left)} до цели"
    }

    private fun createChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Счётчик шагов",
            // LOW keeps it silent but still on the lock screen and status bar.
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Показывает шаги и калории на экране блокировки"
            setShowBadge(false)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            enableVibration(false)
            setSound(null, null)
        }
        notificationManager().createNotificationChannel(channel)
    }

    private fun notificationManager(): NotificationManager =
        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    companion object {
        private const val TAG = "StepService"

        const val CHANNEL_ID = "steps_live"
        const val NOTIFICATION_ID = 1001
        const val ACTION_STOP = "com.purrweb.stepstep.STOP_SERVICE"

        private const val RING_BITMAP_PX = 192

        private const val ACCENT = 0xFF22E8B4.toInt()
        private const val GOLD = 0xFFFFC94A.toInt()

        private const val TICK_INTERVAL_MS = 60_000L

        private const val NOTIFICATION_STEP_THRESHOLD = 5
        private const val NOTIFICATION_MIN_INTERVAL_MS = 1_500L

        private const val WIDGET_STEP_THRESHOLD = 25
        private const val WIDGET_MIN_INTERVAL_MS = 20_000L

        /** True when ACTIVITY_RECOGNITION has been granted. */
        fun canRun(context: Context): Boolean =
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.ACTIVITY_RECOGNITION,
            ) == PackageManager.PERMISSION_GRANTED

        /**
         * Starts the counter if it is allowed to run.
         *
         * @return false when the permission is missing — callers should send
         *   the user through the permission prompt rather than retrying.
         */
        fun start(context: Context): Boolean {
            if (!canRun(context)) return false
            context.startForegroundService(Intent(context, StepService::class.java))
            return true
        }

        fun stop(context: Context) {
            context.startService(
                Intent(context, StepService::class.java).setAction(ACTION_STOP),
            )
        }
    }
}
