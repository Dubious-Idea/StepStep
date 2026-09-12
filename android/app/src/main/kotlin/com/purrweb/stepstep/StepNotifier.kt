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
 * Builds and posts the ongoing lock-screen notification.
 *
 * Used to live inside `StepService`, which kept itself alive purely to own
 * this notification. Now it is posted by whatever briefly-running component
 * last read the sensor — [StepRefreshWorker] on a schedule, or
 * [MainActivity] right after the user opens the app or changes a setting —
 * and stays on screen exactly as before between those reads, since an
 * "ongoing" notification's dismiss-resistance is a property of the
 * notification itself, not of a service keeping it posted.
 */
object StepNotifier {
    const val CHANNEL_ID = "steps_live"
    const val NOTIFICATION_ID = 1001

    private const val RING_BITMAP_PX = 192

    private const val ACCENT = 0xFF22E8B4.toInt()
    private const val GOLD = 0xFFFFC94A.toInt()

    fun createChannel(context: Context) {
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
        notificationManager(context).createNotificationChannel(channel)
    }

    /** Posts (or refreshes) the ongoing notification from the current snapshot. */
    fun post(context: Context, snapshot: StepRepository.Snapshot) {
        notificationManager(context).notify(NOTIFICATION_ID, build(context, snapshot))
    }

    fun cancel(context: Context) {
        notificationManager(context).cancel(NOTIFICATION_ID)
    }

    private fun build(context: Context, snapshot: StepRepository.Snapshot): Notification {
        val goalReached = snapshot.steps >= snapshot.goal
        val ring = RingRenderer.render(
            sizePx = RING_BITMAP_PX,
            progress = snapshot.progress,
            goalReached = goalReached,
        )

        val openApp = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
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

    private fun notificationManager(context: Context): NotificationManager =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
}
