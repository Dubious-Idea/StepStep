package com.purrweb.stepstep

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import kotlin.math.roundToInt

/**
 * Home-screen widget showing the same neon ring as the notification.
 *
 * It renders straight from [StepRepository], so it stays correct even when
 * [StepService] has been killed — it just stops refreshing until the service
 * or the periodic update brings it back.
 */
class StepWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { render(context, appWidgetManager, it) }
    }

    override fun onEnabled(context: Context) {
        // First widget placed — make sure something is keeping it fresh.
        if (StepRepository(context).isOnboarded) StepService.start(context)
    }

    companion object {
        private const val RING_BITMAP_PX = 320

        /** Repaints every placed widget. Safe to call from any process. */
        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, StepWidgetProvider::class.java),
            )
            ids.forEach { render(context, manager, it) }
        }

        private fun render(
            context: Context,
            manager: AppWidgetManager,
            widgetId: Int,
        ) {
            val snapshot = StepRepository(context).snapshot()
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

            val views = RemoteViews(context.packageName, R.layout.widget_steps).apply {
                setImageViewBitmap(R.id.widget_ring, ring)
                setTextViewText(R.id.widget_steps, Metrics.formatSteps(snapshot.steps))
                setTextViewText(
                    R.id.widget_percent,
                    "${(snapshot.progress * 100).roundToInt()}%",
                )
                setTextViewText(
                    R.id.widget_goal,
                    if (goalReached) "Цель выполнена"
                    else "Цель ${Metrics.formatSteps(snapshot.goal)}",
                )
                setTextViewText(R.id.widget_kcal, "${snapshot.kcal.roundToInt()}")
                setTextViewText(
                    R.id.widget_distance,
                    Metrics.formatDistance(snapshot.distanceKm),
                )
                setOnClickPendingIntent(R.id.widget_root, openApp)
            }

            manager.updateAppWidget(widgetId, views)
        }
    }
}
