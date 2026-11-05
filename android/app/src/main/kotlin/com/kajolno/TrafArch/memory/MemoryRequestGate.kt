package com.kajolno.TrafArch.memory

/** All calls are serialized on the receiver's handler. Each request owns its reply. */
internal class MemoryRequestGate(
    private val schedule: (Long, () -> Unit) -> Unit,
    private val dispatch: (Boolean, (Boolean) -> Unit) -> Unit,
) {
    private val pending = mutableSetOf<Any>()

    fun receive(key: Any, kill: Boolean, reply: (Boolean, String) -> Unit) {
        if (!pending.add(key)) return // Duplicate delivery of the same outstanding notification.
        var finished = false
        fun finish(success: Boolean, message: String) {
            if (finished) return
            finished = true
            pending.remove(key)
            reply(success, message)
        }
        schedule(2400L) { finish(false, "processing timeout") }
        try {
            dispatch(kill) { success -> finish(success, if (success) "completed" else "incomplete") }
        } catch (_: Exception) {
            finish(false, "handler unavailable")
        }
    }
}
