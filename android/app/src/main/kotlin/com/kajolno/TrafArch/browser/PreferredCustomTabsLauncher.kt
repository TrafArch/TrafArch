package com.kajolno.TrafArch.browser

import java.net.URI
import java.net.URISyntaxException
import java.util.Locale

/** Browser selection stays deterministic even if a provider disappears after discovery. */
internal class PreferredCustomTabsLauncher(
    private val supportsCustomTabs: (String) -> Boolean,
    private val launch: (String, String) -> Unit,
) {
    fun open(url: String): String? {
        val uri = try {
            URI(url)
        } catch (error: URISyntaxException) {
            throw IllegalArgumentException("Invalid web URL", error)
        }
        require(uri.scheme?.lowercase(Locale.ROOT) in setOf("http", "https") &&
            !uri.host.isNullOrEmpty()) { "Only absolute HTTP(S) URLs are supported" }

        for (provider in listOf("com.microsoft.emmx", "com.android.chrome")) {
            try {
                if (!supportsCustomTabs(provider)) continue
                launch(provider, url)
                return provider
            } catch (_: RuntimeException) {
                // Package visibility, disabled activities or a failed launch may change
                // between lookup and startActivity. Try the next supported provider.
            }
        }
        return null
    }
}
