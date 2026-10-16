package com.example.smart_dustbin

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.provider.Settings

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ecosort/settings")
            .setMethodCallHandler { call, result ->
                if (call.method == "openWifiSettings") {
                    try {
                        startActivity(Intent(Settings.ACTION_WIFI_SETTINGS))
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("unavailable", "Open Wi-Fi in phone settings", null)
                    }
                } else result.notImplemented()
            }
    }
}
