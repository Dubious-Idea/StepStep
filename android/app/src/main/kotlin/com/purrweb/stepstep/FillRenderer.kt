package com.purrweb.stepstep

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader

/**
 * Draws the "fill" progress background shared by the bar (2x1) and grid (2x2)
 * home-screen widgets: a rounded card that is solid black at 0% progress and
 * a full left-to-right accent gradient at 100%, wiping in between.
 *
 * Same reasoning as [RingRenderer]: `RemoteViews` cannot host a custom `View`
 * or a shader, so the background is rendered into a bitmap sized to the
 * widget's actual current dimensions and set as an `ImageView` behind the
 * stock text views `RemoteViews` can draw on top.
 */
object FillRenderer {

    private const val ACCENT_START = 0xFFA8FF3E.toInt()
    private const val ACCENT_MID = 0xFF22E8B4.toInt()
    private const val ACCENT_END = 0xFF4C7BFF.toInt()

    private const val GOLD = 0xFFFFC94A.toInt()
    private const val GOLD_LIGHT = 0xFFFFE9A8.toInt()
    private const val GOLD_DEEP = 0xFFFFB020.toInt()

    /** `brand_background` — the "completely black" 0% state. */
    private const val BASE = 0xFF08090C.toInt()

    private const val STROKE = 0xFF232733.toInt()
    private const val STROKE_WIDTH_PX = 2f

    /** How much of the fill's leading edge gets feathered back to black. */
    private const val EDGE_SOFTNESS_FRACTION = 0.06f

    /**
     * @param widthPx, heightPx  the widget's current on-screen size — read by
     *   the caller from `AppWidgetManager.getAppWidgetOptions` so the fill
     *   always spans the exact size the user resized it to.
     * @param progress  0f..1f
     */
    fun render(
        widthPx: Int,
        heightPx: Int,
        cornerRadiusPx: Float,
        progress: Float,
        goalReached: Boolean,
    ): Bitmap {
        val w = widthPx.coerceAtLeast(1)
        val h = heightPx.coerceAtLeast(1)
        val bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        val inset = STROKE_WIDTH_PX / 2f
        val bounds = RectF(inset, inset, w - inset, h - inset)

        val base = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = BASE }
        canvas.drawRoundRect(bounds, cornerRadiusPx, cornerRadiusPx, base)

        val fraction = progress.coerceIn(0f, 1f)
        if (fraction > 0f) {
            drawFill(canvas, bounds, cornerRadiusPx, fraction, goalReached)
        }

        val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = STROKE_WIDTH_PX
            color = STROKE
        }
        canvas.drawRoundRect(bounds, cornerRadiusPx, cornerRadiusPx, strokePaint)

        return bitmap
    }

    private fun drawFill(
        canvas: Canvas,
        bounds: RectF,
        cornerRadiusPx: Float,
        fraction: Float,
        goalReached: Boolean,
    ) {
        val fillWidth = bounds.width() * fraction

        canvas.save()
        canvas.clipRect(bounds.left, bounds.top, bounds.left + fillWidth, bounds.bottom)

        val colors = if (goalReached) {
            intArrayOf(GOLD, GOLD_LIGHT, GOLD_DEEP)
        } else {
            intArrayOf(ACCENT_START, ACCENT_MID, ACCENT_END)
        }
        val shader = LinearGradient(
            bounds.left,
            0f,
            bounds.right,
            0f,
            colors,
            null,
            Shader.TileMode.CLAMP,
        )
        val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.shader = shader }
        canvas.drawRoundRect(bounds, cornerRadiusPx, cornerRadiusPx, fillPaint)

        // Feather the wipe's leading edge back to black rather than cutting it
        // off with a hard vertical line — the area beyond is already BASE
        // from the first draw, so this just blends into it.
        if (fraction < 1f) {
            val edgeWidth = (bounds.width() * EDGE_SOFTNESS_FRACTION).coerceAtMost(fillWidth)
            val edgeShader = LinearGradient(
                bounds.left + fillWidth - edgeWidth,
                0f,
                bounds.left + fillWidth,
                0f,
                Color.TRANSPARENT,
                BASE,
                Shader.TileMode.CLAMP,
            )
            val edgePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.shader = edgeShader }
            canvas.drawRect(
                bounds.left + fillWidth - edgeWidth,
                bounds.top,
                bounds.left + fillWidth,
                bounds.bottom,
                edgePaint,
            )
        }

        canvas.restore()
    }
}
