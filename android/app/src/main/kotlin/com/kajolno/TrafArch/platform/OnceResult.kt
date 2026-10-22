package com.kajolno.TrafArch.platform

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

/** Commit a reply on the main looper, including cancellation racing a worker callback. */
internal class OnceResult(private val delegate: MethodChannel.Result) : MethodChannel.Result {
    private val completed = AtomicBoolean(false)
    private val main = Handler(Looper.getMainLooper())

    private fun reply(action: () -> Unit) {
        val deliver = Runnable { if (completed.compareAndSet(false, true)) action() }
        if (Looper.myLooper() == Looper.getMainLooper()) deliver.run() else main.post(deliver)
    }

    override fun success(result: Any?) = reply { delegate.success(result) }
    override fun error(code: String, message: String?, details: Any?) =
        reply { delegate.error(code, message, details) }
    override fun notImplemented() = reply { delegate.notImplemented() }
}
