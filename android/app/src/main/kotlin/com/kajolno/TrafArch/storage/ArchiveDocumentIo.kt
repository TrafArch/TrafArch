package com.kajolno.TrafArch.storage

import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.InterruptedIOException
import java.io.OutputStream
import java.nio.ByteBuffer
import java.nio.CharBuffer
import java.nio.charset.CodingErrorAction

internal class ArchiveDocumentTooLarge : IOException("JSON 文件不得大于 32 MiB，请分卡导出。")

/** Bounded, strict UTF-8 transfer; never silently repairs malformed evidence. */
internal object ArchiveDocumentIo {
    const val MAX_BYTES = 32 * 1024 * 1024

    fun validateFileName(name: String): String {
        require(name.isNotBlank() && name.length <= 240 && name.endsWith(".json", ignoreCase = true) &&
            name.none { it.code < 32 || it in "\\/:*?\"<>|" }) { "需要有效的 JSON 文件名" }
        return name
    }

    fun readUtf8(input: InputStream, maxBytes: Int = MAX_BYTES, cancelled: () -> Boolean = { false }): String {
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(16 * 1024)
        while (true) {
            checkCancelled(cancelled)
            val count = input.read(buffer)
            if (count < 0) break
            if (count > maxBytes - output.size()) throw ArchiveDocumentTooLarge()
            output.write(buffer, 0, count)
        }
        checkCancelled(cancelled)
        return Charsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
            .decode(ByteBuffer.wrap(output.toByteArray())).toString()
    }

    fun encodeUtf8(content: String): ByteArray {
        if (content.length > MAX_BYTES) throw ArchiveDocumentTooLarge()
        val buffer = Charsets.UTF_8.newEncoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
            .encode(CharBuffer.wrap(content))
        if (buffer.remaining() > MAX_BYTES) throw ArchiveDocumentTooLarge()
        return ByteArray(buffer.remaining()).also { buffer.get(it) }
    }

    fun writeUtf8(output: OutputStream, content: ByteArray, cancelled: () -> Boolean) {
        var offset = 0
        while (offset < content.size) {
            checkCancelled(cancelled)
            val count = minOf(16 * 1024, content.size - offset)
            output.write(content, offset, count)
            offset += count
        }
        checkCancelled(cancelled)
        output.flush()
    }

    private fun checkCancelled(cancelled: () -> Boolean) {
        if (cancelled() || Thread.currentThread().isInterrupted) throw InterruptedIOException("文件操作已取消")
    }
}
