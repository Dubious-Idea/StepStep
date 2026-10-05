package com.purrweb.stepstep

import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener2
import android.hardware.SensorManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import androidx.core.content.ContextCompat
import java.util.Calendar

/**
 * The classic always-on step counter, built so that being always on costs
 * next to nothing.
 *
 * The hardware counter lives in the sensor hub, a low-power coprocessor that
 * counts whether or not anyone listens, so this service is not what makes
 * counting work. It exists for the two surfaces outside the app — the
 * lock-screen notification and the home-screen widgets — and those are only
 * ever seen with the screen on. So:
 *
 * - **Screen off:** nothing is drawn. The listener stays registered with a
 *   long report latency; while the CPU sleeps, events wait in the hub's FIFO
 *   without waking it, each stamped with the moment the step happened.
 * - **Screen on:** one flush and one repaint — the CPU is already awake for
 *   the display, so this rides along for a few milliseconds.
 * - **Screen on, walking:** a short latency for a near-live counter, with
 *   repaints throttled to [NOTIFICATION_MIN_INTERVAL_MS] / [WIDGETS_MIN_INTERVAL_MS].
 *
 * The only wake-up the app causes on its own is the 23:59 alarm (see
 * [RefreshScheduler]), which doubles as a watchdog: an exact alarm may start
 * a foreground service from the background, so it brings this service back
 * if the system or the ROM killed it.
 *
 * All work runs on a private [HandlerThread], never on the main thread the
 * Flutter UI shares.
 */
class StepTrackingService : Service(), SensorEventListener2 {

    private enum class Repaint { ALWAYS, IF_CHANGED, IF_CHANGED_THROTTLED }

    private lateinit var repository: StepRepository
    private lateinit var sensorManager: SensorManager
    private lateinit var powerManager: PowerManager
    private lateinit var thread: HandlerThread
    private lateinit var handler: Handler
    private var stepSensor: Sensor? = null

    /** False until onCreate has fully set up, and again once torn down. */
    private var isActive = false
    private var isScreenOn = false

    /** Readings of the batch being delivered, folded in one transaction. */
    private val pending = ArrayList<StepLedger.Reading>()
    private var isFoldPosted = false

    private var isFlushing = false
    private val flushWaiters = ArrayList<() -> Unit>()

