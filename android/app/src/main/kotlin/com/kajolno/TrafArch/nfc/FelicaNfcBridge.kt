package com.kajolno.TrafArch.nfc

import android.nfc.tech.NfcF
import java.io.IOException

/** Complete LEN-prefixed frames, unchanged. The captured handle never switches sessions. */
internal class FelicaNfcBridge(private val technology: NfcF) : NfcConnection {
    override val isFelica = true
    override val isConnected get() = technology.isConnected

    // No monitor is held during I/O: the controller can abort via close on another worker.
    override fun transceive(bytes: ByteArray): ByteArray {
        if (!technology.isConnected) throw IOException("NFC-F 连接已断开")
        if (bytes.isEmpty()) throw IOException("FeliCa 帧为空")
        return technology.transceive(bytes)
    }
}
