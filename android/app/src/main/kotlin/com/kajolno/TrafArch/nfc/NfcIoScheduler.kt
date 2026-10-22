package com.kajolno.TrafArch.nfc

import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

/**
 * Process-wide ordering also protects Activity/engine replacement: an old Activity's
 * final close must finish before its replacement connects. Idle workers expire;
 * disposing a controller must not shut down another controller's scheduler.
 */
internal object NfcIoScheduler {
    val io = worker("TrafArch-NFC-IO")
    val closer = worker("TrafArch-NFC-close")

    private fun worker(name: String) = ThreadPoolExecutor(
        1, 1, 30L, TimeUnit.SECONDS, LinkedBlockingQueue<Runnable>(),
        { runnable -> Thread(runnable, name) },
    ).apply { allowCoreThreadTimeOut(true) }
}
