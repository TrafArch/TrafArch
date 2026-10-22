package com.kajolno.TrafArch.nfc

import android.nfc.tech.IsoDep
import android.nfc.tech.TagTechnology
import java.io.IOException

/** A captured, immutable technology port. Only the session controller owns its lifetime. */
internal interface NfcConnection {
    val isFelica: Boolean
    val isConnected: Boolean
    fun transceive(bytes: ByteArray): ByteArray
}

internal class IsoDepConnection(private val technology: IsoDep) : NfcConnection {
    override val isFelica = false
    override val isConnected get() = technology.isConnected
    override fun transceive(bytes: ByteArray): ByteArray = technology.transceive(bytes)
}

/** Used only on the serial NFC worker; own() registers a handle BEFORE connect(). */
internal interface SessionTagAccess {
    fun checkActive()
    fun own(technology: TagTechnology)
    fun release(technology: TagTechnology)
}

internal class NfcSessionClosed : IOException("扫描已停止")

internal data class TagDiscovery(
    val metadata: MutableMap<String, Any?>,
    val connection: NfcConnection?,
)
