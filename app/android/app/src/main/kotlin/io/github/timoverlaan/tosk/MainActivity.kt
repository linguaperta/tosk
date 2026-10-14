package io.github.timoverlaan.tosk

import android.os.Build
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Platform channels of the app itself (v0.5):
 *
 * - `tosk/device`: `info` -> manufacturer, brand, model, sdk. Dart uses it
 *   to detect ONYX (Boox) e-readers; no plugin needed.
 * - `tosk/onyx`: `fullRefresh` -> a full e-ink (GC) refresh through the
 *   Onyx SDK's EpdController. A no-op (false) on other devices.
 * - `tosk/onyx_pen`: low-latency raw drawing with the Onyx pen SDK
 *   (TouchHelper) inside the writing pad's rectangle; strokes are sent back
 *   to Dart as point lists for handwriting recognition. See [OnyxBridge].
 *
 * Nothing from the Onyx SDK is touched unless the device is an ONYX device:
 * [OnyxBridge] is only loaded then, and every SDK call is guarded, so a
 * failing SDK falls back to the Flutter canvas.
 */
class MainActivity : FlutterActivity() {
    private var onyx: OnyxBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, "tosk/device").setMethodCallHandler { call, result ->
            when (call.method) {
                "info" -> result.success(
                    mapOf(
                        "manufacturer" to (Build.MANUFACTURER ?: ""),
                        "brand" to (Build.BRAND ?: ""),
                        "model" to (Build.MODEL ?: ""),
                        "sdk" to Build.VERSION.SDK_INT,
                    )
                )
                else -> result.notImplemented()
            }
        }

        val epd = MethodChannel(messenger, "tosk/onyx")
        val pen = MethodChannel(messenger, "tosk/onyx_pen")
        if (isOnyxDevice()) {
            try {
                onyx = OnyxBridge(this, pen)
            } catch (t: Throwable) {
                Log.w(TAG, "Onyx SDK unavailable", t)
                onyx = null
            }
        }
        epd.setMethodCallHandler { call, result ->
            val bridge = onyx
            when (call.method) {
                "fullRefresh" -> result.success(bridge?.fullRefresh() ?: false)
                else -> result.notImplemented()
            }
        }
        pen.setMethodCallHandler { call, result ->
            val bridge = onyx
            if (bridge == null) {
                // Not an ONYX device (or the SDK failed): Dart uses its canvas.
                result.success(false)
            } else {
                bridge.handle(call, result)
            }
        }
    }

    override fun onPause() {
        onyx?.pause()
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        onyx?.resume()
    }

    override fun onDestroy() {
        onyx?.dispose()
        onyx = null
        super.onDestroy()
    }

    companion object {
        private const val TAG = "tosk"

        fun isOnyxDevice(): Boolean {
            val m = (Build.MANUFACTURER ?: "").lowercase()
            val b = (Build.BRAND ?: "").lowercase()
            return m.contains("onyx") || b.contains("onyx")
        }
    }
}
