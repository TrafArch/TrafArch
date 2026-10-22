package com.kajolno.TrafArch.qr

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.provider.MediaStore
import android.util.Log
import com.kajolno.TrafArch.platform.OnceResult
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.concurrent.Executors

internal class QrImageHandler(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "transit_card_analyzer/qr_image")
    private val io = Executors.newSingleThreadExecutor { Thread(it, "TrafArch-QR-image") }
    private var pending: OnceResult? = null
    private var copying = false
    private var disposed = false

    init {
        channel.setMethodCallHandler { call, rawResult ->
            val result = OnceResult(rawResult)
            if (call.method == "pickImage") pickImage(result) else result.notImplemented()
        }
    }

    @Suppress("DEPRECATION", "InlinedApi")
    private fun pickImage(result: OnceResult) {
        if (disposed) {
            result.error("PICK_CANCELLED", "页面已关闭，相册选择已取消", null)
            return
        }
        if (pending != null) {
            result.error("PICK_IN_PROGRESS", "相册选择已在进行中", null)
            return
        }
        pending = result
        try {
            try {
                activity.startActivityForResult(
                    Intent(MediaStore.ACTION_PICK_IMAGES).apply { type = "image/*" }, REQUEST_PICK_QR_IMAGE,
                )
            } catch (error: ActivityNotFoundException) {
                Log.w("QRImage", "Photo picker unavailable, fallback to GET_CONTENT: ${error.message}")
                activity.startActivityForResult(
                    Intent(Intent.ACTION_GET_CONTENT).apply {
                        type = "image/*"
                        addCategory(Intent.CATEGORY_OPENABLE)
                    }, REQUEST_PICK_QR_IMAGE,
                )
            }
        } catch (error: Exception) {
            pending = null
            result.error("PICKER_UNAVAILABLE", "未找到可用的相册/文件选择器", null)
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != REQUEST_PICK_QR_IMAGE || copying) return
        val result = pending ?: return
        val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
        if (uri == null) {
            pending = null
            result.success(null)
            return
        }
        // Keep the captured reply registered until the copy completes or disposal cancels it.
        copying = true
        io.execute {
            try {
                val path = cachePickedImage(uri)
                activity.runOnUiThread {
                    if (pending === result) { pending = null; copying = false }
                    result.success(path)
                }
            } catch (error: Exception) {
                Log.w("QRImage", "Failed to cache picked image: ${error.message}")
                activity.runOnUiThread {
                    if (pending === result) { pending = null; copying = false }
                    result.error("IMAGE_READ_FAILED", error.message ?: "读取所选图片失败", null)
                }
            }
        }
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        channel.setMethodCallHandler(null)
        pending?.error("PICK_CANCELLED", "页面已关闭，相册选择已取消", null)
        pending = null
        copying = false
        io.shutdownNow()
    }

    companion object { private const val REQUEST_PICK_QR_IMAGE = 1002 }

    /** 将所选图片复制到应用私有缓存目录（每次选择前清理旧文件），返回绝对路径。 */
    private fun cachePickedImage(uri: Uri): String {
        val dir = File(activity.cacheDir, "qr_picked")
        if (dir.exists()) {
            dir.listFiles()?.forEach { it.delete() }
        } else {
            dir.mkdirs()
        }
        val file = File(dir, "picked_${System.currentTimeMillis()}.img")
        activity.contentResolver.openInputStream(uri)?.use { input ->
            file.outputStream().use { output -> input.copyTo(output) }
        } ?: throw IOException("无法打开所选图片")
        return file.absolutePath
    }

}
