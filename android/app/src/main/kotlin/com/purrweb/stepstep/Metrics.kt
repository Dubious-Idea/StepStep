package com.purrweb.stepstep

import java.util.Locale
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Mirror of `lib/services/metrics.dart`.
 *
 * The widget and the ongoing notification are rendered by this process while
 * the Flutter engine may not be running at all, so the numbers they show have
 * to be computed natively. Any change to the Dart formulas must be applied
 * here too — the constants below are deliberately identical, and
 * `test/metrics_test.dart` pins the reference value both sides must produce
 * (10 000 steps / 175 cm / 75 kg / 100 active min => ~271.7 kcal).
 */
object Metrics {
    const val STRIDE_TO_HEIGHT_RATIO = 0.414
    const val MIN_SPEED_M_PER_MIN = 40.0
    const val MAX_SPEED_M_PER_MIN = 150.0
    const val FALLBACK_CADENCE_STEPS_PER_MIN = 100.0

    private const val KCAL_PER_MIN_DIVISOR = 200.0
    private const val ACSM_HORIZONTAL_VO2_FACTOR = 0.1

    private const val MIN_HEIGHT_CM = 100
    private const val MAX_HEIGHT_CM = 250

    fun strideMeters(heightCm: Int): Double =
        heightCm.coerceIn(MIN_HEIGHT_CM, MAX_HEIGHT_CM) * STRIDE_TO_HEIGHT_RATIO / 100.0

    fun distanceKm(steps: Int, heightCm: Int): Double =
        if (steps <= 0) 0.0 else steps * strideMeters(heightCm) / 1000.0

    fun activeKcal(steps: Int, heightCm: Int, weightKg: Double, activeMinutes: Double): Double {
        if (steps <= 0) return 0.0

        val minutes = if (activeMinutes > 0) activeMinutes
        else steps / FALLBACK_CADENCE_STEPS_PER_MIN
        val metres = steps * strideMeters(heightCm)
        val speed = (metres / minutes).coerceIn(MIN_SPEED_M_PER_MIN, MAX_SPEED_M_PER_MIN)
        val effectiveMinutes = metres / speed

        val netVo2 = ACSM_HORIZONTAL_VO2_FACTOR * speed
        val kcalPerMin = netVo2 * weightKg / KCAL_PER_MIN_DIVISOR
        return kcalPerMin * effectiveMinutes
    }

    fun goalProgress(steps: Int, goal: Int): Float =
        if (goal <= 0) 1f else min(1f, max(0f, steps.toFloat() / goal))

    /** `8432` -> `8 432`, matching `formatSteps` in Dart (narrow no-break space). */
    fun formatSteps(steps: Int): String {
        val digits = Math.abs(steps).toString()
        val sb = StringBuilder(if (steps < 0) "-" else "")
        for (i in digits.indices) {
            if (i > 0 && (digits.length - i) % 3 == 0) sb.append(' ')
            sb.append(digits[i])
        }
        return sb.toString()
    }

    /**
     * Locale.US on purpose: Dart's `toStringAsFixed` always uses a dot, and the
     * widget sitting next to the app showing `6,10 км` against `6.10 км` would
     * look like two different numbers.
     */
    fun formatDistance(km: Double): String =
        if (km < 1) "${(km * 1000).roundToInt()} м"
        else String.format(Locale.US, if (km < 10) "%.2f км" else "%.1f км", km)
}
