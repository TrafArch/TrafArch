package com.kajolno.TrafArch.nfc

import android.app.Activity
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.nfc.tech.TagTechnology
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.kajolno.TrafArch.platform.OnceResult
import java.util.UUID

/**
 * Main looper owns sessions/replies/reader mode. The NFC worker owns all normal I/O.
 * A separate close worker interrupts blocked I/O; a serial retirement barrier runs
 * before any successor can connect, including a connect which finishes after abort.
 */
internal class NfcSessionController(private val activity: Activity) {
    private enum class State { WAITING, DISCOVERING, CONNECTED, METADATA_ONLY, CLOSED }

    private class Session(val id: String, val discovery: OnceResult) {
        val gate = Any()
        @Volatile var stopped = false
        var state = State.WAITING // Main looper only.
        var connection: NfcConnection? = null // Installed on the main looper only.
        val replies = linkedSetOf<OnceResult>() // Main looper only.
        val technologies = linkedSetOf<TagTechnology>() // Protected by gate; never do I/O under it.
    }

    private class SessionWork(val session: Session, private val action: () -> Unit) : Runnable {
        override fun run() { if (!session.stopped) action() }
    }

    private class Retirement {
        val waiters = mutableListOf<OnceResult>()
        var completed = false
        var timedOut = false
        var errors: List<String> = emptyList()
    }

    private val main = Handler(Looper.getMainLooper())
    private val io = NfcIoScheduler.io
    private val closer = NfcIoScheduler.closer
    private val metadata = TagMetadataReader()
    private var active: Session? = null
    private var foreground = false
    private var disposed = false
    private val usedIds = mutableSetOf<String>()
    private val retirements = linkedMapOf<String, Retirement>()
    private var lastRetirement: Pair<String, Retirement>? = null
    private val adapter: NfcAdapter? by lazy { NfcAdapter.getDefaultAdapter(activity) }

    fun start(requestedId: String?, result: OnceResult) {
        if (disposed) {
            result.error("NFC_STOPPED", "扫描已停止", null)
            return
        }
        val nfc = adapter
        if (nfc == null) {
            result.error("NFC_UNAVAILABLE", "当前设备没有 NFC", null)
            return
        }
        if (!nfc.isEnabled) {
            result.error("NFC_DISABLED", "请先打开系统 NFC", null)
            return
        }
        val id = requestedId ?: UUID.randomUUID().toString()
        if (!usedIds.add(id)) {
            result.error("STALE_SESSION", "NFC 会话已失效", mapOf("sessionId" to id))
            return
        }
        active?.let { retire(it) }
        val session = Session(id, result)
        active = session
        if (foreground) enableDiscovery(session)
    }

    private fun enableDiscovery(session: Session) {
        if (disposed || active !== session || session.state != State.WAITING) return
        try {
            // This callback captures the registering session; it never claims a newer pending reply.
            adapter?.enableReaderMode(activity, { tag ->
                main.post { discovered(session, tag) }
            }, READER_FLAGS, null)
        } catch (error: Exception) {
            session.discovery.error("NFC_SCAN_FAILED", error.message ?: "无法启动 NFC 扫描", details(session, error))
            retire(session)
        }
    }

    private fun discovered(session: Session, tag: Tag) {
        if (disposed || !foreground || active !== session || session.state != State.WAITING) return
        session.state = State.DISCOVERING
        io.execute(SessionWork(session) {
            try {
                val discovery = metadata.read(tag, access(session))
                main.post {
                    if (active === session && !session.stopped) {
                        session.connection = discovery.connection
                        session.state = if (discovery.connection == null) State.METADATA_ONLY else State.CONNECTED
                        discovery.metadata["sessionId"] = session.id
                        session.discovery.success(discovery.metadata)
                    }
                }
            } catch (error: Exception) {
                main.post {
                    if (active === session && !session.stopped) {
                        session.discovery.error("NFC_SCAN_FAILED", error.message, details(session, error))
                        retire(session)
                    }
                }
            }
        })
    }

