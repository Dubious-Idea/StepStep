package com.purrweb.stepstep

import android.content.Context

/**
 * Repaints every placed widget of every kind — the ring, the bar and the
 * grid. Callers that used to talk to [StepWidgetProvider] directly go
 * through here instead, so adding a new widget variant only means adding one
 * line here rather than hunting down every refresh call site.
 */
object Widgets {
    fun updateAll(context: Context) {
        StepWidgetProvider.updateAll(context)
        StepWidgetProviderBar.updateAll(context)
        StepWidgetProviderGrid.updateAll(context)
    }
}
