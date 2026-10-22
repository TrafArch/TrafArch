package com.kajolno.TrafArch.nfc

import android.nfc.Tag
import android.nfc.tech.IsoDep
import android.nfc.tech.MifareClassic
import android.nfc.tech.NfcA
import android.nfc.tech.NfcB
import android.nfc.tech.NfcF
import android.nfc.tech.NfcV
import android.util.Log
import java.util.Locale

/** Metadata and the existing best-effort probes, called only by the session I/O worker. */
internal class TagMetadataReader {
    fun read(tag: Tag, access: SessionTagAccess): TagDiscovery {
        access.checkActive()
        val issues = mutableListOf<Map<String, String?>>()
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
            issue(issues, "read NFC-A", e)
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
            issue(issues, "read NFC-B", e)
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
            issue(issues, "read NFC-F", e)
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
            issue(issues, "read NFC-V", e)
        }

        // MIFARE Classic：保留原有块 0 尝试；不能读取时仅记录问题，不增加认证。
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
                    access.own(mfc)
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
                    issue(issues, "read MIFARE manufacturer block", e)
                } finally {
                    // 读取完成后释放 MIFARE 连接，避免连接泄漏
                    try {
                        access.release(mfc)
                    } catch (e: Exception) {
                        issue(issues, "close MIFARE Classic", e)
                    }
                }
            }
        } catch (e: Exception) {
            issue(issues, "read MIFARE Classic", e)
        }

        // ISO-DEP：ATS（historicalBytes）/ 高一层响应 / 最大帧长
        var historicalBytes: String? = null
        var hiLayerResponse: String? = null
        var maxLen: Int? = null
        var connected = false

        var connection: NfcConnection? = null
        val isoDep = try { IsoDep.get(tag) } catch (e: Exception) {
            issue(issues, "ISO-DEP metadata", e)
            null
        }
        if (isoDep != null) {
            try {
                access.own(isoDep)
                isoDep.timeout = 5000
                isoDep.connect()
                connected = isoDep.isConnected
                maxLen = isoDep.maxTransceiveLength
                historicalBytes = isoDep.historicalBytes?.toHex()
                hiLayerResponse = isoDep.hiLayerResponse?.toHex()
            } catch (e: Exception) {
                issue(issues, "ISO-DEP", e)
            }
            if (connected) {
                connection = IsoDepConnection(isoDep)
            } else {
                try { access.release(isoDep) } catch (e: Exception) {
                    issue(issues, "ISO-DEP close", e)
                }
            }
        }

        // Keep ISO-DEP priority and the original 3000 ms NFC-F timeout.
        var felicaConnected = false
        access.checkActive()
        if (!connected) {
            val nfcF = try { NfcF.get(tag) } catch (e: Exception) {
                issue(issues, "NFC-F metadata", e)
                null
            }
            if (nfcF != null) {
                try {
                    access.own(nfcF)
                    if (!nfcF.isConnected) {
                        nfcF.timeout = 3000
                        nfcF.connect()
                    }
                    felicaConnected = nfcF.isConnected
                    if (felicaConnected) connection = FelicaNfcBridge(nfcF)
                } catch (e: Exception) {
                    issue(issues, "NFC-F connect", e)
                }
                if (!felicaConnected) {
                    try { access.release(nfcF) } catch (e: Exception) {
                        issue(issues, "NFC-F close", e)
                    }
                }
            }
        }
        access.checkActive()

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
            "felicaConnected" to felicaConnected,
            "timestamp" to java.time.Instant.now().toString()
        )

        if (issues.isNotEmpty()) map["metadataIssues"] = issues
        return TagDiscovery(map, connection)
    }

    private fun issue(issues: MutableList<Map<String, String?>>, stage: String, error: Exception) {
        if (error is NfcSessionClosed) throw error
        Log.w("NFC", "$stage: ${error.message}")
        issues.add(mapOf("stage" to stage, "exception" to error.javaClass.name, "message" to error.message))
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

}

private fun ByteArray.toHex(): String =
    joinToString(" ") { String.format(Locale.US, "%02X", it.toInt() and 0xFF) }
