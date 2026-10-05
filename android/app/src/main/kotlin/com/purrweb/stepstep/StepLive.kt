package com.purrweb.stepstep

import java.util.concurrent.CopyOnWriteArraySet

/**
 * Fan-out of fresh snapshots from [StepTrackingService] to whoever is
 * watching — in practice the open app, through [MainActivity]'s event
 * channel, so the ring grows while you walk instead of only on resume.
 *
 * Listeners are called on the service's thread; hop to the main thread
 * before touching anything that cares.
 */
object StepLive {
    private val listeners = CopyOnWriteArraySet<(StepRepository.Snapshot) -> Unit>()

    fun add(listener: (StepRepository.Snapshot) -> Unit) {
        listeners += listener
    }

    fun remove(listener: (StepRepository.Snapshot) -> Unit) {
        listeners -= listener
    }

    /** Builds the snapshot only when someone is actually listening. */
    fun publish(snapshot: () -> StepRepository.Snapshot) {
        if (listeners.isEmpty()) return
        val current = snapshot()
        listeners.forEach { it(current) }
    }
}
