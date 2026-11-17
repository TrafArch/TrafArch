package com.kajolno.TrafArch.nfc

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NfcDiscoveryLifecycleTest {
    private class PresentTagReader {
        val events = mutableListOf<String>()
        var presenceLatched = true
        var discoveries = 0

        fun closeTechnology() {
            // Android BasicTagTechnology.close reconnects rather than removing the tag.
            events.add("technology-close")
        }

        fun idle() {
            events.add("idle-enable")
        }

        fun disable() {
            events.add("disable")
            presenceLatched = false
        }

        fun enableFelica() {
            events.add("felica-enable")
            // Changing nonzero reader flags does not retire a present old tag.
            if (!presenceLatched) {
                presenceLatched = true
                discoveries++
            }
        }
    }

    @Test
    fun presentIsoTagIsRediscoveredAsFelicaAfterTechnologyClose() {
        val reader = PresentTagReader()
        reader.closeTechnology()
        reader.idle()

        NfcDiscoveryLifecycle.activate(true, { true }, reader::disable, reader::enableFelica)

        assertEquals(1, reader.discoveries)
        assertEquals(
            listOf("technology-close", "idle-enable", "disable", "felica-enable"),
            reader.events,
        )
    }

    @Test
    fun ordinaryDiscoveryDoesNotResetTheReader() {
        val reader = PresentTagReader()
        NfcDiscoveryLifecycle.activate(false, { true }, reader::disable, reader::enableFelica)
        assertEquals(listOf("felica-enable"), reader.events)
        assertTrue(reader.presenceLatched)
    }

    @Test
    fun cancelledOrReplacedSessionCannotChangeReaderMode() {
        val reader = PresentTagReader()
        NfcDiscoveryLifecycle.activate(true, { false }, reader::disable, reader::enableFelica)
        assertTrue(reader.events.isEmpty())
    }

    @Test
    fun cancellationDuringResetDoesNotReenableDiscovery() {
        val reader = PresentTagReader()
        var current = true
        NfcDiscoveryLifecycle.activate(true, { current }, {
            reader.disable()
            current = false
        }, reader::enableFelica)
        assertEquals(listOf("disable"), reader.events)
        assertEquals(0, reader.discoveries)
    }

    @Test
    fun resetFailureDoesNotEnableAReaderWithUncertainPresenceState() {
        var enabled = false
        var failed = false
        try {
            NfcDiscoveryLifecycle.activate(true, { true }, {
                throw IllegalStateException("reset failed")
            }, { enabled = true })
        } catch (_: IllegalStateException) {
            failed = true
        }
        assertTrue(failed)
        assertFalse(enabled)
    }

    private class WaitingDiscovery(private val felicaOnly: Boolean) {
        var connectedTechnology: String? = null
        fun onTagDiscovered(hasFelica: Boolean) {
            if (connectedTechnology != null) return
            if (!NfcDiscoveryLifecycle.acceptsTag(felicaOnly, hasFelica)) return
            connectedTechnology = if (hasFelica) "NFC-F" else "ISO-DEP"
        }
    }

    @Test
    fun queuedOldIsoCallbackCannotClaimTheNewFelicaDiscovery() {
        val session = WaitingDiscovery(felicaOnly = true)
        // Android delivers through the current Activity callback: an old tag
        // notification may already be queued when reader flags are replaced.
        session.onTagDiscovered(hasFelica = false)
        session.onTagDiscovered(hasFelica = true)
        assertEquals("NFC-F", session.connectedTechnology)
    }

    @Test
    fun ordinaryReaderStillClaimsItsFirstIsoTag() {
        val session = WaitingDiscovery(felicaOnly = false)
        session.onTagDiscovered(hasFelica = false)
        session.onTagDiscovered(hasFelica = true)
        assertEquals("ISO-DEP", session.connectedTechnology)
    }

    private class Clock {
        var now = 0L
        val work = mutableListOf<Pair<Long, () -> Unit>>()
        fun schedule(delay: Long, action: () -> Unit) {
            work.add(now + delay to action)
        }
        fun advance(milliseconds: Long) {
            now += milliseconds
            val due = work.filter { it.first <= now }
            work.removeAll(due.toSet())
            due.forEach { it.second() }
        }
    }

    @Test
    fun waitingTagTimesOutAt55SecondsBeforeDartFallback() {
        val clock = Clock()
        val failures = mutableListOf<NfcDiscoveryPhase>()
        NfcDiscoveryLifecycle.armTimeout(clock::schedule,
            { NfcDiscoveryPhase.WAITING_FOR_TAG }, failures::add)
        clock.advance(54_999)
        assertTrue(failures.isEmpty())
        clock.advance(1)
        assertEquals(listOf(NfcDiscoveryPhase.WAITING_FOR_TAG), failures)
        clock.advance(60_000)
        assertEquals(1, failures.size)
    }

    @Test
    fun deadlineReportsConnectingIfTagCallbackArrived() {
        val clock = Clock()
        var phase: NfcDiscoveryPhase? = NfcDiscoveryPhase.WAITING_FOR_TAG
        val failures = mutableListOf<NfcDiscoveryPhase>()
        NfcDiscoveryLifecycle.armTimeout(clock::schedule, { phase }, failures::add)
        clock.advance(1_000)
        phase = NfcDiscoveryPhase.CONNECTING
        clock.advance(54_000)
        assertEquals(listOf(NfcDiscoveryPhase.CONNECTING), failures)
    }

    @Test
    fun completedStoppedOrReplacedSessionInvalidatesItsDeadline() {
        for (terminalState in listOf("success", "stopped", "replaced")) {
            val clock = Clock()
            var phase: NfcDiscoveryPhase? = NfcDiscoveryPhase.WAITING_FOR_TAG
            val failures = mutableListOf<NfcDiscoveryPhase>()
            NfcDiscoveryLifecycle.armTimeout(clock::schedule, { phase }, failures::add)
            phase = null
            clock.advance(60_000)
            assertTrue(terminalState, failures.isEmpty())
        }
    }
}
