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
        // Any installed browser exposing CustomTabsService qualifies; the system picks the
        // best match. Passing null means "no allowlist", so Firefox Beta/Nightly, Brave,
        // Vivaldi, Kiwi, Samsung Internet and others are all eligible.
        anyCustomTabsProvider = { CustomTabsClient.getPackageName(activity, null) },
        launchCustomTab = { provider, url ->
            val tab = CustomTabsIntent.Builder()
                .setShowTitle(true)
                .setCloseButtonPosition(CustomTabsIntent.CLOSE_BUTTON_POSITION_START)
                .build()
            tab.intent.setPackage(provider)
            tab.launchUrl(activity, Uri.parse(url))
        },
        launchDefaultBrowser = { url ->
            activity.startActivity(
                Intent(Intent.ACTION_VIEW, Uri.parse(url))
                    .addCategory(Intent.CATEGORY_BROWSABLE),
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
                        // null means neither Custom Tabs nor the default browser opened;
                        // the Dart layer falls back to copying the link.
                        result.success(launcher.open(url))
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
