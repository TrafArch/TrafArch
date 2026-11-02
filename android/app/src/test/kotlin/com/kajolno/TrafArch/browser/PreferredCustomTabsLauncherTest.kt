package com.kajolno.TrafArch.browser

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

class PreferredCustomTabsLauncherTest {
    private val url = "https://example.com/form?id=001#upload"

    private fun launcher(
        anyCustomTabsProvider: () -> String? = { "com.microsoft.emmx" },
        launchCustomTab: (String, String) -> Unit = { _, _ -> },
    ) = PreferredCustomTabsLauncher(
        anyCustomTabsProvider = anyCustomTabsProvider,
        launchCustomTab = launchCustomTab,
    )

    @Test fun launchesWhateverCustomTabsBrowserTheSystemReports() {
        val launched = mutableListOf<Pair<String, String>>()
        val launcher = launcher(
            anyCustomTabsProvider = { "org.mozilla.firefox_beta" },
            launchCustomTab = { provider, address -> launched.add(provider to address) },
        )

        assertEquals("org.mozilla.firefox_beta", launcher.open(url))
        assertEquals(listOf("org.mozilla.firefox_beta" to url), launched)
    }

    @Test fun anyCustomTabsPackageIsAcceptedWithoutAnAllowlist() {
        val launched = mutableListOf<String>()
        val launcher = launcher(
            anyCustomTabsProvider = { "com.brave.browser" },
            launchCustomTab = { provider, _ -> launched.add(provider) },
        )

        assertEquals("com.brave.browser", launcher.open(url))
        assertEquals(listOf("com.brave.browser"), launched)
    }

    @Test fun missingCustomTabsBrowserReturnsNullWithoutLaunching() {
        var launched = false
        val launcher = launcher(
            anyCustomTabsProvider = { null },
            launchCustomTab = { _, _ -> launched = true },
        )

        assertNull(launcher.open(url))
        assertEquals(false, launched)
    }

    @Test fun providerDiscoveryFailureIsReportedAsUnavailable() {
        val launcher = launcher(anyCustomTabsProvider = { throw SecurityException("hidden") })

        assertNull(launcher.open(url))
    }

    @Test fun launchFailureIsReportedAsUnavailable() {
        val launcher = launcher(launchCustomTab = { _, _ ->
            throw IllegalStateException("activity no longer available")
        })

        assertNull(launcher.open(url))
    }

    @Test fun invalidUrlsAreRejectedBeforeBrowserDiscovery() {
        var queried = false
        val launcher = launcher(anyCustomTabsProvider = { queried = true; "com.android.chrome" })

        for (address in listOf("", "https:/form", "file:///tmp/a", "javascript:alert(1)",
            "https://example.com/a b")) {
            assertThrows(IllegalArgumentException::class.java) { launcher.open(address) }
        }
        assertEquals(false, queried)
    }
}
