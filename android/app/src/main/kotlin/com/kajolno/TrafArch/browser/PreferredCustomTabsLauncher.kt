package com.kajolno.TrafArch.browser

import java.net.URI
import java.net.URISyntaxException
import java.util.Locale

/**
 * Browser selection stays deterministic even if a provider disappears after discovery.
 *
 * Edge and Chrome expose a Custom Tabs service. Firefox for Android does not bind a
 * `CustomTabsService` (it only handles `ACTION_VIEW`), so it is listed as an external
 * fallback: still pinned to its package name, never an implicit "any browser" intent.
 */
internal class PreferredCustomTabsLauncher(
    private val supportsCustomTabs: (String) -> Boolean,
    private val isInstalled: (String) -> Boolean,
    private val launchCustomTab: (String, String) -> Unit,
    private val launchExternal: (String, String) -> Unit,
) {
    private data class Provider(val packageName: String, val externalFallback: Boolean)

    private val providers = listOf(
        Provider(EDGE, externalFallback = false),
        Provider(CHROME, externalFallback = false),
        Provider(FIREFOX, externalFallback = true),
    )

    fun open(url: String): String? {
        val uri = try {
            URI(url)
        } catch (error: URISyntaxException) {
            throw IllegalArgumentException("Invalid web URL", error)
        }
        require(uri.scheme?.lowercase(Locale.ROOT) in setOf("http", "https") &&
            !uri.host.isNullOrEmpty()) { "Only absolute HTTP(S) URLs are supported" }

        for (provider in providers) {
            try {
                if (supportsCustomTabs(provider.packageName)) {
                    launchCustomTab(provider.packageName, url)
                    return provider.packageName
                }
                if (provider.externalFallback && isInstalled(provider.packageName)) {
                    launchExternal(provider.packageName, url)
                    return provider.packageName
                }
            } catch (_: RuntimeException) {
                // Package visibility, disabled activities or a failed launch may change
                // between lookup and startActivity. Try the next supported provider.
            }
        }
        return null
    }

    private companion object {
        const val EDGE = "com.microsoft.emmx"
        const val CHROME = "com.android.chrome"
        const val FIREFOX = "org.mozilla.firefox"
    }
}
