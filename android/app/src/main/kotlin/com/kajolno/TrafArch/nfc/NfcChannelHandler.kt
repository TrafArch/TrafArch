package com.kajolno.TrafArch.nfc

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.nfc.NfcAdapter
import com.kajolno.TrafArch.platform.OnceResult
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

internal class NfcChannelHandler(private val activity: Activity, messenger: BinaryMessenger) {
    private val sessions = NfcSessionController(activity)
    private val channel = MethodChannel(messenger, "transit_card_analyzer/nfc")
    private val octopusChannel = MethodChannel(messenger, "transit_card_analyzer/octopus_nfc")
    private val statusChannel = EventChannel(messenger, "transit_card_analyzer/nfc_status")
    private val status = NfcAdapterStatusStream(sessions::adapterEnabled, sessions::onAdapterPowerChanged)
    private var disposed = false
    private val powerReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == NfcAdapter.ACTION_ADAPTER_STATE_CHANGED) {
                status.onAdapterState(intent.getIntExtra(NfcAdapter.EXTRA_ADAPTER_STATE, -1))
            }
        }
    }

    init {
        bind(channel, felicaOnly = false)
        bind(octopusChannel, felicaOnly = true)
        // This filter contains only Android's protected NFC system broadcast.
        activity.registerReceiver(powerReceiver, IntentFilter(NfcAdapter.ACTION_ADAPTER_STATE_CHANGED))
        statusChannel.setStreamHandler(status)
    }

    private fun bind(target: MethodChannel, felicaOnly: Boolean) {
        target.setMethodCallHandler { call, rawResult ->
            val result = OnceResult(rawResult)
            when (call.method) {
                "scanOnce", "stopScan", "transceiveFelica" -> handle(call, result, felicaOnly)
                "getFelicaReaderSupport" -> if (felicaOnly) result.notImplemented() else {
                    // Android CDD 7.4.4 requires NFC-F reader mode for advertised NFC.
                    // NFC-F host card emulation is a separate capability.
                    val supported = when {
                        sessions.adapterEnabled() == null -> false
                        activity.packageManager.hasSystemFeature(PackageManager.FEATURE_NFC) -> true
                        else -> null
                    }
                    result.success(supported)
                }
                "transceive" -> if (felicaOnly) result.notImplemented() else handle(call, result, felicaOnly)
                else -> result.notImplemented()
            }
        }
    }

    private fun handle(call: MethodCall, result: OnceResult, felicaOnly: Boolean) {
        val map = call.arguments as? Map<*, *>
        val rawId = map?.get("sessionId")
        if ((felicaOnly || map?.containsKey("sessionId") == true) && (rawId !is String || rawId.isBlank())) {
            result.error("BAD_ARGUMENT", "sessionId 数据格式错误", null)
            return
        }
        val sessionId = rawId as? String
        when (call.method) {
            "scanOnce" -> sessions.start(sessionId, result, felicaOnly)
            "stopScan" -> sessions.stop(sessionId, result)
            else -> {
                val felica = call.method == "transceiveFelica"
                val payload = if (map == null) call.arguments else map[if (felica) "frame" else "apdu"]
                val bytes = when (payload) {
                    is ByteArray -> payload.copyOf()
                    is List<*> -> if (payload.all { it is Number }) {
                        payload.map { (it as Number).toByte() }.toByteArray()
                    } else null
                    else -> null
                }
                if (bytes == null) {
                    result.error("BAD_ARGUMENT", if (felica) "FeliCa 帧格式错误" else "APDU 数据格式错误", null)
                } else {
                    sessions.transceive(sessionId, felica, bytes, result)
                }
            }
        }
    }

    fun onResume() {
        status.refresh()
        sessions.onResume()
    }
    fun onPause() = sessions.onPause()

    fun dispose() {
        if (disposed) return
        disposed = true
        activity.unregisterReceiver(powerReceiver)
        status.onCancel(null)
        statusChannel.setStreamHandler(null)
        channel.setMethodCallHandler(null)
        octopusChannel.setMethodCallHandler(null)
        sessions.dispose()
    }
}
