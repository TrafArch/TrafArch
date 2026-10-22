package com.kajolno.TrafArch.storage

import android.Manifest
import android.app.Activity
import android.content.ContentValues
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import androidx.annotation.RequiresApi
import com.kajolno.TrafArch.platform.OnceResult
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.concurrent.Executors

internal class FileExportHandler(private val activity: Activity, messenger: BinaryMessenger) {
    private data class Request(val fileName: String, val content: String, val result: OnceResult)
    private val channel = MethodChannel(messenger, "transit_card_analyzer/export")
    private val io = Executors.newSingleThreadExecutor { Thread(it, "TrafArch-export") }
    private val replies = mutableSetOf<OnceResult>() // Main looper only, including in-flight writes.
    private var waitingPermission: Request? = null
    private var disposed = false

    init {
        channel.setMethodCallHandler { call, rawResult ->
            val result = OnceResult(rawResult)
            if (call.method == "saveToDownloads") exportToDownloads(call, result) else result.notImplemented()
        }
    }

    private fun exportToDownloads(call: MethodCall, result: OnceResult) {
        if (disposed) {
            result.error("EXPORT_CANCELLED", "页面已关闭，导出已取消", null)
            return
        }
        val arguments = call.arguments as? Map<*, *>
        val fileName = arguments?.get("fileName") as? String
        val content = arguments?.get("content") as? String
        if (fileName.isNullOrBlank() || content == null) {
            result.error("BAD_ARGUMENT", "导出参数缺失", null)
            return
        }
        if (waitingPermission != null) {
            result.error("EXPORT_IN_PROGRESS", "导出正在等待存储权限", null)
            return
        }
        val request = Request(fileName, content, result)
        replies.add(result)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ||
            activity.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
        ) {
            writeToDownloads(request)
        } else {
            waitingPermission = request
            try {
                activity.requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), REQUEST_WRITE_STORAGE)
            } catch (error: Exception) {
                waitingPermission = null
                replies.remove(result)
                result.error("EXPORT_FAILED", error.message ?: "导出失败", null)
            }
        }
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != REQUEST_WRITE_STORAGE) return
        val request = waitingPermission ?: return
        waitingPermission = null
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            writeToDownloads(request)
        } else {
            replies.remove(request.result)
            request.result.error("PERMISSION_DENIED", "未授予存储权限，无法导出到下载目录", null)
        }
    }

    private fun writeToDownloads(request: Request) {
        io.execute {
            try {
                val path = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    writeViaMediaStore(request.fileName, request.content)
                } else {
                    writeViaLegacyDownloads(request.fileName, request.content)
                }
                activity.runOnUiThread {
                    replies.remove(request.result)
                    request.result.success(path)
                }
            } catch (error: Exception) {
                Log.w(TAG, "Export log failed: ${error.message}")
                activity.runOnUiThread {
                    replies.remove(request.result)
                    request.result.error("EXPORT_FAILED", error.message ?: "导出失败", null)
                }
            }
        }
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        channel.setMethodCallHandler(null)
        waitingPermission = null
        replies.forEach { it.error("EXPORT_CANCELLED", "页面已关闭，导出已取消", null) }
        replies.clear()
        io.shutdownNow()
    }

    companion object {
        private const val REQUEST_WRITE_STORAGE = 1001
        private const val TAG = "NFC"
    }

    /**
     * MediaStore.Downloads 写入（API 29+ 无需权限）；
     * 同名文件由系统自动改名，回查实际文件名用于展示。
     */
    @RequiresApi(Build.VERSION_CODES.Q)
    private fun writeViaMediaStore(fileName: String, content: String): String {
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, fileName)
            put(MediaStore.Downloads.MIME_TYPE, "text/plain")
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val resolver = activity.contentResolver
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IOException("无法在下载目录创建文件")
        try {
            resolver.openOutputStream(uri)?.use { out ->
                out.write(content.toByteArray(Charsets.UTF_8))
            } ?: throw IOException("无法写入下载文件")
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        } catch (e: Exception) {
            // 写入失败时删除半成品条目，避免残留
            try {
                resolver.delete(uri, null, null)
            } catch (cleanupError: Exception) {
                Log.w(TAG, "Failed to clean pending download: ${cleanupError.message}")
            }
            throw e
        }
        val displayName = resolver.query(
            uri, arrayOf(MediaStore.Downloads.DISPLAY_NAME), null, null, null
        )?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else fileName
        } ?: fileName
        return "Download/$displayName"
    }

    /** 公共 Download 目录写入（API 26-28，需 WRITE_EXTERNAL_STORAGE）。 */
    @Suppress("DEPRECATION")
    private fun writeViaLegacyDownloads(fileName: String, content: String): String {
        val dir = Environment.getExternalStoragePublicDirectory(
            Environment.DIRECTORY_DOWNLOADS
        )
        if (!dir.exists() && !dir.mkdirs()) {
            throw IOException("无法创建下载目录")
        }
        val file = File(dir, fileName)
        file.writeText(content, Charsets.UTF_8)
        return file.absolutePath
    }

}
