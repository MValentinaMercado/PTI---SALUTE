package com.example.saluteapp

import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {

    private var sosSms: SosSmsChannel? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Canal del SOS: envío real de SMS (ver SosSmsChannel.kt).
        val handler = SosSmsChannel(this)
        sosSms = handler
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SosSmsChannel.CHANNEL)
            .setMethodCallHandler(handler)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        sosSms?.onPermissionResult(requestCode, grantResults)
    }
}
