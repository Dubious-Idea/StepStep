package com.purrweb.stepstep

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * The whole reason a persistent foreground service is no longer needed: one
 * bounded sensor read, a repository update, and a repaint of the widgets and
 * the ongoing notification — then the process is free to go away until the
 * next scheduled run. [RefreshScheduler] is what decides when that is, both
 * for the periodic cadence and the once-a-day 23:59 finalisation.
 */
class StepRefreshWorker(
    context: Context,
    params: WorkerParameters,
) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val context = applicationContext
        val repository = StepRepository(context)

        readSensorOnce(context)?.let { raw -> repository.recordRawCounter(raw) }

        Widgets.updateAll(context)
        if (repository.isLiveNotificationEnabled) {
            // Channels persist once created, but this runs standalone with no
            // guarantee MainActivity (which normally creates it) has launched
            // in this process — cheap to make sure either way.
            StepNotifier.createChannel(context)
            StepNotifier.post(context, repository.snapshot())
        }

        Result.success()
    }

    /**
     * Registers for a single `TYPE_STEP_COUNTER` reading and blocks (this
     * runs on a background thread pool, not the main thread) until it
     * arrives or [SENSOR_READ_TIMEOUT_MS] passes — the sensor typically
     * reports its current cumulative value within milliseconds of
     * registration, so the timeout only matters on a device with no sensor
     * or a stuck driver.
     */
    private fun readSensorOnce(context: Context): Long? {
        val manager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        val sensor = manager.getDefaultSensor(Sensor.TYPE_STEP_COUNTER) ?: return null

        val latch = CountDownLatch(1)
        var raw: Long? = null

        val listener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                raw = event.values.firstOrNull()?.toLong()
                latch.countDown()
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
        }

        manager.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_FASTEST)
        latch.await(SENSOR_READ_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        manager.unregisterListener(listener)

        return raw
    }

    companion object {
        private const val SENSOR_READ_TIMEOUT_MS = 5_000L
    }
}
