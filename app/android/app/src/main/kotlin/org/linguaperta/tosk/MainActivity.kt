package org.linguaperta.tosk

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Platform channels of the app itself (v0.5):
 *
 * - `tosk/device`: `info` -> manufacturer, brand, model, sdk, abis. Dart uses
 *   it to detect ONYX (Boox) e-readers and to pick the APK of an app update
 *   (`Build.SUPPORTED_ABIS`); no plugin needed. `openTtsSettings` opens the
 *   text-to-speech settings (the "install a voice" notice);
 *   `openNotificationSettings` the app's notification settings (the daily
 *   reminder when notifications are off for tosk).
 *
 * All app audio (speech and sound effects) plays on the media stream, so the
 * volume keys adjust the media volume in the app, even when nothing plays.
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

    private val prefs by lazy { getSharedPreferences(PREFS, Context.MODE_PRIVATE) }

    /** The Onyx bridge, created on first use; null when unavailable or disabled. */
    private fun onyxBridge(): OnyxBridge? {
        if (onyxTried) return onyx
        onyxTried = true
        // A previous Onyx call that never returned (native crash) is detected at
        // app start by [ToskApplication], which sets KEY_DISABLED.
        if (!isOnyxDevice() || prefs.getBoolean(KEY_DISABLED, false)) return null
        onyx = guarded("init") {
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
    private fun <T> guarded(op: String, block: () -> T): T {
        prefs.edit().putString(KEY_PENDING, op).commit()
        try {
            return block()
        } finally {
            prefs.edit().remove(KEY_PENDING).commit()
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
                        "abis" to Build.SUPPORTED_ABIS.toList(),
                    )
                )
                // The app's notification settings (Android 8+), else its
                // app info page; false when neither opens.
                "openNotificationSettings" -> {
                    val intents = buildList {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            add(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName))
                        }
                        add(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null)))
                    }
                    var opened = false
                    for (intent in intents) {
                        try {
                            startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                            opened = true
                            break
                        } catch (e: ActivityNotFoundException) {
                            Log.w(TAG, "no ${intent.action}")
                        }
                    }
                    result.success(opened)
                }
                // Android's text-to-speech settings (install a voice), else
                // the general settings; false when neither opens.
                "openTtsSettings" -> {
                    var opened = false
                    for (action in listOf("com.android.settings.TTS_SETTINGS", Settings.ACTION_SETTINGS)) {
                        try {
                            startActivity(Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                            opened = true
                            break
                        } catch (e: ActivityNotFoundException) {
                            Log.w(TAG, "no $action")
                        }
                    }
                    result.success(opened)
                }
                else -> result.notImplemented()
            }
        }

        val epd = MethodChannel(messenger, "tosk/onyx")
        val pen = MethodChannel(messenger, "tosk/onyx_pen")
        penChannel = pen
        epd.setMethodCallHandler { call, result ->
            when (call.method) {
                "fullRefresh" -> result.success(onyxBridge()?.let { b -> guarded("fullRefresh") { b.fullRefresh() } } ?: false)
                else -> result.notImplemented()
            }
        }
        pen.setMethodCallHandler { call, result ->
            val bridge = if (call.method == "close") onyx else onyxBridge()
            if (bridge == null) {
                // Not an ONYX device (or the SDK failed): Dart uses its canvas.
                result.success(false)
            } else {
                guarded("pen.${call.method}") { bridge.handle(call, result) }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        volumeControlStream = AudioManager.STREAM_MUSIC
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
        const val PREFS = "tosk_native"
        const val KEY_PENDING = "onyx_call_pending"
        const val KEY_DISABLED = "onyx_disabled"

        fun isOnyxDevice(): Boolean {
            val m = (Build.MANUFACTURER ?: "").lowercase()
            val b = (Build.BRAND ?: "").lowercase()
            return m.contains("onyx") || b.contains("onyx")
        }
    }
}