    private var lastNotifiedSteps = -1
    private var lastNotifiedAt = 0L
    private var lastWidgetSteps = -1
    private var lastWidgetsAt = 0L
    private var isCatchUpPosted = false

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                Intent.ACTION_SCREEN_ON -> onScreenOn()
                Intent.ACTION_SCREEN_OFF -> onScreenOff()
            }
        }
    }

    // A batch is dispatched as a tight run of callbacks on this looper, so a
    // fold queued behind the first one runs once the run is in.
    private val foldRunnable = Runnable {
        isFoldPosted = false
        if (foldPending() && isScreenOn && !isFlushing) render(Repaint.IF_CHANGED_THROTTLED)
    }

    private val flushTimeout = Runnable { completeFlush() }

    private val catchUp = Runnable {
        isCatchUpPosted = false
        if (isScreenOn) render(Repaint.IF_CHANGED_THROTTLED)
    }

    private val midnight = Runnable {
        render(Repaint.IF_CHANGED)
        scheduleMidnight()
    }

    override fun onCreate() {
        super.onCreate()
        repository = StepRepository(this)
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        // The non-wake-up variant on purpose: it never wakes the CPU.
        stepSensor = sensorManager.getDefaultSensor(Sensor.TYPE_STEP_COUNTER, false)
            ?: sensorManager.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)

        StepNotifier.createChannels(this)
        if (!enterForeground()) {
            stopSelf()
            return
        }

        thread = HandlerThread("StepTracking").apply { start() }
        handler = Handler(thread.looper)
        isActive = true
        instance = this

        isScreenOn = powerManager.isInteractive
        ContextCompat.registerReceiver(
            this,
            screenReceiver,
            IntentFilter().apply {
                addAction(Intent.ACTION_SCREEN_ON)
                addAction(Intent.ACTION_SCREEN_OFF)
            },
            null,
            handler,
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )

        handler.post {
            registerSensor()
            flush { render(Repaint.ALWAYS) }
            if (isScreenOn) scheduleMidnight()
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!isActive) {
            stopSelf()
            return START_NOT_STICKY
        }
        // Every startForegroundService() call expects startForeground()
        // again, even with the service already running.
        enterForeground()
        if (intent?.action == ACTION_DAY_END) handler.post { finaliseDay() }
        return START_STICKY
    }

    override fun onDestroy() {
        if (isActive) {
            isActive = false
            instance = null
            sensorManager.unregisterListener(this)
            runCatching { unregisterReceiver(screenReceiver) }
            thread.quitSafely()
        }
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // --------------------------------------------------------------- sensor

    override fun onSensorChanged(event: SensorEvent) {
        if (event.sensor.type != Sensor.TYPE_STEP_COUNTER) return
        val raw = event.values.firstOrNull()?.toLong() ?: return
        val atMillis = StepLedger.eventWallMillis(
            timestampNanos = event.timestamp,
            nowMillis = System.currentTimeMillis(),
            elapsedRealtimeNanos = SystemClock.elapsedRealtimeNanos(),
        )
        pending += StepLedger.Reading(raw, atMillis)
        if (!isFoldPosted) {
            isFoldPosted = true
            handler.post(foldRunnable)
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    override fun onFlushCompleted(sensor: Sensor) {
        // Queued behind the fold of the batch this flush delivered.
        handler.post { completeFlush() }
    }

    /** Short latency while someone can see the numbers, long otherwise. */
    private fun registerSensor() {
        val sensor = stepSensor ?: return
        sensorManager.unregisterListener(this)
        val latencyUs = if (isScreenOn) SCREEN_ON_LATENCY_US else SCREEN_OFF_LATENCY_US
        sensorManager.registerListener(
            this,
            sensor,
            SensorManager.SENSOR_DELAY_NORMAL,
            latencyUs,
            handler,
        )
    }

    /**
     * Asks the hub to hand over whatever it has batched, then runs [then]
     * once that has been folded in — or after [FLUSH_TIMEOUT_MS] on a device
     * that never confirms the flush.
     */
    private fun flush(then: () -> Unit) {
        flushWaiters += then
        if (isFlushing) return
        isFlushing = true
        val requested = stepSensor != null && sensorManager.flush(this)
        if (requested) {
            handler.postDelayed(flushTimeout, FLUSH_TIMEOUT_MS)
        } else {
            handler.post(flushTimeout)
        }
    }

    private fun completeFlush() {
        if (!isFlushing) return
        isFlushing = false
        handler.removeCallbacks(flushTimeout)
        foldPending()
        val waiters = ArrayList(flushWaiters)
        flushWaiters.clear()
        waiters.forEach { it() }
    }

    /** @return true when there was anything to fold. */
    private fun foldPending(): Boolean {
        if (pending.isEmpty()) return false
        val readings = ArrayList(pending)
        pending.clear()
        repository.recordReadings(readings)
        StepLive.publish { repository.snapshot() }
        return true
    }

    // --------------------------------------------------------------- screen

    private fun onScreenOn() {
        isScreenOn = true
        // Drain what was batched while the screen was off — with its real
        // timestamps — before re-registering, which may drop the FIFO.
        flush {
            registerSensor()
            render(Repaint.IF_CHANGED)
        }
        scheduleMidnight()
    }

    private fun onScreenOff() {
        isScreenOn = false
        handler.removeCallbacks(midnight)
        handler.removeCallbacks(catchUp)
        isCatchUpPosted = false
        flush { registerSensor() }
    }

    /** Rolls the displays over to the new day if the screen is on at midnight. */
    private fun scheduleMidnight() {
        handler.removeCallbacks(midnight)
        val next = Calendar.getInstance().apply {
            add(Calendar.DAY_OF_YEAR, 1)
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 1)
            set(Calendar.MILLISECOND, 0)
        }
        handler.postDelayed(midnight, next.timeInMillis - System.currentTimeMillis())
    }

    /**
     * The 23:59 alarm: make sure everything up to now is folded before the
     * date rolls over. The alarm's own wake lock ends when its receiver
     * returns, so hold one just until the flush is in.
     */
    private fun finaliseDay() {
        val wakeLock = powerManager
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "StepStep:day-end")
            .apply {
                setReferenceCounted(false)
                acquire(DAY_END_WAKE_LOCK_MS)
            }
        flush {
            if (isScreenOn) render(Repaint.IF_CHANGED)
            wakeLock.release()
        }
    }

    // -------------------------------------------------------------- display

    private fun render(mode: Repaint) {
        val snapshot = repository.snapshot()
        val now = SystemClock.elapsedRealtime()

        if (isDue(mode, snapshot.steps, lastNotifiedSteps, lastNotifiedAt, NOTIFICATION_MIN_INTERVAL_MS, now)) {
            if (!repository.isNotificationDismissed) {
                StepNotifier.post(this, snapshot, repository.isLiveNotificationEnabled)
            }
            lastNotifiedSteps = snapshot.steps
            lastNotifiedAt = now
        }

        if (isDue(mode, snapshot.steps, lastWidgetSteps, lastWidgetsAt, WIDGETS_MIN_INTERVAL_MS, now)) {
            Widgets.updateAll(this)
            lastWidgetSteps = snapshot.steps
            lastWidgetsAt = now
        }

        // Throttled with something still unshown: come back once the window
        // opens, so the last steps of a walk are never left off screen.
        val stale = snapshot.steps != lastNotifiedSteps || snapshot.steps != lastWidgetSteps
        if (stale && !isCatchUpPosted) {
            isCatchUpPosted = true
            handler.postDelayed(catchUp, NOTIFICATION_MIN_INTERVAL_MS)
        }
    }

    private fun isDue(
        mode: Repaint,
        steps: Int,
        shownSteps: Int,
        shownAt: Long,
        minIntervalMs: Long,
        now: Long,
    ): Boolean = when (mode) {
        Repaint.ALWAYS -> true
        Repaint.IF_CHANGED -> steps != shownSteps
        Repaint.IF_CHANGED_THROTTLED -> steps != shownSteps && now - shownAt >= minIntervalMs
    }

    /** @return false when the system refused, e.g. a background start without an exemption. */
    private fun enterForeground(): Boolean = runCatching {
        val notification = StepNotifier.build(
            this,
            repository.snapshot(),
            repository.isLiveNotificationEnabled,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                StepNotifier.NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH,
            )
        } else {
            startForeground(StepNotifier.NOTIFICATION_ID, notification)
        }
        // Whatever the user swiped away is back on screen now.
        repository.isNotificationDismissed = false
    }.onFailure {
        Log.w(TAG, "Could not enter the foreground", it)
    }.isSuccess

    private fun post(block: () -> Unit) {
        if (isActive) handler.post { block() }
    }

    companion object {
        private const val TAG = "StepTracking"
        private const val ACTION_DAY_END = "com.purrweb.stepstep.DAY_END"

        /** Screen on: a near-live counter for whoever is looking. */
        private const val SCREEN_ON_LATENCY_US = 2_000_000

        /** Screen off: nobody is looking, so at most one batch every few minutes. */
        private const val SCREEN_OFF_LATENCY_US = 300_000_000

        private const val FLUSH_TIMEOUT_MS = 1_500L
        private const val NOTIFICATION_MIN_INTERVAL_MS = 5_000L
        private const val WIDGETS_MIN_INTERVAL_MS = 15_000L
        private const val DAY_END_WAKE_LOCK_MS = 10_000L

        @Volatile
        private var instance: StepTrackingService? = null

        /**
         * Starts the counter, or nudges the running one to re-read and
         * repaint — e.g. when the app is opened.
         *
         * @return false when it cannot run (no activity-recognition
         *   permission) or the system refused a background start.
         */
        fun start(context: Context): Boolean {
            val running = instance
            if (running != null) {
                running.post { running.flush { running.render(Repaint.ALWAYS) } }
                return true
            }
            return startService(context, null)
        }

        /** Called by the 23:59 alarm; brings the service back if it was killed. */
        fun finaliseDay(context: Context) {
            val running = instance
            if (running != null) {
                running.post { running.finaliseDay() }
            } else {
                startService(context, ACTION_DAY_END)
            }
        }

        /**
         * Flushes the sensor and repaints, then calls [onDone] on the
         * service thread.
         *
         * @return false when the service is not running, so the caller
         *   should read the sensor itself.
         */
        fun refresh(onDone: () -> Unit): Boolean {
            val running = instance ?: return false
            running.post {
                running.flush {
                    running.render(Repaint.IF_CHANGED)
                    onDone()
                }
            }
            return true
        }

        /**
         * Repaints the notification and widgets right away, e.g. after the
         * profile or the notification setting changed.
         *
         * @return false when the service is not running.
         */
        fun repaint(): Boolean {
            val running = instance ?: return false
            running.post { running.render(Repaint.ALWAYS) }
            return true
        }

        private fun startService(context: Context, action: String?): Boolean {
            if (!PermissionCoordinator.canCountSteps(context)) return false
            val intent = Intent(context, StepTrackingService::class.java).setAction(action)
            return runCatching { ContextCompat.startForegroundService(context, intent) }
                .onFailure { Log.w(TAG, "Could not start the step counter", it) }
                .isSuccess
        }
    }
}