    private fun access(session: Session) = object : SessionTagAccess {
        override fun checkActive() { if (session.stopped) throw NfcSessionClosed() }
        override fun own(technology: TagTechnology) {
            synchronized(session.gate) {
                checkActive()
                session.technologies.add(technology)
            }
        }
        override fun release(technology: TagTechnology) {
            // Worker only. Keep a failed close registered for the retirement sweep.
            technology.close()
            synchronized(session.gate) { session.technologies.remove(technology) }
        }
    }

    fun transceive(id: String?, felica: Boolean, bytes: ByteArray, result: OnceResult) {
        val session = active
        if (id != null && (session == null || session.id != id)) {
            stale(id, result)
            return
        }
        val connection = session?.connection
        if (session == null || session.stopped || connection == null || connection.isFelica != felica) {
            disconnected(felica, result)
            return
        }
        // Bound accepted work, including the running command and replies waiting for the main looper.
        if (session.replies.size >= MAX_PENDING_COMMANDS) {
            result.error("NFC_BUSY", "NFC 指令队列已满", mapOf("sessionId" to session.id))
            return
        }
        session.replies.add(result)
        // Capture BOTH the session and its immutable connection at acceptance, including legacy calls.
        io.execute(SessionWork(session) {
            try {
                if (!connection.isConnected) {
                    complete(session, result) { disconnected(felica, result) }
                } else {
                    val response = connection.transceive(bytes)
                    // ByteArray preserves Dart Uint8List (unsigned bytes), including SW1/SW2 and LEN.
                    complete(session, result) { result.success(response) }
                }
            } catch (error: Exception) {
                complete(session, result) {
                    result.error("TRANSCEIVE_FAILED", error.message, details(session, error))
                }
            }
        })
    }

    private fun complete(session: Session, result: OnceResult, reply: () -> Unit) {
        main.post {
            if (session.replies.remove(result) && active === session && !session.stopped) reply()
        }
    }

    fun stop(id: String?, result: OnceResult) {
        val session = active
        if (session != null && (id == null || session.id == id)) {
            val retirement = retire(session)
            awaitClose(session.id, retirement, result)
            return
        }
        val previous = if (id == null) lastRetirement else retirements[id]?.let { id to it }
        if (previous != null) {
            awaitClose(previous.first, previous.second, result)
        } else if (id == null) {
            result.success(null)
        } else {
            stale(id, result)
        }
    }

    private fun awaitClose(id: String, retirement: Retirement, result: OnceResult) {
        if (retirement.completed || retirement.timedOut) closeReply(id, retirement, result)
        else retirement.waiters.add(result)
    }

