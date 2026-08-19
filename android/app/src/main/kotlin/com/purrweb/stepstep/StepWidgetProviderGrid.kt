package com.purrweb.stepstep

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.widget.RemoteViews
import kotlin.math.roundToInt

/**
 * Square-ish 2x2 widget: steps, goal, calories and distance over the same
 * fill background as [StepWidgetProviderBar] — see [FillRenderer].
 */
class StepWidgetProviderGrid : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { render(context, appWidgetManager, it) }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        render(context, appWidgetManager, appWidgetId)
    }

    companion object {
        private const val DEFAULT_WIDTH_DP = 180
        private const val DEFAULT_HEIGHT_DP = 180

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, StepWidgetProviderGrid::class.java),
            )
            ids.forEach { render(context, manager, it) }
        }

        private fun render(context: Context, manager: AppWidgetManager, widgetId: Int) {
            val snapshot = StepRepository(context).snapshot()
            val goalReached = snapshot.steps >= snapshot.goal

            val density = context.resources.displayMetrics.density
            val options = manager.getAppWidgetOptions(widgetId)
            val widthPx = (
                options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, DEFAULT_WIDTH_DP) *
                    density
                ).roundToInt()
            val heightPx = (
                options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, DEFAULT_HEIGHT_DP) *
                    density
                ).roundToInt()

            val fill = FillRenderer.render(
                widthPx = widthPx,
                heightPx = heightPx,
                cornerRadiusPx = context.resources.getDimension(R.dimen.widget_corner_radius),
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

            val views = RemoteViews(context.packageName, R.layout.widget_steps_grid).apply {
                setImageViewBitmap(R.id.widget_grid_fill, fill)
                setTextViewText(R.id.widget_grid_steps, Metrics.formatSteps(snapshot.steps))
                setTextViewText(
                    R.id.widget_grid_goal,
                    if (goalReached) "Цель выполнена"
                    else "Цель ${Metrics.formatSteps(snapshot.goal)}",
                )
                setTextViewText(
                    R.id.widget_grid_kcal,
                    "${snapshot.kcal.roundToInt()} ${context.getString(R.string.unit_kcal)}",
                )
                setTextViewText(
                    R.id.widget_grid_distance,
                    Metrics.formatDistance(snapshot.distanceKm),
                )
                setOnClickPendingIntent(R.id.widget_grid_root, openApp)
            }

            manager.updateAppWidget(widgetId, views)
        }
    }
}
