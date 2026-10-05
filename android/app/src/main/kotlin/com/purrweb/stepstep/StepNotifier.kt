package com.purrweb.stepstep

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import kotlin.math.roundToInt

/**
 * Builds and posts the notification [StepTrackingService] runs under.
 *
 * A foreground service must show *a* notification, so there are two: the
 * lock-screen one with the ring (the reason the app has a notification at
 * all), and a collapsed one on its own quiet channel for when the user turns
 * the lock-screen display off in the profile. Counting continues either way.
 */
object StepNotifier {
    const val CHANNEL_ID = "steps_live"
    const val QUIET_CHANNEL_ID = "steps_quiet"
    const val NOTIFICATION_ID = 1001

    private const val RING_BITMAP_PX = 192
    private const val DISMISS_REQUEST_CODE = 4713

    private const val ACCENT = 0xFF22E8B4.toInt()
    private const val GOLD = 0xFFFFC94A.toInt()

    fun createChannels(context: Context) {
        val live = NotificationChannel(
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
        val quiet = NotificationChannel(
            QUIET_CHANNEL_ID,
            "Фоновый подсчёт",
            // MIN: no status-bar icon, collapsed at the bottom of the shade.
            NotificationManager.IMPORTANCE_MIN,
        ).apply {
            description = "Свёрнутое уведомление, пока шаги на экране блокировки выключены"
            setShowBadge(false)
            lockscreenVisibility = Notification.VISIBILITY_SECRET
            enableVibration(false)
            setSound(null, null)
        }
        notificationManager(context).createNotificationChannels(listOf(live, quiet))
    }

    /** Posts (or refreshes) the notification from the current snapshot. */
    fun post(context: Context, snapshot: StepRepository.Snapshot, live: Boolean) {
        notificationManager(context).notify(NOTIFICATION_ID, build(context, snapshot, live))
    }

    /**
     * @param live true for the lock-screen notification with the ring, false
     *   for the collapsed one on [QUIET_CHANNEL_ID].
     */
    fun build(context: Context, snapshot: StepRepository.Snapshot, live: Boolean): Notification =
        if (live) buildLive(context, snapshot) else buildQuiet(context, snapshot)

    private fun buildLive(context: Context, snapshot: StepRepository.Snapshot): Notification {
        val goalReached = snapshot.steps >= snapshot.goal
        val ring = RingRenderer.render(
            sizePx = RING_BITMAP_PX,
            progress = snapshot.progress,
            goalReached = goalReached,
        )

        val collapsed = RemoteViews(context.packageName, R.layout.notification_steps).apply {
            setImageViewBitmap(R.id.notification_ring, ring)
            setTextViewText(R.id.notification_steps, Metrics.formatSteps(snapshot.steps))
            setTextViewText(
                R.id.notification_summary,
                summaryLine(snapshot, goalReached),
            )
        }

        val expanded =
            RemoteViews(context.packageName, R.layout.notification_steps_expanded).apply {
                setImageViewBitmap(R.id.notification_ring, ring)
                setTextViewText(R.id.notification_steps, Metrics.formatSteps(snapshot.steps))
                setTextViewText(
                    R.id.notification_summary,
                    summaryLine(snapshot, goalReached),
                )
                setTextViewText(R.id.notification_kcal, "${snapshot.kcal.roundToInt()}")
                setTextViewText(
                    R.id.notification_distance,
                    Metrics.formatDistance(snapshot.distanceKm),
                )
                setTextViewText(
                    R.id.notification_goal,
                    "${(snapshot.progress * 100).roundToInt()}%",
                )
            }

        return NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_steps)
            .setContentTitle(Metrics.formatSteps(snapshot.steps))
            .setContentText(summaryLine(snapshot, goalReached))
            // No setLargeIcon: DecoratedCustomViewStyle renders the large icon
            // itself, next to a custom view that already draws the ring, so
            // setting both puts two rings on the same row.
            .setCustomContentView(collapsed)
            .setCustomBigContentView(expanded)
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .setContentIntent(openApp(context))
            .setDeleteIntent(dismissed(context))
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
            // Android 12+ otherwise holds a new foreground-service
            // notification back for up to 10 seconds; the ring is the whole
            // point, so show it straight away.
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    private fun buildQuiet(context: Context, snapshot: StepRepository.Snapshot): Notification =
        NotificationCompat.Builder(context, QUIET_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_steps)
            .setContentTitle("Шаги сегодня: ${Metrics.formatSteps(snapshot.steps)}")
            .setContentText("Подсчёт идёт в фоне")
            .setContentIntent(openApp(context))
            .setDeleteIntent(dismissed(context))
            .setOngoing(true)
            .setSilent(true)
            .setShowWhen(false)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .build()

    private fun openApp(context: Context): PendingIntent = PendingIntent.getActivity(
        context,
        0,
        Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        },
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    /**
     * Fires only when the user swipes the notification away, never when the
     * app replaces it — see [StepRepository.isNotificationDismissed].
     */
    private fun dismissed(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context,
        DISMISS_REQUEST_CODE,
        Intent(context, StepRefreshReceiver::class.java)
            .setAction(StepRefreshReceiver.ACTION_NOTIFICATION_DISMISSED),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

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

    private fun notificationManager(context: Context): NotificationManager =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
}
