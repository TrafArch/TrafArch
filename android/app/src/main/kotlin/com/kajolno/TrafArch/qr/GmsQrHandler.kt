package com.kajolno.TrafArch.qr

import android.app.Activity
import android.util.Log
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.common.api.CommonStatusCodes
import com.google.android.gms.common.moduleinstall.ModuleInstall
import com.google.android.gms.common.moduleinstall.ModuleInstallRequest
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScanner
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import com.kajolno.TrafArch.platform.OnceResult
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

internal class GmsQrHandler(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "transit_card_analyzer/gms_scan")
    private val io = Executors.newSingleThreadExecutor { Thread(it, "TrafArch-GMS-warmup") }
    @Volatile private var disposed = false
    @Volatile private var pendingGmsScanResult: OnceResult? = null
    @Volatile private var cachedGmsScanner: GmsBarcodeScanner? = null

    init {
        channel.setMethodCallHandler { call, rawResult ->
            val result = OnceResult(rawResult)
            when (call.method) {
                "isAvailable" -> result.success(isGmsScanAvailable())
                "warmUp" -> { warmUpGmsScan(); result.success(null) }
                "scan" -> startGmsScan(result)
                else -> result.notImplemented()
            }
        }
    }

    fun dispose() {
        synchronized(this) {
            if (disposed) return
            disposed = true
            pendingGmsScanResult?.error("SCAN_CANCELLED", "页面已关闭，扫码已取消", null)
            pendingGmsScanResult = null
            cachedGmsScanner = null
        }
        channel.setMethodCallHandler(null)
        io.shutdownNow()
    }

    companion object { private const val QR_TAG = "QRImage" }

    /**
     * 设备是否具备 Google Play 服务扫码能力（Google Code Scanner API）。
     * 扫码界面与相机由 GMS 进程提供，应用侧无需申请相机权限。
     */
    private fun isGmsScanAvailable(): Boolean {
        return try {
            GoogleApiAvailability.getInstance()
                .isGooglePlayServicesAvailable(activity) == ConnectionResult.SUCCESS
        } catch (e: Exception) {
            Log.w(QR_TAG, "Failed to check Google Play services: ${e.message}")
            false
        }
    }

    /**
     * 调起 Google Play 服务扫码界面（Google Code Scanner）扫描二维码：
     * 扫码 UI 与相机在 GMS 进程内完成，应用不申请相机权限。
     * 复用缓存的扫码器（见 [gmsScanner]），避免每次扫码重复初始化。
     * - 识别成功：回传原始载荷字节（优先 rawBytes——JT/T 1179 为 8 bit byte
     *   模式，文本会损坏数据；缺失时按 ISO-8859-1 还原文本字节）；
     * - 用户取消 / 未识别：回传 null；
     * - 服务不可用 / 扫码失败：回传错误，由 Dart 端处理。
     */
    private fun startGmsScan(result: OnceResult) {
        if (disposed) {
            result.error("SCAN_CANCELLED", "页面已关闭，扫码已取消", null)
            return
        }
        if (!isGmsScanAvailable()) {
            result.error("GMS_UNAVAILABLE", "当前设备未安装或未启用 Google Play 服务", null)
            return
        }
        synchronized(this) {
            if (pendingGmsScanResult != null) {
                result.error("SCAN_IN_PROGRESS", "Google 扫码已在进行中", null)
                return
            }
            pendingGmsScanResult = result
        }

        try {
            gmsScanner().startScan()
                .addOnSuccessListener { barcode ->
                    val pending = takePendingGmsScanResult(result) ?: return@addOnSuccessListener
                    val bytes = barcode.rawBytes
                        ?: barcode.rawValue?.toByteArray(Charsets.ISO_8859_1)
                    if (bytes == null || bytes.isEmpty()) {
                        pending.success(null)
                    } else {
                        pending.success(bytes)
                    }
                }
                .addOnCanceledListener {
                    // 用户取消扫码
                    takePendingGmsScanResult(result)?.success(null)
                }
                .addOnFailureListener { e ->
                    val pending = takePendingGmsScanResult(result) ?: return@addOnFailureListener
                    if (e is ApiException && e.statusCode == CommonStatusCodes.CANCELED) {
                        // 部分 GMS 版本以失败回调上报用户取消
                        pending.success(null)
                    } else {
                        Log.w(QR_TAG, "GMS scan failed: ${e.message}")
                        pending.error("SCAN_FAILED", e.message ?: "Google 扫码失败", null)
                    }
                }
        } catch (e: Exception) {
            takePendingGmsScanResult(result)
                ?.error("SCAN_FAILED", e.message ?: "Google 扫码启动失败", null)
        }
    }

    /** 取出并清空 GMS 扫码挂起请求，保证无论成败只回传一次。 */
    private fun takePendingGmsScanResult(expected: OnceResult): OnceResult? = synchronized(this) {
        val current = pendingGmsScanResult
        if (current !== expected) return@synchronized null
        pendingGmsScanResult = null
        current
    }

    /** 懒创建并缓存 GMS 扫码器（仅 QR + 自动变焦，配置固定）；复用避免重复初始化。 */
    private fun gmsScanner(): GmsBarcodeScanner {
        if (disposed) throw IllegalStateException("页面已关闭")
        cachedGmsScanner?.let { return it }
        synchronized(this) {
            if (disposed) throw IllegalStateException("页面已关闭")
            cachedGmsScanner?.let { return it }
            val options = GmsBarcodeScannerOptions.Builder()
                .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
                .enableAutoZoom()
                .build()
            val scanner = GmsBarcodeScanning.getClient(activity, options)
            cachedGmsScanner = scanner
            return scanner
        }
    }

    /**
     * 后台预热 GMS 扫码，缩短首次调起扫码界面的等待时间：
     * - 提前创建并缓存扫码器（完成 GMS 服务绑定与初始化）；
     * - 检查 barcode_ui 扫码模块，缺失时请求后台尽快安装
     *   （安装时预下载仅对 Play 商店渠道生效，侧装 APK 由本预热兜底）。
     * 全程异步、不弹界面、失败静默（首次扫码仍会按需加载，不影响功能）。
     */
    private fun warmUpGmsScan() {
        io.execute {
            try {
                if (disposed || !isGmsScanAvailable()) return@execute
                val scanner = gmsScanner()
                val moduleInstallClient = ModuleInstall.getClient(activity)
                moduleInstallClient.areModulesAvailable(scanner)
                    .addOnSuccessListener { response ->
                        if (!disposed && !response.areModulesAvailable()) {
                            Log.i(QR_TAG, "Scanner module missing, requesting install")
                            moduleInstallClient.installModules(
                                ModuleInstallRequest.newBuilder()
                                    .addApi(scanner)
                                    .build()
                            )
                                .addOnSuccessListener {
                                    Log.i(QR_TAG, "Scanner module install requested")
                                }
                                .addOnFailureListener { e ->
                                    Log.w(QR_TAG, "Failed to install scanner module: ${e.message}")
                                }
                        }
                    }
                    .addOnFailureListener { e ->
                        Log.w(QR_TAG, "Failed to check scanner module: ${e.message}")
                    }
            } catch (e: Exception) {
                Log.w(QR_TAG, "GMS scan warm-up failed: ${e.message}")
            }
        }
    }

}
