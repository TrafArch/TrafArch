package com.kajolno.TrafArch.nfc

import android.nfc.Tag
import android.nfc.tech.NfcF
import java.io.IOException

/**
 * NFC-F（FeliCa）通信桥：只负责连接、原始帧收发与关闭，
 * 不解析 Suica / 八达通的业务记录（解析全部在 Dart 层）。
 *
 * 线程约束：attach 由标签回调线程调用，transceive 由 MainActivity
 * 的后台线程调用；本类只做同步 I/O，不切换线程。
 */
class FelicaNfcBridge {

    @Volatile
    private var nfcF: NfcF? = null

    /** 连接 NfcF 并保存句柄；失败抛 IOException，由调用方记录。 */
    @Synchronized
    fun attach(tag: Tag) {
        val tech = NfcF.get(tag) ?: throw IOException("当前标签不支持 NFC-F")
        if (!tech.isConnected) {
            tech.timeout = 3000
            tech.connect()
        }
        nfcF = tech
    }

    @Synchronized
    fun isConnected(): Boolean = nfcF?.isConnected == true

    /** 发送完整 FeliCa 帧（含 LEN），返回完整响应帧（含 LEN）。 */
    @Synchronized
    fun transceive(frame: ByteArray): ByteArray {
        val tech = nfcF ?: throw IOException("NFC-F 未连接")
        if (!tech.isConnected) throw IOException("NFC-F 连接已断开")
        if (frame.isEmpty()) throw IOException("FeliCa 帧为空")
        return tech.transceive(frame)
    }

    @Synchronized
    fun close() {
        val tech = nfcF ?: return
        nfcF = null
        try {
            if (tech.isConnected) tech.close()
        } catch (_: Exception) {
            // 标签离开 / 已断开时忽略关闭异常
        }
    }
}