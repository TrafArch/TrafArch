package com.kajolno.TrafArch

import android.Manifest
import android.content.ContentValues
import android.content.pm.PackageManager
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.nfc.tech.IsoDep
import android.nfc.tech.MifareClassic
import android.nfc.tech.NfcA
import android.nfc.tech.NfcB
import android.nfc.tech.NfcF
import android.nfc.tech.NfcV
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.Locale

class MainActivity : FlutterActivity(), NfcAdapter.ReaderCallback {
    companion object {
        private const val CHANNEL = "transit_card_analyzer/nfc"
        private const val EXPORT_CHANNEL = "transit_card_analyzer/export"
        private const val REQUEST_WRITE_STORAGE = 1001
        private const val TAG = "NFC"

        // 轮询 NFC-A/B/F/V 全部非接触协议，跳过 NDEF 检查
        private val READER_FLAGS = NfcAdapter.FLAG_READER_NFC_A or
                NfcAdapter.FLAG_READER_NFC_B or
                NfcAdapter.FLAG_READER_NFC_F or
                NfcAdapter.FLAG_READER_NFC_V or
                NfcAdapter.FLAG_READER_SKIP_NDEF_CHECK
    }

    private var nfcAdapter: NfcAdapter? = null
    
    @Volatile
    private var pendingResult: MethodChannel.Result? = null

    @Volatile
    private var isoDep: IsoDep? = null

    // 导出等待存储权限期间挂起的请求（仅 Android 9- 需要）
    @Volatile
    private var pendingExportResult: MethodChannel.Result? = null
    private var pendingExportPayload: Pair<String, String>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        nfcAdapter = NfcAdapter.getDefaultAdapter(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "scanOnce" -> startScan(result)
                    "stopScan" -> stopScan(result)
                    "transceive" -> transceive(call, result)
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, EXPORT_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveToDownloads" -> exportToDownloads(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    override fun onResume() {
        super.onResume()
        // 回到前台：若仍在等待标签（扫描未被取消），恢复 Reader Mode。
        // 部分系统在应用退到后台时会自动关闭 Reader Mode，
        // 不恢复会导致等待中的 scanOnce 永远收不到回调。
        val waiting = synchronized(this) { pendingResult != null }
        val adapter = nfcAdapter
        if (waiting && adapter != null && adapter.isEnabled) {
            try {
                adapter.enableReaderMode(this, this, READER_FLAGS, null)
            } catch (e: Exception) {
                Log.w(TAG, "Failed to restore reader mode: ${e.message}")
            }
        }
    }

    override fun onPause() {
        super.onPause()
        // 退到后台：仅在等待标签期间关闭 Reader Mode，避免后台读卡；
        // 若标签已发现（解析/transceive 进行中）则保持连接，防止读取失败。
        val waiting = synchronized(this) { pendingResult != null }
        if (waiting) {
            nfcAdapter?.disableReaderMode(this)
        }
    }

    private fun transceive(call: MethodCall, result: MethodChannel.Result) {
        val apduBytes = (call.arguments as? List<*>)?.map { (it as Number).toByte() }?.toByteArray()
        if (apduBytes == null) {
            result.error("BAD_ARGUMENT", "APDU 数据格式错误", null)
            return
        }
        val tag = synchronized(this) { isoDep }
        if (tag == null || !tag.isConnected) {
            result.error("TAG_NOT_CONNECTED", "ISO-DEP 未连接", null)
            return
        }
        Thread {
            try {
                val resp = tag.transceive(apduBytes)
                // 直接回传 ByteArray：Dart 端收到 Uint8List（0~255 无符号）。
                // 若改为 resp.toList()，元素为有符号 Byte（-128~127），
                // 会导致 Dart 端 SW 判断（0x9000）与 HEX/金额解析全部出错。
                result.success(resp)
            } catch (e: Exception) {
                Log.w(TAG, "transceive failed: ${e.message}")
                result.error("TRANSCEIVE_FAILED", e.message, null)
            }
        }.start()
    }

    private fun startScan(result: MethodChannel.Result) {
        if (nfcAdapter == null) {
            result.error("NFC_UNAVAILABLE", "当前设备没有 NFC", null)
            return
        }
        if (!nfcAdapter!!.isEnabled) {
            result.error("NFC_DISABLED", "请先打开系统 NFC", null)
            return
        }

        synchronized(this) {
            pendingResult = result
        }

        nfcAdapter!!.enableReaderMode(this, this, READER_FLAGS, null)
    }

