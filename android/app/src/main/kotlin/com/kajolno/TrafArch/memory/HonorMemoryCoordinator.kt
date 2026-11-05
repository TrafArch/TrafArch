package com.kajolno.TrafArch.memory

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Looper
import android.os.Parcel
import android.os.SystemClock
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/** Process-owned receiver; it never retains an Activity. No polling or keep-alive service. */
internal class HonorMemoryCoordinator(context: Context) {
    private val application = context.applicationContext
    private val main = Handler(Looper.getMainLooper())
    private val worker = Handler(HandlerThread("TrafArch-memory").apply { start() }.looper)
    private val storage = Executors.newSingleThreadExecutor { Thread(it, "TrafArch-recovery") }
    // Binder calls cannot occupy the deadline handler, even if a remote misbehaves.
    private val replies = Executors.newFixedThreadPool(2) { Thread(it, "TrafArch-memory-reply") }
    private val recovery = RecoveryFile(application.noBackupFilesDir)
    private var channel: MethodChannel? = null // Main thread only.
    private var engine: FlutterEngine? = null
    private val gate = MemoryRequestGate(
        schedule = { delay, action -> worker.postDelayed({ action() }, delay) },
        dispatch = { kill, complete ->
            val acceptedAt = SystemClock.uptimeMillis()
            val expiresAtMillis = System.currentTimeMillis() + 2200L
            main.post {
                // A blocked UI may resume after the system deadline. Such a
                // stale notification must not interrupt a later user read.
                if (SystemClock.uptimeMillis() - acceptedAt >= 2200L) {
                    worker.post { complete(false) }
                    return@post
                }
                val target = channel
                if (target == null) {
                    worker.post { complete(false) }
                } else {
                    // Let Flutter's built-in cache/native memory handling participate too.
                    try {
                        engine?.systemChannel?.sendMemoryPressureWarning()
                        target.invokeMethod("onMemoryPressure", mapOf(
                            "kill" to kill, "expiresAtMillis" to expiresAtMillis,
                        ), object : MethodChannel.Result {
                            override fun success(result: Any?) { worker.post { complete(result == true) } }
                            override fun error(code: String, message: String?, details: Any?) { worker.post { complete(false) } }
                            override fun notImplemented() { worker.post { complete(false) } }
                        })
                    } catch (_: RuntimeException) {
                        worker.post { complete(false) }
                    }
                }
            }
        },
    )

    init {
        val filter = IntentFilter(TRIM).apply { addAction(KILL) }
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                try {
                    val kill = when (intent.action) { TRIM -> false; KILL -> true; else -> return }
                    val common = intent.getBundleExtra("common") ?: return
                    @Suppress("DEPRECATION")
                    val type = common.get("notifyType") as? Int ?: return
                    @Suppress("DEPRECATION")
                    val id = common.get("notifyId") as? Int ?: return
                    if (type != 1000 && type != 2000) return
                    val callback = common.getBinder("callback") ?: return
                    if (!callback.isBinderAlive) return
                    // Exported as required by HONOR. Payload validation is not
                    // sender authentication: KILL only saves locally, never exits.
                    val key = Triple(type, id, callback)
                    gate.receive(key, kill) { success, message ->
                        replies.execute { reply(callback, type, id, success, message) }
                    }
                } catch (_: RuntimeException) {
                    // Malformed parcelables from an exported receiver must not crash the app.
                }
            }
        }
        if (Build.VERSION.SDK_INT >= 33) {
            application.registerReceiver(receiver, filter, null, worker, Context.RECEIVER_EXPORTED)
        } else {
            application.registerReceiver(receiver, filter, null, worker)
        }
    }

    fun attach(flutterEngine: FlutterEngine) {
        channel?.setMethodCallHandler(null)
        engine = flutterEngine
        val attached = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "transit_card_analyzer/memory")
        channel = attached
        attached.setMethodCallHandler { call, result ->
            if (call.method !in setOf("readRecovery", "writeRecovery", "clearRecovery")) {
                result.notImplemented()
            } else {
                val content = call.argument<String>("content")
                storage.execute {
                    try {
                        val value = when (call.method) {
                            "readRecovery" -> recovery.read()
                            "writeRecovery" -> { recovery.write(requireNotNull(content)); null }
                            else -> { recovery.clear(); null }
                        }
                        main.post { result.success(value) }
                    } catch (_: Exception) {
                        main.post { result.error("RECOVERY_IO_FAILED", "现场恢复文件读写失败", null) }
                    }
                }
            }
        }
    }

    fun detach(flutterEngine: FlutterEngine) {
        if (engine !== flutterEngine) return
        channel?.setMethodCallHandler(null)
        channel = null
        engine = null
    }

    private fun reply(remote: IBinder, type: Int, id: Int, success: Boolean, message: String) {
        val data = Parcel.obtain()
        try {
            data.writeInt(type)
            data.writeInt(id)
            data.writeInt(if (success) 0 else 1)
            data.writeBundle(Bundle().apply { putString("reply", message) })
            // A one-way transaction has no reply parcel / readException handshake.
            remote.transact(IBinder.FIRST_CALL_TRANSACTION, data, null, IBinder.FLAG_ONEWAY)
        } catch (_: Exception) {
            // The system may have already killed the remote; never expose card data in logs.
        } finally { data.recycle() }
    }

    companion object {
        const val TRIM = "itgsa.intent.action.TRIM"
        const val KILL = "itgsa.intent.action.KILL"
    }
}
