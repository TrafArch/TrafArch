package com.kajolno.TrafArch.browser

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

class PreferredCustomTabsLauncherTest {
    private val url = "https://example.com/form?id=001#upload"

    private fun launcher(
        supportsCustomTabs: (String) -> Boolean = { true },
        isInstalled: (String) -> Boolean = { true },
        launchCustomTab: (String, String) -> Unit = { _, _ -> },
        launchExternal: (String, String) -> Unit = { _, _ -> },
    ) = PreferredCustomTabsLauncher(
        supportsCustomTabs = supportsCustomTabs,
        isInstalled = isInstalled,
        launchCustomTab = launchCustomTab,
        launchExternal = launchExternal,
    )

    @Test fun edgeWinsWhenAllProvidersSupportCustomTabs() {
        val launched = mutableListOf<Pair<String, String>>()
        val launcher = launcher(launchCustomTab = { provider, address ->
            launched.add(provider to address)
        })

        assertEquals("com.microsoft.emmx", launcher.open(url))
        assertEquals(listOf("com.microsoft.emmx" to url), launched)
    }

    @Test fun missingEdgeUsesChrome() {
        val launched = mutableListOf<String>()
        val launcher = launcher(
            supportsCustomTabs = { it == "com.android.chrome" },
            launchCustomTab = { provider, _ -> launched.add(provider) },
        )

        assertEquals("com.android.chrome", launcher.open(url))
        assertEquals(listOf("com.android.chrome"), launched)
    }

    @Test fun edgeLaunchFailureContinuesWithChrome() {
        val attempted = mutableListOf<String>()
        val launcher = launcher(launchCustomTab = { provider, _ ->
            attempted.add(provider)
            if (provider == "com.microsoft.emmx") throw SecurityException("disabled")
        })

        assertEquals("com.android.chrome", launcher.open(url))
        assertEquals(listOf("com.microsoft.emmx", "com.android.chrome"), attempted)
    }

    @Test fun failedProviderDiscoveryStillTriesChrome() {
        val launcher = launcher(supportsCustomTabs = {
            if (it == "com.microsoft.emmx") throw SecurityException("hidden")
            true
        })
        assertEquals("com.android.chrome", launcher.open(url))
    }

    @Test fun firefoxFallsBackToExternalViewBecauseItHasNoCustomTabsService() {
        val customTabs = mutableListOf<String>()
        val external = mutableListOf<Pair<String, String>>()
        val launcher = launcher(
            supportsCustomTabs = { false },
            isInstalled = { it == "org.mozilla.firefox" },
            launchCustomTab = { provider, _ -> customTabs.add(provider) },
            launchExternal = { provider, address -> external.add(provider to address) },
        )

        assertEquals("org.mozilla.firefox", launcher.open(url))
        assertEquals(emptyList<String>(), customTabs)
        assertEquals(listOf("org.mozilla.firefox" to url), external)
    }

    @Test fun firefoxWithCustomTabsServiceUsesCustomTabNotExternalView() {
        val customTabs = mutableListOf<String>()
        val external = mutableListOf<String>()
        val launcher = launcher(
            supportsCustomTabs = { it == "org.mozilla.firefox" },
            launchCustomTab = { provider, _ -> customTabs.add(provider) },
            launchExternal = { provider, _ -> external.add(provider) },
        )

        assertEquals("org.mozilla.firefox", launcher.open(url))
        assertEquals(listOf("org.mozilla.firefox"), customTabs)
        assertEquals(emptyList<String>(), external)
    }

    @Test fun missingProvidersNeverLaunchAnImplicitDefaultBrowser() {
        val checked = mutableListOf<String>()
        val launched = mutableListOf<String>()
        val launcher = launcher(
            supportsCustomTabs = { checked.add(it); false },
            isInstalled = { false },
            launchCustomTab = { provider, _ -> launched.add(provider) },
            launchExternal = { provider, _ -> launched.add(provider) },
        )

        assertNull(launcher.open(url))
        assertEquals(
            listOf("com.microsoft.emmx", "com.android.chrome", "org.mozilla.firefox"),
            checked,
        )
        assertEquals(emptyList<String>(), launched)
    }

    @Test fun allLaunchFailuresReportUnavailable() {
        val attempted = mutableListOf<String>()
        val launcher = launcher(launchCustomTab = { provider, _ ->
            attempted.add(provider)
            throw IllegalStateException("activity no longer available")
        })

        assertNull(launcher.open(url))
        assertEquals(
            listOf("com.microsoft.emmx", "com.android.chrome", "org.mozilla.firefox"),
            attempted,
        )
    }

    @Test fun firefoxExternalLaunchFailureIsReported() {
        val launcher = launcher(
            supportsCustomTabs = { false },
            isInstalled = { true },
            launchExternal = { _, _ -> throw SecurityException("disabled") },
        )

        assertNull(launcher.open(url))
    }

    @Test fun invalidUrlsAreRejectedBeforeBrowserDiscovery() {
        var queried = false
        val launcher = launcher(supportsCustomTabs = { queried = true; true })

        for (address in listOf("", "https:/form", "file:///tmp/a", "javascript:alert(1)",
            "https://example.com/a b")) {
            assertThrows(IllegalArgumentException::class.java) { launcher.open(address) }
        }
        assertEquals(false, queried)
    }
}
