package com.kajolno.TrafArch.nfc

import android.nfc.NfcAdapter
import io.flutter.plugin.common.EventChannel
import org.junit.Assert.assertEquals
import org.junit.Test

class NfcAdapterStatusStreamTest {
    private class Sink : EventChannel.EventSink {
        val events = mutableListOf<Any?>()
        override fun success(event: Any?) { events.add(event) }
        override fun error(code: String, message: String?, details: Any?) = error(code)
        override fun endOfStream() = Unit
    }

    @Test
    fun quickSettingsStopsWaitingOnTurningOffAndAllowsReadingOnlyWhenFullyOn() {
        val readerEnabled = mutableListOf<Boolean>()
        val stream = NfcAdapterStatusStream({ true }, { readerEnabled.add(it) })
        val sink = Sink()
        stream.onListen(null, sink)
        stream.onAdapterState(NfcAdapter.STATE_TURNING_OFF)
        stream.onAdapterState(NfcAdapter.STATE_OFF)
        stream.onAdapterState(NfcAdapter.STATE_TURNING_ON)
        stream.onAdapterState(NfcAdapter.STATE_ON)
        assertEquals(listOf("enabled", "disabled", "enabled"), sink.events)
        assertEquals(listOf(true, false, true), readerEnabled)
    }

    @Test
    fun nativeReaderObservesPowerEvenWithoutDartListenerAndNewListenerGetsLiveSnapshot() {
        var enabled: Boolean? = true
        val readerEnabled = mutableListOf<Boolean>()
        val stream = NfcAdapterStatusStream({ enabled }, { readerEnabled.add(it) })
        val first = Sink()
        stream.onListen(null, first)
        stream.onCancel(null)
        stream.onAdapterState(NfcAdapter.STATE_OFF)
        assertEquals(listOf(true, false), readerEnabled)
        assertEquals(listOf("enabled"), first.events)

        enabled = false
        val second = Sink()
        stream.onListen(null, second)
        enabled = true
        stream.refresh()
        assertEquals(listOf("disabled", "enabled"), second.events)
        assertEquals(listOf(true, false, true), readerEnabled)
    }

    @Test
    fun deviceWithoutAdapterReportsUnavailableOnEverySubscription() {
        val stream = NfcAdapterStatusStream({ null }, {})
        repeat(2) {
            val sink = Sink()
            stream.onListen(null, sink)
            assertEquals(listOf("unavailable"), sink.events)
            stream.onCancel(null)
        }
    }
}