    private fun stopScan(result: MethodChannel.Result? = null) {
        nfcAdapter?.disableReaderMode(this)
        synchronized(this) {
            pendingResult?.error("NFC_STOPPED", "扫描已停止", null)
            pendingResult = null
            try {
                isoDep?.close()
            } catch (e: Exception) {
                Log.w(TAG, "Failed to close ISO-DEP: ${e.message}")
            }
            isoDep = null
        }
        // 必须回传 result：Dart 端 await stopScan() 依赖该 Future 完成来复位
        // 扫描状态（否则首页“再次读取”按钮永远不出现）。
        // onDestroy 等主动调用方不等待结果，传 null 即可
        result?.success(null)
    }

    /**
     * 将文本内容保存到系统下载目录（导出运行日志）。
     * - Android 10+（API 29+）：MediaStore Downloads，无需存储权限；
     * - Android 9-（API 26-28）：公共 Download 目录，需 WRITE_EXTERNAL_STORAGE，
     *   未授权时发起运行时请求，结果在 onRequestPermissionsResult 中续接。
     */
    private fun exportToDownloads(call: MethodCall, result: MethodChannel.Result) {
        val fileName = call.argument<String>("fileName")
        val content = call.argument<String>("content")
        if (fileName.isNullOrBlank() || content == null) {
            result.error("BAD_ARGUMENT", "导出参数缺失", null)
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ||
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            writeToDownloads(fileName, content, result)
            return
        }

        synchronized(this) {
            pendingExportResult = result
            pendingExportPayload = fileName to content
        }
        requestPermissions(
            arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
            REQUEST_WRITE_STORAGE
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_WRITE_STORAGE) return

        // 无论授权与否都必须回传 result，避免 Dart 端 await 永久挂起
        var exportResult: MethodChannel.Result? = null
        var payload: Pair<String, String>? = null
        synchronized(this) {
            exportResult = pendingExportResult
            payload = pendingExportPayload
            pendingExportResult = null
            pendingExportPayload = null
        }
        val result = exportResult ?: return
        val data = payload
        // payload 与 result 理论成对出现；兜底回传避免极端情况下 Dart 端 await 挂起
        if (data == null) {
            result.error("EXPORT_FAILED", "导出请求状态异常，请重试", null)
            return
        }

        if (grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        ) {
            writeToDownloads(data.first, data.second, result)
        } else {
            result.error("PERMISSION_DENIED", "未授予存储权限，无法导出到下载目录", null)
        }
    }

    /** 后台线程执行实际写入，完成后回主线程回传结果。 */
    private fun writeToDownloads(
        fileName: String,
        content: String,
        result: MethodChannel.Result
    ) {
        Thread {
            try {
                val savedPath: String
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    savedPath = writeViaMediaStore(fileName, content)
                } else {
                    savedPath = writeViaLegacyDownloads(fileName, content)
                }
                runOnUiThread { result.success(savedPath) }
            } catch (e: Exception) {
                Log.w(TAG, "Export log failed: ${e.message}")
                runOnUiThread {
                    result.error("EXPORT_FAILED", e.message ?: "导出失败", null)
                }
            }
        }.start()
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
        val resolver = contentResolver
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

