package com.kajolno.TrafArch.memory

import android.util.AtomicFile
import java.io.File
import java.io.ByteArrayOutputStream

/** Separate from every SQLite file and manifest. noBackupFilesDir is supplied by Application. */
internal class RecoveryFile(directory: File) {
    private val file = AtomicFile(File(directory, "memory_recovery.json"))

    fun read(): String? {
        if (!file.baseFile.exists() && !File(file.baseFile.path + ".bak").exists()) return null
        return file.openRead().use {
            val output = ByteArrayOutputStream()
            val buffer = ByteArray(8192)
            while (true) {
                val count = it.read(buffer)
                if (count < 0) break
                require(output.size() + count <= MAX_BYTES) { "Recovery file too large" }
                output.write(buffer, 0, count)
            }
            output.toString("UTF-8")
        }
    }

    fun write(content: String) {
        // Reject oversized input before making another large UTF-8 allocation.
        require(content.length <= MAX_BYTES) { "Recovery state too large" }
        val bytes = content.toByteArray(Charsets.UTF_8)
        require(bytes.size <= MAX_BYTES) { "Recovery state too large" }
        val stream = file.startWrite()
        try {
            stream.write(bytes)
            file.finishWrite(stream)
        } catch (error: Exception) {
            file.failWrite(stream)
            throw error
        }
    }

    fun clear() = file.delete()

    companion object { const val MAX_BYTES = 8 * 1024 * 1024 }
}
