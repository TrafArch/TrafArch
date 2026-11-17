package com.kajolno.TrafArch.platform

import android.content.Context
import com.hihonor.uikit.hnmagicsystem.compatibility.TransparencyCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Read-only capability probe for MagicOS translucent (通透) components.
 *
 * The bundled Translucent Component Kit answers through
 * [TransparencyCompat.isSupportTransparencyView]; Honor's docs also expose the
 * `launcher_transparency_mode` resource in `androidhnext`, so that value is
 * kept as a fallback when the SDK class is unavailable or misbehaves. Neither
 * path changes system state; the kit itself is only queried, never used to
 * draw here.
 */
internal class TranslucencyChannelHandler(context: Context, messenger: BinaryMessenger) {
    private val appContext = context.applicationContext
    private val channel = MethodChannel(messenger, "transit_card_analyzer/translucency")

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getSupport" -> result.success(support())
                else -> result.notImplemented()
            }
        }
    }

    private fun support(): Map<String, Any> {
        val mode = runCatching {
            val resId = appContext.resources.getIdentifier(
                RES_NAME, "integer", RES_PACKAGE_HN_EXT,
            )
            if (resId > 0) appContext.resources.getInteger(resId) else 0
        }.getOrDefault(0)
        val sdk = runCatching {
            TransparencyCompat.isSupportTransparencyView()
        }.getOrDefault(false)
        return mapOf(
            "supported" to (sdk || mode == TRANSPARENCY_MODE_SUPPORTED),
            "mode" to mode,
            "sdk" to sdk,
        )
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    private companion object {
        const val RES_PACKAGE_HN_EXT = "androidhnext"
        const val RES_NAME = "launcher_transparency_mode"

        /** Honor: 3 means the translucent switch is exposed. */
        const val TRANSPARENCY_MODE_SUPPORTED = 3
    }
}