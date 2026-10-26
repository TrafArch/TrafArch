package com.kajolno.TrafArch.browser

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

class PreferredCustomTabsLauncherTest {
    private val url = "https://example.com/form?id=001#upload"

    @Test fun edgeWinsWhenBothProvidersSupportCustomTabs() {
        val launched = mutableListOf<Pair<String, String>>()
        val launcher = PreferredCustomTabsLauncher(
            supportsCustomTabs = { true },
            launch = { provider, address -> launched.add(provider to address) },
        )

        assertEquals("com.microsoft.emmx", launcher.open(url))
        assertEquals(listOf("com.microsoft.emmx" to url), launched)
    }

    @Test fun missingEdgeUsesChrome() {
        val launched = mutableListOf<String>()
        val launcher = PreferredCustomTabsLauncher(
            supportsCustomTabs = { it == "com.android.chrome" },
            launch = { provider, _ -> launched.add(provider) },
        )

        assertEquals("com.android.chrome", launcher.open(url))
        assertEquals(listOf("com.android.chrome"), launched)
    }

    @Test fun edgeLaunchFailureContinuesWithChrome() {
        val attempted = mutableListOf<String>()
        val launcher = PreferredCustomTabsLauncher(
            supportsCustomTabs = { true },
            launch = { provider, _ ->
                attempted.add(provider)
                if (provider == "com.microsoft.emmx") throw SecurityException("disabled")
            },
        )

        assertEquals("com.android.chrome", launcher.open(url))
        assertEquals(listOf("com.microsoft.emmx", "com.android.chrome"), attempted)
    }

    @Test fun failedProviderDiscoveryStillTriesChrome() {
        val launcher = PreferredCustomTabsLauncher(
            supportsCustomTabs = {
                if (it == "com.microsoft.emmx") throw SecurityException("hidden")
                true
            },
            launch = { _, _ -> },
        )
        assertEquals("com.android.chrome", launcher.open(url))
    }

    @Test fun missingProvidersNeverLaunchAnImplicitDefaultBrowser() {
        val checked = mutableListOf<String>()
        val launched = mutableListOf<String>()
        val launcher = PreferredCustomTabsLauncher(
            supportsCustomTabs = { checked.add(it); false },
            launch = { provider, _ -> launched.add(provider) },
        )

        assertNull(launcher.open(url))
        assertEquals(listOf("com.microsoft.emmx", "com.android.chrome"), checked)
        assertEquals(emptyList<String>(), launched)
    }

    @Test fun bothLaunchFailuresReportUnavailable() {
        val attempted = mutableListOf<String>()
        val launcher = PreferredCustomTabsLauncher(
            supportsCustomTabs = { true },
            launch = { provider, _ ->
                attempted.add(provider)
                throw IllegalStateException("activity no longer available")
            },
        )

        assertNull(launcher.open(url))
        assertEquals(listOf("com.microsoft.emmx", "com.android.chrome"), attempted)
    }

    @Test fun invalidUrlsAreRejectedBeforeBrowserDiscovery() {
        var queried = false
        val launcher = PreferredCustomTabsLauncher(
            supportsCustomTabs = { queried = true; true },
            launch = { _, _ -> },
        )

        for (address in listOf("", "https:/form", "file:///tmp/a", "javascript:alert(1)",
            "https://example.com/a b")) {
            assertThrows(IllegalArgumentException::class.java) { launcher.open(address) }
        }
        assertEquals(false, queried)
    }
}
