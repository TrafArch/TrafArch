package com.kajolno.TrafArch.storage

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InterruptedIOException
import java.io.OutputStream
import java.nio.charset.CharacterCodingException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class ArchiveDocumentIoTest {
    @Test fun readsUtf8WithoutChangingLeadingZerosOrChinese() {
        val content = "{\"卡号\":\"00123\"}"
        assertEquals(content, ArchiveDocumentIo.readUtf8(ByteArrayInputStream(content.toByteArray(Charsets.UTF_8))))
    }

    @Test fun sizeLimitCountsBytesAndRejectsOneByteOver() {
        assertEquals("1234", ArchiveDocumentIo.readUtf8(ByteArrayInputStream("1234".toByteArray()), maxBytes = 4))
        assertThrows(ArchiveDocumentTooLarge::class.java) {
            ArchiveDocumentIo.readUtf8(ByteArrayInputStream("一二".toByteArray(Charsets.UTF_8)), maxBytes = 5)
        }
    }

    @Test fun malformedUtf8IsNotSilentlyReplaced() {
        assertThrows(CharacterCodingException::class.java) {
            ArchiveDocumentIo.readUtf8(ByteArrayInputStream(byteArrayOf(0xC3.toByte(), 0x28)))
        }
    }

    @Test fun cancelledReadDoesNotReturnPartialContent() {
        assertThrows(InterruptedIOException::class.java) {
            ArchiveDocumentIo.readUtf8(ByteArrayInputStream("{}".toByteArray()), cancelled = { true })
        }
    }

    @Test fun saveNameAllowsOnlyBasenameJson() {
        assertEquals("卡片备份.JSON", ArchiveDocumentIo.validateFileName("卡片备份.JSON"))
        for (name in listOf("../x.json", "a\\b.json", "x.txt", "", "x\u0000.json", "C:x.json")) {
            assertThrows(IllegalArgumentException::class.java) { ArchiveDocumentIo.validateFileName(name) }
        }
    }

    @Test fun writesUtf8WithoutChangingEvidence() {
        val original = "{\"站点\":\"001号站\",\"amount\":null}"
        val output = ByteArrayOutputStream()
        ArchiveDocumentIo.writeUtf8(output, ArchiveDocumentIo.encodeUtf8(original)) { false }
        assertEquals(original, output.toString("UTF-8"))
    }

    @Test fun failedWritePropagatesInsteadOfReportingSuccess() {
        val output = object : OutputStream() {
            override fun write(value: Int) { throw IOException("provider unavailable") }
        }
        assertThrows(IOException::class.java) {
            ArchiveDocumentIo.writeUtf8(output, "{}".toByteArray()) { false }
        }
    }

    @Test fun cancelledWriteStopsBeforeWritingOrFlushing() {
        var flushed = false
        val output = object : ByteArrayOutputStream() {
            override fun flush() { flushed = true }
        }
        assertThrows(InterruptedIOException::class.java) {
            ArchiveDocumentIo.writeUtf8(output, "{}".toByteArray()) { true }
        }
        assertEquals(0, output.size())
        assertEquals(false, flushed)
    }

    @Test fun invalidUtf16CannotBecomeReplacementCharactersInExport() {
        assertThrows(CharacterCodingException::class.java) {
            ArchiveDocumentIo.encodeUtf8("\uD800")
        }
    }
}
