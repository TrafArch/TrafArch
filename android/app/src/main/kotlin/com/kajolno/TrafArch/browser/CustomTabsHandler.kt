package com.kajolno.TrafArch.browser

import android.app.Activity
import android.net.Uri
import androidx.browser.customtabs.CustomTabsClient
import androidx.browser.customtabs.CustomTabsIntent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

internal class CustomTabsHandler(activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "transit_card_analyzer/browser")
    private val launcher = PreferredCustomTabsLauncher(
        supportsCustomTabs = { provider ->
            // Ignore the system default browser; only the ordered allowlist is eligible.
            CustomTabsClient.getPackageName(activity, listOf(provider), true) == provider
        },
        launch = { provider, url ->
            val tab = CustomTabsIntent.Builder()
                .setShowTitle(true)
                .setCloseButtonPosition(CustomTabsIntent.CLOSE_BUTTON_POSITION_START)
                .build()
            tab.intent.setPackage(provider)
            tab.launchUrl(activity, Uri.parse(url))
        },
    )

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "openCustomTab") {
                result.notImplemented()
            } else {
                val url = (call.arguments as? Map<*, *>)?.get("url") as? String
                if (url == null) {
                    result.error("INVALID_URL", "问卷地址无效", null)
                } else {
                    try {
                        val provider = launcher.open(url)
                        if (provider == null) {
                            result.error("BROWSER_UNAVAILABLE", "无法启动 Edge 或 Chrome 的应用内浏览器", null)
                        } else {
                            result.success(provider)
                        }
                    } catch (_: IllegalArgumentException) {
                        result.error("INVALID_URL", "问卷地址无效", null)
                    }
                }
            }
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }
}
