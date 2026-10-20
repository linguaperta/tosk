package org.linguaperta.tosk

import android.app.Activity
import android.graphics.Rect
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.View
import com.onyx.android.sdk.api.device.epd.EpdController
import com.onyx.android.sdk.api.device.epd.UpdateMode
import com.onyx.android.sdk.data.note.TouchPoint
import com.onyx.android.sdk.pen.RawInputCallback
import com.onyx.android.sdk.pen.TouchHelper
import com.onyx.android.sdk.pen.data.TouchPointList
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.lsposed.hiddenapibypass.HiddenApiBypass

/**
 * The Onyx (Boox) SDK behind the `tosk/onyx` and `tosk/onyx_pen`
 * channels. Only created on ONYX devices (see [MainActivity]).
 *
 * Pen protocol (Dart -> native), rectangles in physical pixels of the
 * Flutter view:
 * - `open {left, top, right, bottom, strokeWidth}` -> true when raw drawing
 *   runs (false: the SDK failed, Dart keeps its own canvas);
 * - `setRect {left, top, right, bottom}` when the pad moved;
 * - `setEnabled {enabled}` to pause it (a dialog over the pad, the answer
 *   checked) and resume it;
 * - `clear` drops the strokes drawn on the e-ink overlay;
 * - `close`.
 *
 * Native -> Dart: `stroke` with a DoubleArray `[x, y, t, x, y, t, ...]` per
 * finished stylus stroke (x/y in physical pixels of the view, t in ms), and
 * `erase` with the eraser's points (the pen's eraser end / side button).
 */
class OnyxBridge(private val activity: Activity, private val channel: MethodChannel) {
    private val main = Handler(Looper.getMainLooper())
    private var helper: TouchHelper? = null
    private var rect: Rect? = null
    private var enabled = false
    private var pausedByLifecycle = false

    init {
        // The SDK reaches into Onyx framework classes that Android 9+ treats as
        // hidden API; Onyx's own sample apps lift the restriction like this.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            try {
                HiddenApiBypass.addHiddenApiExemptions("")
            } catch (t: Throwable) {
                Log.w(TAG, "hidden API exemption failed", t)
            }
        }
    }

    private fun hostView(): View =
        activity.findViewById(FLUTTER_VIEW_ID) ?: activity.window.decorView

    /** A full GC refresh of the whole screen (clears e-ink ghosting). */
    fun fullRefresh(): Boolean {
        val view = hostView()
        return try {
            EpdController.refreshScreen(view, UpdateMode.GC)
            true
        } catch (t: Throwable) {
            try {
                EpdController.repaintEveryThing(UpdateMode.GC)
                true
            } catch (t2: Throwable) {
                Log.w(TAG, "EPD full refresh failed", t2)
                view.invalidate()
                false
            }
        }
    }

    private val callback = object : RawInputCallback() {
        override fun onBeginRawDrawing(shortcut: Boolean, point: TouchPoint?) {}
        override fun onEndRawDrawing(shortcut: Boolean, point: TouchPoint?) {}
        override fun onRawDrawingTouchPointMoveReceived(point: TouchPoint?) {}
        override fun onRawDrawingTouchPointListReceived(list: TouchPointList?) {
            send("stroke", list)
        }

        override fun onBeginRawErasing(shortcut: Boolean, point: TouchPoint?) {}
        override fun onEndRawErasing(shortcut: Boolean, point: TouchPoint?) {}
        override fun onRawErasingTouchPointMoveReceived(point: TouchPoint?) {}
        override fun onRawErasingTouchPointListReceived(list: TouchPointList?) {
            send("erase", list)
        }
    }

    private fun send(method: String, list: TouchPointList?) {
        val points = list?.points ?: return
        if (points.isEmpty()) return
        val out = DoubleArray(points.size * 3)
        var i = 0
        for (p in points) {
            out[i++] = p.x.toDouble()
            out[i++] = p.y.toDouble()
            out[i++] = p.timestamp.toDouble()
        }
        main.post { channel.invokeMethod(method, out) }
    }

    private fun rectOf(call: MethodCall): Rect? {
        val l = call.argument<Number>("left")?.toInt() ?: return null
        val t = call.argument<Number>("top")?.toInt() ?: return null
        val r = call.argument<Number>("right")?.toInt() ?: return null
        val b = call.argument<Number>("bottom")?.toInt() ?: return null
        if (r <= l || b <= t) return null
        return Rect(l, t, r, b)
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "open" -> result.success(open(rectOf(call), call.argument<Number>("strokeWidth")?.toFloat() ?: 3f))
                "setRect" -> {
                    val r = rectOf(call)
                    if (r != null && r != rect) {
                        rect = r
                        helper?.setLimitRect(r, emptyList())
                    }
                    result.success(helper != null)
                }
                "setEnabled" -> {
                    enabled = call.argument<Boolean>("enabled") ?: false
                    helper?.setRawDrawingEnabled(enabled && !pausedByLifecycle)
                    result.success(helper != null)
                }
                "clear" -> {
                    // Toggling raw drawing drops the overlay; the Flutter frame
                    // underneath (an empty pad) is shown again.
                    helper?.let {
                        it.setRawDrawingEnabled(false)
                        hostView().invalidate()
                        if (enabled && !pausedByLifecycle) it.setRawDrawingEnabled(true)
                    }
                    result.success(helper != null)
                }
                "close" -> {
                    close()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        } catch (t: Throwable) {
            Log.w(TAG, "Onyx pen: ${call.method} failed", t)
            close()
            result.success(false)
        }
    }

    private fun open(r: Rect?, strokeWidth: Float): Boolean {
        if (r == null) return false
        return try {
            val h = helper ?: TouchHelper.create(hostView(), callback).also { helper = it }
            rect = r
            h.setStrokeWidth(strokeWidth)
            h.setStrokeStyle(TouchHelper.STROKE_STYLE_PENCIL)
            h.setLimitRect(r, emptyList())
            if (!h.isRawDrawingCreated) h.openRawDrawing()
            enabled = true
            h.setRawDrawingEnabled(!pausedByLifecycle)
            true
        } catch (t: Throwable) {
            Log.w(TAG, "Onyx pen: raw drawing unavailable", t)
            close()
            false
        }
    }

    private fun close() {
        val h = helper ?: return
        helper = null
        enabled = false
        try {
            h.setRawDrawingEnabled(false)
            h.closeRawDrawing()
        } catch (t: Throwable) {
            Log.w(TAG, "Onyx pen: close failed", t)
        }
    }

    fun pause() {
        pausedByLifecycle = true
        try {
            helper?.setRawDrawingEnabled(false)
        } catch (_: Throwable) {
        }
    }

    fun resume() {
        pausedByLifecycle = false
        try {
            if (enabled) helper?.setRawDrawingEnabled(true)
        } catch (_: Throwable) {
        }
    }

    fun dispose() = close()

    companion object {
        private const val TAG = "tosk-onyx"
        private val FLUTTER_VIEW_ID = io.flutter.embedding.android.FlutterActivity.FLUTTER_VIEW_ID
    }
}
