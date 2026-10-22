package com.kajolno.TrafArch.nfc

import android.app.Activity
import com.kajolno.TrafArch.platform.OnceResult
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

internal class NfcChannelHandler(activity: Activity, messenger: BinaryMessenger) {
    private val sessions = NfcSessionController(activity)
    private val channel = MethodChannel(messenger, "transit_card_analyzer/nfc")

    init {
        channel.setMethodCallHandler { call, rawResult ->
            val result = OnceResult(rawResult)
            when (call.method) {
                "scanOnce", "stopScan", "transceive", "transceiveFelica" -> handle(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun handle(call: MethodCall, result: OnceResult) {
        val map = call.arguments as? Map<*, *>
        val rawId = map?.get("sessionId")
        if (map?.containsKey("sessionId") == true && (rawId !is String || rawId.isBlank())) {
            result.error("BAD_ARGUMENT", "sessionId 数据格式错误", null)
            return
        }
        val sessionId = rawId as? String
        when (call.method) {
            "scanOnce" -> sessions.start(sessionId, result)
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

    fun onResume() = sessions.onResume()
    fun onPause() = sessions.onPause()

    fun dispose() {
        channel.setMethodCallHandler(null)
        sessions.dispose()
    }
}