    private fun retire(session: Session): Retirement {
        retirements[session.id]?.let { return it }
        val retirement = Retirement()
        retirements[session.id] = retirement
        lastRetirement = session.id to retirement
        main.postDelayed({
            if (!retirement.completed) {
                retirement.timedOut = true
                retirement.waiters.forEach { closeReply(session.id, retirement, it) }
                retirement.waiters.clear()
            }
        }, CLOSE_ACK_TIMEOUT_MS)
        val toAbort = synchronized(session.gate) {
            session.stopped = true
            session.technologies.toList()
        }
        session.state = State.CLOSED
        session.connection = null
        val controlErrors = mutableListOf<String>()
        if (active === session) {
            active = null // Detach BEFORE disabling discovery or scheduling blocking closes.
            try { adapter?.disableReaderMode(activity) } catch (error: Exception) {
                controlErrors.add(error.message ?: error.javaClass.simpleName)
            }
        }
        session.discovery.error("NFC_STOPPED", "扫描已停止", null)
        session.replies.forEach { it.error("NFC_STOPPED", "扫描已停止", null) }
        session.replies.clear()
        // Remove queued commands/connect work, but never another session's retirement barrier.
        io.queue.toList().forEach { task ->
            if (task is SessionWork && task.session === session) io.remove(task)
        }
        val abort = closer.submit {
            toAbort.forEach { technology ->
                try { technology.close() } catch (error: Exception) {
                    Log.w("NFC", "Abort close failed: ${error.message}")
                }
            }
        }
        // FIFO: no successor connect may run until BOTH abort and the old worker have finished.
        io.execute {
            val errors = controlErrors.toMutableList()
            try { abort.get() } catch (error: Exception) {
                errors.add(error.message ?: error.javaClass.simpleName)
            }
            val remaining = synchronized(session.gate) { session.technologies.toList() }
            remaining.forEach { technology ->
                try { technology.close() } catch (error: Exception) {
                    errors.add(error.message ?: error.javaClass.simpleName)
                }
            }
            synchronized(session.gate) { session.technologies.clear() }
            main.post {
                retirement.errors = errors
                retirement.completed = true
                retirement.waiters.forEach { closeReply(session.id, retirement, it) }
                retirement.waiters.clear()
            }
        }
        return retirement
    }

    private fun closeReply(id: String, retirement: Retirement, result: OnceResult) {
        if (!retirement.completed) {
            result.error("NFC_CLOSE_FAILED", "NFC 连接关闭失败", mapOf(
                "sessionId" to id, "closing" to true, "reason" to "close_timeout",
            ))
        } else if (retirement.errors.isEmpty()) result.success(null) else {
            result.error("NFC_CLOSE_FAILED", "NFC 连接关闭失败", mapOf(
                "sessionId" to id, "closing" to false, "errors" to retirement.errors,
            ))
        }
    }

    fun onResume() {
        foreground = true
        active?.let { if (it.state == State.WAITING) enableDiscovery(it) }
    }

    fun onPause() {
        foreground = false
        // Keep DISCOVERING / CONNECTED reads alive as before; only suspend waiting discovery.
        if (active?.state == State.WAITING) {
            try { adapter?.disableReaderMode(activity) } catch (error: Exception) {
                Log.w("NFC", "Failed to pause reader mode: ${error.message}")
            }
        }
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        active?.let { retire(it) }
        // Finish channel replies before the messenger is detached. Physical
        // retirement still owns the barrier and must not be reported as success.
        retirements.forEach { (id, retirement) ->
            retirement.waiters.forEach { result ->
                result.error("NFC_STOPPED", "NFC 引擎已关闭", mapOf(
                    "sessionId" to id, "closing" to !retirement.completed,
                    "reason" to "engine_disposed",
                ))
            }
            retirement.waiters.clear()
        }
        // The shared scheduler drains retirement barriers and expires idle workers itself.
    }

    private fun stale(id: String, result: OnceResult) = result.error(
        "STALE_SESSION", "NFC 会话已失效", mapOf("sessionId" to id, "activeSessionId" to active?.id),
    )

    private fun disconnected(felica: Boolean, result: OnceResult) = result.error(
        if (felica) "FELICA_NOT_CONNECTED" else "TAG_NOT_CONNECTED",
        if (felica) "NFC-F 未连接" else "ISO-DEP 未连接", null,
    )

    private fun details(session: Session, error: Exception) = mapOf(
        "sessionId" to session.id, "exception" to error.javaClass.name,
    )

    companion object {
        private const val MAX_PENDING_COMMANDS = 64
        private const val CLOSE_ACK_TIMEOUT_MS = 10_000L
        private const val READER_FLAGS = NfcAdapter.FLAG_READER_NFC_A or
            NfcAdapter.FLAG_READER_NFC_B or NfcAdapter.FLAG_READER_NFC_F or
            NfcAdapter.FLAG_READER_NFC_V or NfcAdapter.FLAG_READER_SKIP_NDEF_CHECK
    }
}
