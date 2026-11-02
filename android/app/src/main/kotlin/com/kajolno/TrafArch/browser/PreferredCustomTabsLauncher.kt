package com.kajolno.TrafArch.browser

import java.net.URI
import java.net.URISyntaxException
import java.util.Locale

/**
 * Opens a web page in any installed browser that provides a Custom Tabs service.
 *
 * The system Custom Tabs lookup returns the best matching provider, so the launcher no
 * longer pins a fixed allowlist: Edge, Chrome, Firefox Beta/Nightly, Brave, Vivaldi, Kiwi,
 * Samsung Internet and any other browser that declares `CustomTabsService` are all eligible.
 * When no provider is available the caller receives `null` and decides the fallback
 * (the Dart layer copies the link to the clipboard).
 */
internal class PreferredCustomTabsLauncher(
    private val anyCustomTabsProvider: () -> String?,
    private val launchCustomTab: (String, String) -> Unit,
) {
    fun open(url: String): String? {
        val uri = try {
            URI(url)
        } catch (error: URISyntaxException) {
            throw IllegalArgumentException("Invalid web URL", error)
        }
        require(uri.scheme?.lowercase(Locale.ROOT) in setOf("http", "https") &&
            !uri.host.isNullOrEmpty()) { "Only absolute HTTP(S) URLs are supported" }

        val provider = try {
            anyCustomTabsProvider()
        } catch (_: RuntimeException) {
            // Package visibility may change between discovery and this call; treat as absent.
            null
        }
        if (provider == null) return null
        return try {
            launchCustomTab(provider, url)
            provider
        } catch (_: RuntimeException) {
            // The provider could be disabled or uninstalled between discovery and launch.
            null
        }
    }
}
