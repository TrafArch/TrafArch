package com.kajolno.TrafArch.analytics

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

internal class AnalyticsHandler(context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "transit_card_analyzer/analytics")

    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "isAvailable" -> result.success(AnalyticsBackend.available(context))
                    "setCollectionEnabled" -> {
                        val enabled = call.arguments as? Boolean
                        if (enabled == null) {
                            result.error("INVALID_ARGUMENT", "Expected boolean", null)
                        } else {
                            AnalyticsBackend.setEnabled(context, enabled)
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (_: RuntimeException) {
                result.error("ANALYTICS_UNAVAILABLE", "无法访问 Firebase 分析", null)
            }
        }
    }

    fun dispose() = channel.setMethodCallHandler(null)
}