    override fun onTagDiscovered(tag: Tag) {
        val result: MethodChannel.Result
        synchronized(this) {
            result = pendingResult ?: return
            pendingResult = null
        }

        val uid = tag.id?.toHex() ?: ""
        val techs = tag.techList?.map { it.substringAfterLast('.') } ?: emptyList()

        // NFC-A：ATQA / SAK（据此识别卡型）
        var atqa: String? = null
        var sak: String? = null
        try {
            val nfcA = NfcA.get(tag)
            if (nfcA != null) {
                atqa = nfcA.atqa?.toHex()
                sak = String.format(Locale.US, "%02X", nfcA.sak.toInt() and 0xFF)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to read NFC-A: ${e.message}")
        }

        // NFC-B：应用数据 / 协议信息
        var nfcBAppData: String? = null
        var nfcBProtocolInfo: String? = null
        try {
            val nfcB = NfcB.get(tag)
            if (nfcB != null) {
                nfcBAppData = nfcB.applicationData?.toHex()
                nfcBProtocolInfo = nfcB.protocolInfo?.toHex()
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to read NFC-B: ${e.message}")
        }

        // NFC-F（FeliCa 系）：系统码 / 制造商
        var nfcFSystemCode: String? = null
        var nfcFManufacturer: String? = null
        try {
            val nfcF = NfcF.get(tag)
            if (nfcF != null) {
                nfcFSystemCode = nfcF.systemCode?.toHex()
                nfcFManufacturer = nfcF.manufacturer?.toHex()
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to read NFC-F: ${e.message}")
        }

        // NFC-V（ISO 15693）：DSFID / 响应标志
        var nfcVDsfId: String? = null
        var nfcVResponseFlags: String? = null
        try {
            val nfcV = NfcV.get(tag)
            if (nfcV != null) {
                nfcVDsfId = String.format(Locale.US, "%02X", nfcV.dsfId.toInt() and 0xFF)
                nfcVResponseFlags =
                    String.format(Locale.US, "%02X", nfcV.responseFlags.toInt() and 0xFF)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to read NFC-V: ${e.message}")
        }

        // MIFARE Classic：卡型 / 容量 / 扇区块数 / 厂商块（块 0，无需认证）
        var mifareType: String? = null
        var mifareSize: Int? = null
        var mifareSectorCount: Int? = null
        var mifareBlockCount: Int? = null
        var mifareManufacturerBlock: String? = null
        var mifareBccValid: Boolean? = null
        try {
            val mfc = MifareClassic.get(tag)
            if (mfc != null) {
                mifareType = mfc.type.toString()
                mifareSize = mfc.size
                mifareSectorCount = mfc.sectorCount
                mifareBlockCount = mfc.blockCount
                try {
                    mfc.connect()
                    if (mfc.isConnected) {
                        val block0 = mfc.readBlock(0)
                        mifareManufacturerBlock = block0.toHex()
                        if (block0.size >= 5) {
                            val expectedBcc = (block0[0].toInt() and 0xFF) xor
                                    (block0[1].toInt() and 0xFF) xor
                                    (block0[2].toInt() and 0xFF) xor
                                    (block0[3].toInt() and 0xFF)
                            mifareBccValid = (block0[4].toInt() and 0xFF) == expectedBcc
                        }
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to read MIFARE manufacturer block: ${e.message}")
                } finally {
                    // 读取完成后释放 MIFARE 连接，避免连接泄漏
                    try {
                        mfc.close()
                    } catch (e: Exception) {
                        Log.w(TAG, "Failed to close MIFARE Classic: ${e.message}")
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to read MIFARE Classic: ${e.message}")
        }

        // ISO-DEP：ATS（historicalBytes）/ 高一层响应 / 最大帧长
        var historicalBytes: String? = null
        var hiLayerResponse: String? = null
        var maxLen: Int? = null
        var connected = false

        try {
            val isoDep = IsoDep.get(tag)
            if (isoDep != null) {
                isoDep.timeout = 5000
                isoDep.connect()
                connected = isoDep.isConnected
                maxLen = isoDep.maxTransceiveLength
                historicalBytes = isoDep.historicalBytes?.toHex()
                hiLayerResponse = isoDep.hiLayerResponse?.toHex()
                synchronized(this) { this.isoDep = isoDep }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to read ISO-DEP: ${e.message}")
        }

        // ATQA/SAK -> 卡型，历史字节 -> 解读
        val cardType = identifyCardType(atqa, sak, techs, connected)
        val atsDescription = describeHistoricalBytes(historicalBytes)

        val map = hashMapOf<String, Any?>(
            "uid" to uid,
            "technologies" to techs,
            "atqa" to atqa,
            "sak" to sak,
            "ats" to historicalBytes,
            "historicalBytes" to historicalBytes,
            "hiLayerResponse" to hiLayerResponse,
            "nfcBApplicationData" to nfcBAppData,
            "nfcBProtocolInfo" to nfcBProtocolInfo,
            "nfcFSystemCode" to nfcFSystemCode,
            "nfcFManufacturer" to nfcFManufacturer,
            "nfcVDsfId" to nfcVDsfId,
            "nfcVResponseFlags" to nfcVResponseFlags,
            "mifareType" to mifareType,
            "mifareSize" to mifareSize,
            "mifareSectorCount" to mifareSectorCount,
            "mifareBlockCount" to mifareBlockCount,
            "mifareManufacturerBlock" to mifareManufacturerBlock,
            "mifareBccValid" to mifareBccValid,
            "cardType" to cardType,
            "atsDescription" to atsDescription,
            "maxTransceiveLength" to maxLen,
            "tagDescription" to tag.toString(),
            "isoDepConnected" to connected,
            "timestamp" to java.time.Instant.now().toString()
        )

        // 立即回传标签信息，但保持 Reader Mode 与 IsoDep 连接。
        // 后续 APDU（SELECT / READ BINARY / READ RECORD）由 Dart 层完成，
        // 解析结束后由 Dart 层调用 stopScan() 统一关闭连接，
        // 避免部分设备因过早 disableReaderMode 导致 transceive 失败。
        result.success(map)
    }

    /**
     * ATQA/SAK 组合判断，兼容两种字节序。
     */
    private fun identifyCardType(
        atqa: String?,
        sak: String?,
        techs: List<String>,
        isoDepConnected: Boolean,
    ): String {
        val atqaVal = atqa?.replace(" ", "")?.uppercase(Locale.US)
        val sakVal = sak?.replace(" ", "")?.uppercase(Locale.US)
        val hasNfcA = techs.any { it.equals("NfcA", ignoreCase = true) }

        when {
            atqaMatches(atqaVal, "000C") && sakVal == "01" ->
                return "Topaz 512 (NFC Forum Type 1)"
            atqaMatches(atqaVal, "0004") && sakVal == "08" -> return "MIFARE Classic 1K"
            atqaMatches(atqaVal, "0002") && sakVal == "18" -> return "MIFARE Classic 4K"
            atqaMatches(atqaVal, "0004") && sakVal == "09" -> return "MIFARE Mini 0.3K"
            atqaMatches(atqaVal, "0044") && sakVal == "00" -> return "MIFARE Ultralight"
            atqaMatches(atqaVal, "0344") && sakVal == "20" ->
                return "MIFARE DESFire / DESFire EV1"
            atqaMatches(atqaVal, "0400") && sakVal == "20" ->
                return "MIFARE DESFire EV2 / EV3"
            sakVal == "10" && hasNfcA -> return "MIFARE Plus SL1"
            sakVal == "11" && hasNfcA -> return "MIFARE Plus SL3"
            sakVal == "28" && hasNfcA -> return "JCOP (NXP Java Card)"
            sakVal == "38" && hasNfcA -> return "NXP SmartMX2 / SmartMX3"
        }

        return when {
            isoDepConnected -> "ISO 14443-4 CPU 卡"
            hasNfcA -> "NFC-A 存储卡"
            techs.any { it.equals("NfcB", ignoreCase = true) } -> "NFC-B 卡"
            techs.any { it.equals("NfcF", ignoreCase = true) } -> "NFC-F (FeliCa) 卡"
            techs.any { it.equals("NfcV", ignoreCase = true) } -> "NFC-V (ISO 15693) 卡"
            else -> "未知卡型"
        }
    }

    private fun atqaMatches(value: String?, candidate: String): Boolean {
        if (value == null || value.length != candidate.length) return false
        return value == candidate ||
                value == candidate.chunked(2).reversed().joinToString("")
    }

    /**
     * 解读 ISO/IEC 7816-4 历史字节。
     *
     * 注意：Android 的 IsoDep.historicalBytes 只提供 ATS 的历史字节（T1..Tk），
     * TL / T0 及接口字节（TAi / TBi / TCi）由系统剥离、应用层不可见，
     * 因此这里不做 TL/T0 结构解析，避免错位解析产生误导性描述。
     */
    private fun describeHistoricalBytes(bytesHex: String?): String? {
        val bytes = bytesHex?.split(" ")?.mapNotNull { it.toIntOrNull(16) } ?: return null
        if (bytes.isEmpty()) return null
        val category = bytes[0]
        val categoryDesc = when {
            category == 0x00 -> "状态字节对"
            category == 0x80 -> "国家/发卡方信息"
            else -> String.format(Locale.US, "类别 0x%02X", category)
        }
        return "历史字节 ${bytes.size} 字节（$categoryDesc；ATS 的 TL/T0 不可见）"
    }

    override fun onDestroy() {
        // 权限等待中的导出请求：回传取消，避免 Dart 端 await 永久挂起
        var exportResult: MethodChannel.Result? = null
        synchronized(this) {
            exportResult = pendingExportResult
            pendingExportResult = null
            pendingExportPayload = null
        }
        exportResult?.error("EXPORT_CANCELLED", "页面已关闭，导出已取消", null)

        stopScan()
        super.onDestroy()
    }
}

private fun ByteArray.toHex(): String =
    joinToString(" ") { String.format(Locale.US, "%02X", it.toInt() and 0xFF) }
