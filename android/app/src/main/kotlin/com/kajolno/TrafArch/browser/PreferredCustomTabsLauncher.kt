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
 * If discovery or launch fails, opens the URL with the system's default browser.
 * Returns `null` only if both routes fail (the Dart layer then copies the link).
 */
internal class PreferredCustomTabsLauncher(
    private val anyCustomTabsProvider: () -> String?,
    private val launchCustomTab: (String, String) -> Unit,
    private val launchDefaultBrowser: (String) -> Unit,
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
        if (provider != null) {
            try {
                launchCustomTab(provider, url)
                return provider
            } catch (_: RuntimeException) {
                // The provider could be disabled or uninstalled after discovery.
            }
        }
        return try {
            launchDefaultBrowser(url)
            "default_browser"
        } catch (_: RuntimeException) {
            // No browser activity is available, or the system refused the launch.
            null
        }
    }
}
