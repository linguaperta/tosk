package io.github.timoverlaan.tosk

import android.content.Context
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
 * Nothing from the Onyx SDK is touched unless the device is an ONYX device,
 * and even then only LAZILY, on the first refresh / pen call (never at app
 * start). A crash guard protects against SDK code that kills the process
 * natively (uncatchable): a marker is written before the SDK is initialised
 * and cleared afterwards; if the app finds the marker still set on a later
 * start, the previous init crashed, and the Onyx features stay off for good
 * (Dart falls back to its own canvas; no e-ink refresh).
 */
class MainActivity : FlutterActivity() {
    private var onyx: OnyxBridge? = null
    private var onyxTried = false
    private var penChannel: MethodChannel? = null

    private val prefs by lazy { getSharedPreferences("tosk_native", Context.MODE_PRIVATE) }

    /** The Onyx bridge, created on first use; null when unavailable or disabled. */
    private fun onyxBridge(): OnyxBridge? {
        if (onyxTried) return onyx
        onyxTried = true
        if (!isOnyxDevice() || prefs.getBoolean(KEY_DISABLED, false)) return null
        if (prefs.getBoolean(KEY_PENDING, false)) {
            // The last init never finished: it crashed the app. Don't try again.
            Log.w(TAG, "Onyx SDK crashed during a previous init; disabled")
            prefs.edit().putBoolean(KEY_DISABLED, true).putBoolean(KEY_PENDING, false).commit()
            return null
        }
        onyx = guarded {
            try {
                OnyxBridge(this, penChannel!!)
            } catch (t: Throwable) {
                Log.w(TAG, "Onyx SDK unavailable", t)
                null
            }
        }
        return onyx
    }

    /**
     * Runs an Onyx SDK call with the crash marker set, so a native crash inside
     * it (which no try/catch can see) disables the Onyx features on next start.
     */
    private fun <T> guarded(block: () -> T): T {
        prefs.edit().putBoolean(KEY_PENDING, true).commit()
        try {
            return block()
        } finally {
            prefs.edit().putBoolean(KEY_PENDING, false).commit()
        }
    }

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
        penChannel = pen
        epd.setMethodCallHandler { call, result ->
            when (call.method) {
                "fullRefresh" -> result.success(onyxBridge()?.let { b -> guarded { b.fullRefresh() } } ?: false)
                else -> result.notImplemented()
            }
        }
        pen.setMethodCallHandler { call, result ->
            val bridge = if (call.method == "close") onyx else onyxBridge()
            if (bridge == null) {
                // Not an ONYX device (or the SDK failed): Dart uses its canvas.
                result.success(false)
            } else {
                guarded { bridge.handle(call, result) }
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
        private const val KEY_PENDING = "onyx_init_pending"
        private const val KEY_DISABLED = "onyx_disabled"

        fun isOnyxDevice(): Boolean {
            val m = (Build.MANUFACTURER ?: "").lowercase()
            val b = (Build.BRAND ?: "").lowercase()
            return m.contains("onyx") || b.contains("onyx")
        }
    }
}
