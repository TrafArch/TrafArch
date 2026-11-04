package com.kajolno.TrafArch.memory

import org.junit.Assert.assertEquals
import org.junit.Test

class MemoryRequestGateTest {
    @Test fun overlappingTrimAndKillReplyToTheirOwnRequestOnce() {
        val deadlines = mutableListOf<() -> Unit>()
        val work = mutableListOf<Pair<Boolean, (Boolean) -> Unit>>()
        val replies = mutableListOf<Pair<Int, Boolean>>()
        val gate = MemoryRequestGate(
            schedule = { delay, action -> assertEquals(2400L, delay); deadlines.add(action) },
            dispatch = { kill, complete -> work.add(kill to complete) },
        )
        gate.receive(1, false) { ok, _ -> replies.add(1 to ok) }
        gate.receive(2, true) { ok, _ -> replies.add(2 to ok) }
        gate.receive(1, false) { _, _ -> throw AssertionError("duplicate") }
        assertEquals(listOf(false, true), work.map { it.first })
        work[1].second(true)
        deadlines.forEach { it() }
        work[0].second(true) // Late success cannot replace a timeout failure.
        work[1].second(false)
        assertEquals(listOf(2 to true, 1 to false), replies)
    }

    @Test fun unavailableHandlerReportsFailureWithoutWaitingForSystemTimeout() {
        val replies = mutableListOf<Boolean>()
        val deadlines = mutableListOf<() -> Unit>()
        val gate = MemoryRequestGate(
            schedule = { _, action -> deadlines.add(action) },
            dispatch = { _, _ -> throw IllegalStateException("engine detached") },
        )
        gate.receive("request", true) { ok, _ -> replies.add(ok) }
        deadlines.single()()
        assertEquals(listOf(false), replies)
    }
}
