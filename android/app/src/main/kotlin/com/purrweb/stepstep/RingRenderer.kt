package com.purrweb.stepstep

import android.graphics.Bitmap
import android.graphics.BlurMaskFilter
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.SweepGradient
import kotlin.math.cos
import kotlin.math.sin

/**
 * Draws the neon progress ring shared by the home-screen widget and the
 * ongoing notification.
 *
 * Rendered into a software bitmap because `RemoteViews` cannot host a custom
 * view — the host process (launcher / system UI) can only display images and
 * stock widgets. Keeping one renderer for both surfaces is what makes the
 * notification and the widget look like the same product.
 *
 * Colours mirror `lib/theme/tokens.dart`.
 */
object RingRenderer {

    private const val ACCENT_START = 0xFFA8FF3E.toInt()
    private const val ACCENT_MID = 0xFF22E8B4.toInt()
    private const val ACCENT_END = 0xFF4C7BFF.toInt()

    private const val GOLD = 0xFFFFC94A.toInt()
    private const val GOLD_LIGHT = 0xFFFFE9A8.toInt()
    private const val GOLD_DEEP = 0xFFFFB020.toInt()

    private const val TRACK = 0xFF232733.toInt()

    /** Progress starts at 12 o'clock and runs clockwise. */
    private const val START_ANGLE = -90f

    /**
     * A hairline of arc is always drawn so a zero-step ring still reads as
     * "ready" rather than broken.
     */
    private const val MIN_SWEEP_DEGREES = 2.5f

    /**
     * @param sizePx    side of the square bitmap
     * @param progress  0f..1f
     * @param goalReached switches the gradient to the reserved gold state
     */
    fun render(
        sizePx: Int,
        progress: Float,
        goalReached: Boolean,
        strokeWidthPx: Float = sizePx * 0.085f,
    ): Bitmap {
        val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        // Just enough room for the blur to fall off without clipping. Anything
        // more and the ring shrinks inside its own bitmap — at notification
        // size that is the difference between a ring and a smudge.
        val glowPadding = strokeWidthPx * 0.5f
        val inset = strokeWidthPx / 2f + glowPadding
        val bounds = RectF(inset, inset, sizePx - inset, sizePx - inset)
        val radius = bounds.width() / 2f
        val cx = bounds.centerX()
        val cy = bounds.centerY()

        drawTrack(canvas, bounds, strokeWidthPx)

        val sweep = MIN_SWEEP_DEGREES + progress.coerceIn(0f, 1f) *
            (360f - MIN_SWEEP_DEGREES)
        val shader = buildShader(cx, cy, goalReached)

        // Glow first, crisp arc on top — the blur has to sit behind the stroke
        // or the ring reads muddy instead of lit.
        val glow = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = strokeWidthPx * 1.05f
            strokeCap = Paint.Cap.ROUND
            this.shader = shader
            alpha = 120
            maskFilter = BlurMaskFilter(strokeWidthPx * 0.9f, BlurMaskFilter.Blur.NORMAL)
        }
        canvas.drawArc(bounds, START_ANGLE, sweep, false, glow)

        val arc = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = strokeWidthPx
            strokeCap = Paint.Cap.ROUND
            this.shader = shader
        }
        canvas.drawArc(bounds, START_ANGLE, sweep, false, arc)

        drawHead(canvas, cx, cy, radius, sweep, strokeWidthPx, goalReached)

        return bitmap
    }

    private fun drawTrack(canvas: Canvas, bounds: RectF, strokeWidthPx: Float) {
        val track = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = strokeWidthPx
            strokeCap = Paint.Cap.ROUND
            color = TRACK
        }
        canvas.drawCircle(bounds.centerX(), bounds.centerY(), bounds.width() / 2f, track)
    }

    private fun buildShader(
        cx: Float,
        cy: Float,
        goalReached: Boolean,
    ): SweepGradient {
        val colors = if (goalReached) {
            intArrayOf(GOLD, GOLD_LIGHT, GOLD_DEEP, GOLD)
        } else {
            intArrayOf(ACCENT_START, ACCENT_MID, ACCENT_END, ACCENT_START)
        }
        val stops = floatArrayOf(0f, 0.35f, 0.72f, 1f)

        return SweepGradient(cx, cy, colors, stops).apply {
            // SweepGradient starts at 3 o'clock; rotate so its first colour
            // lands on the arc's own starting point at 12 o'clock.
            setLocalMatrix(Matrix().apply { postRotate(START_ANGLE, cx, cy) })
        }
    }

    /** A bright dot riding the leading edge of the arc. */
    private fun drawHead(
        canvas: Canvas,
        cx: Float,
        cy: Float,
        radius: Float,
        sweep: Float,
        strokeWidthPx: Float,
        goalReached: Boolean,
    ) {
        val angleRad = Math.toRadians((START_ANGLE + sweep).toDouble())
        val hx = cx + radius * cos(angleRad).toFloat()
        val hy = cy + radius * sin(angleRad).toFloat()
        val headColor = if (goalReached) GOLD_LIGHT else headColorFor(sweep)

        val halo = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = headColor
            alpha = 150
            maskFilter = BlurMaskFilter(strokeWidthPx * 0.8f, BlurMaskFilter.Blur.NORMAL)
        }
        canvas.drawCircle(hx, hy, strokeWidthPx * 0.42f, halo)

        val core = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE }
        canvas.drawCircle(hx, hy, strokeWidthPx * 0.2f, core)
    }

    /** Approximates the gradient colour at the head so the halo matches it. */
    private fun headColorFor(sweep: Float): Int {
        val t = (sweep / 360f).coerceIn(0f, 1f)
        return when {
            t < 0.35f -> lerpColor(ACCENT_START, ACCENT_MID, t / 0.35f)
            t < 0.72f -> lerpColor(ACCENT_MID, ACCENT_END, (t - 0.35f) / 0.37f)
            else -> lerpColor(ACCENT_END, ACCENT_START, (t - 0.72f) / 0.28f)
        }
    }

    private fun lerpColor(from: Int, to: Int, t: Float): Int {
        val clamped = t.coerceIn(0f, 1f)
        fun mix(shift: Int): Int {
            val a = (from shr shift) and 0xFF
            val b = (to shr shift) and 0xFF
            return (a + (b - a) * clamped).toInt() and 0xFF
        }
        return Color.argb(0xFF, mix(16), mix(8), mix(0))
    }
}
