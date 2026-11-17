package com.kajolno.TrafArch.nfc

/** Only fixed discovery states may cross the diagnostic channel boundary. */
internal enum class NfcDiscoveryPhase(val diagnosticValue: String) {
    WAITING_FOR_TAG("waiting_for_tag"),
    CONNECTING("connecting"),
}

/** Main-looper operations, separated from Android for lifecycle regression tests. */
internal object NfcDiscoveryLifecycle {
    const val TIMEOUT_MS = 55_000L

    fun activate(
        resetDiscovery: Boolean,
        isCurrent: () -> Boolean,
        disable: () -> Unit,
        enable: () -> Unit,
    ) {
        if (!isCurrent()) return
        // A nonzero reader-mode update can retain the previous tag's presence
        // loop. Dedicated NFC-F acquisition must begin a fresh discovery cycle.
        if (resetDiscovery) disable()
        if (!isCurrent()) return
        enable()
    }

    fun acceptsTag(felicaOnly: Boolean, hasFelica: Boolean): Boolean = !felicaOnly || hasFelica

    fun armTimeout(
        schedule: (Long, () -> Unit) -> Unit,
        currentPhase: () -> NfcDiscoveryPhase?,
        onTimeout: (NfcDiscoveryPhase) -> Unit,
    ) {
        schedule(TIMEOUT_MS) {
            // The owning session supplies null after discovery, stop or replacement.
            currentPhase()?.let(onTimeout)
        }
    }
}
