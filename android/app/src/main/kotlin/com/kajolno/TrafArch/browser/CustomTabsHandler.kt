package com.kajolno.TrafArch.browser

import android.app.Activity
import android.content.Intent
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
        isInstalled = { provider ->
            activity.packageManager.getLaunchIntentForPackage(provider) != null
        },
        launchCustomTab = { provider, url ->
            val tab = CustomTabsIntent.Builder()
                .setShowTitle(true)
                .setCloseButtonPosition(CustomTabsIntent.CLOSE_BUTTON_POSITION_START)
                .build()
            tab.intent.setPackage(provider)
            tab.launchUrl(activity, Uri.parse(url))
        },
        // Firefox 不绑定 CustomTabsService，只能走 ACTION_VIEW；仍固定包名，
        // 避免退化为系统默认浏览器的隐式选择。
        launchExternal = { provider, url ->
            activity.startActivity(
                Intent(Intent.ACTION_VIEW, Uri.parse(url)).setPackage(provider),
            )
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
                            result.error("BROWSER_UNAVAILABLE", "无法启动 Edge、Chrome 或 Firefox 的浏览器", null)
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
