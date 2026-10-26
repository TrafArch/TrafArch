package com.kajolno.TrafArch.storage

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import com.kajolno.TrafArch.platform.OnceResult
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.io.InterruptedIOException
import java.nio.charset.CharacterCodingException
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/** System document picker owns file access; no broad storage permission is used. */
internal class ArchiveDocumentHandler(private val activity: Activity, messenger: BinaryMessenger) {
    private class Request(val result: OnceResult, val content: ByteArray? = null) {
        val requestCode = requestCodes.getAndUpdate { if (it >= 0x7FFF) 0x4000 else it + 1 }
        @Volatile var cancelled = false
    }

    private val channel = MethodChannel(messenger, "transit_card_analyzer/archive_documents")
    private val io = Executors.newSingleThreadExecutor { Thread(it, "TrafArch-archive-documents") }
    private var pending: Request? = null
    private var transferring = false
    private var disposed = false

    init {
        channel.setMethodCallHandler { call, rawResult ->
            val result = OnceResult(rawResult)
            if (call.method != "openJson" && call.method != "saveJson") {
                result.notImplemented()
            } else if (disposed) {
                result.success(null)
            } else if (pending != null) {
                result.error("DOCUMENT_IN_PROGRESS", "已有文件操作正在进行", null)
            } else {
                try {
                    if (call.method == "openJson") {
                        launch(Request(result), null)
                    } else {
                        val arguments = call.arguments as? Map<*, *>
                        val name = arguments?.get("fileName") as? String
                            ?: throw IllegalArgumentException("缺少文件名")
                        val content = arguments.get("content") as? String
                            ?: throw IllegalArgumentException("缺少文件内容")
                        ArchiveDocumentIo.validateFileName(name)
                        launch(Request(result, ArchiveDocumentIo.encodeUtf8(content)), name)
                    }
                } catch (error: Exception) {
                    pending = null
                    replyError(result, error, writing = call.method == "saveJson")
                }
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun launch(request: Request, fileName: String?) {
        pending = request
        val intent = if (fileName == null) {
            Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                type = "*/*"
                putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/json", "text/json", "text/plain", "application/octet-stream"))
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        } else {
            Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                type = "application/json"
                putExtra(Intent.EXTRA_TITLE, fileName)
                addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            }
        }
        intent.addCategory(Intent.CATEGORY_OPENABLE)
        activity.startActivityForResult(intent, request.requestCode)
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        val request = pending ?: return
        if (requestCode != request.requestCode || transferring) return
        val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
        if (uri == null) {
            pending = null
            request.result.success(null)
            return
        }
        transferring = true
        io.execute {
            try {
                val output = if (request.content == null) {
                    val content = activity.contentResolver.openInputStream(uri)?.use {
                        ArchiveDocumentIo.readUtf8(it, cancelled = { request.cancelled })
                    } ?: throw IOException("无法打开所选文件")
                    mapOf("name" to displayName(uri), "content" to content)
                } else {
                    if (request.cancelled) throw InterruptedIOException("文件操作已取消")
                    activity.contentResolver.openOutputStream(uri, "wt")?.use {
                        ArchiveDocumentIo.writeUtf8(it, request.content) { request.cancelled }
                    } ?: throw IOException("无法写入所选位置")
                    displayName(uri)
                }
                activity.runOnUiThread {
                    finish(request)
                    request.result.success(output)
                }
            } catch (error: Exception) {
                activity.runOnUiThread {
                    finish(request)
                    if (request.cancelled) request.result.success(null)
                    else replyError(request.result, error, writing = request.content != null)
                }
            }
        }
    }

    private fun displayName(uri: Uri): String = runCatching {
        activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) it.getString(0)?.takeIf(String::isNotBlank) else null
        }
    }.getOrNull() ?: "卡片数据.json"

    private fun finish(request: Request) {
        if (pending === request) {
            pending = null
            transferring = false
        }
    }

    private fun replyError(result: OnceResult, error: Exception, writing: Boolean) {
        val code = when (error) {
            is ArchiveDocumentTooLarge -> "DOCUMENT_TOO_LARGE"
            is CharacterCodingException -> "DOCUMENT_INVALID_UTF8"
            is IllegalArgumentException -> "BAD_ARGUMENT"
            else -> if (writing) "DOCUMENT_WRITE_FAILED" else "DOCUMENT_READ_FAILED"
        }
        val message = if (error is CharacterCodingException) "请选择 UTF-8 编码的 JSON 文件"
            else error.message ?: if (writing) "文件保存失败" else "文件读取失败"
        result.error(code, message, null)
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        channel.setMethodCallHandler(null)
        pending?.let {
            it.cancelled = true
            it.result.success(null)
        }
        pending = null
        transferring = false
        io.shutdownNow()
    }

    // A result belonging to a disposed handler cannot complete a new operation
    // after Flutter engine replacement on the same Activity.
    companion object { private val requestCodes = AtomicInteger(0x4000) }
}
