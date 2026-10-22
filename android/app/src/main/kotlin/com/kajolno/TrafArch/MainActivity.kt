package com.kajolno.TrafArch

import android.content.Intent
import com.kajolno.TrafArch.nfc.NfcChannelHandler
import com.kajolno.TrafArch.qr.GmsQrHandler
import com.kajolno.TrafArch.qr.QrImageHandler
import com.kajolno.TrafArch.storage.FileExportHandler
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/** Android composition root: channels own their pending requests and native resources. */
class MainActivity : FlutterActivity() {
    private var nfc: NfcChannelHandler? = null
    private var qrImage: QrImageHandler? = null
    private var gmsQr: GmsQrHandler? = null
    private var fileExport: FileExportHandler? = null
    private var foreground = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        disposeHandlers()
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        nfc = NfcChannelHandler(this, messenger)
        qrImage = QrImageHandler(this, messenger)
        gmsQr = GmsQrHandler(this, messenger)
        fileExport = FileExportHandler(this, messenger)
        if (foreground) nfc?.onResume()
    }

    override fun onResume() {
        super.onResume()
        foreground = true
        nfc?.onResume()
    }

    override fun onPause() {
        foreground = false
        nfc?.onPause()
        super.onPause()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        fileExport?.onRequestPermissionsResult(requestCode, grantResults)
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        qrImage?.onActivityResult(requestCode, resultCode, data)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        disposeHandlers()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        disposeHandlers()
        super.onDestroy()
    }

    private fun disposeHandlers() {
        nfc?.dispose()
        qrImage?.dispose()
        gmsQr?.dispose()
        fileExport?.dispose()
        nfc = null
        qrImage = null
        gmsQr = null
        fileExport = null
    }
}
