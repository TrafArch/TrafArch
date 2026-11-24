package com.kajolno.TrafArch.nfc

import android.nfc.NfcAdapter
import io.flutter.plugin.common.EventChannel

/** Main-looper adapter snapshots and power changes for both reader owners. */
internal class NfcAdapterStatusStream(
    private val readEnabled: () -> Boolean?,
    private val updateReader: (Boolean) -> Unit,
) : EventChannel.StreamHandler {
    private var sink: EventChannel.EventSink? = null
    private var lastStatus: String? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        // Reconcile missed broadcasts, then replay even if the value did not change.
        sink = null
        refresh()
        sink = events
        events.success(lastStatus)
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    fun refresh() {
        update(readEnabled())
    }

    fun onAdapterState(state: Int) {
        when (state) {
            NfcAdapter.STATE_ON -> update(true)
            NfcAdapter.STATE_OFF, NfcAdapter.STATE_TURNING_OFF, NfcAdapter.STATE_TURNING_ON -> update(false)
            else -> refresh()
        }
    }

    private fun update(enabled: Boolean?) {
        val status = when (enabled) {
            true -> "enabled"
            false -> "disabled"
            null -> "unavailable"
        }
        if (status == lastStatus) return
        lastStatus = status
        sink?.success(status)
        updateReader(enabled == true)
    }
}
