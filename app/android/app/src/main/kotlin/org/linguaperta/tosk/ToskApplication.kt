package org.linguaperta.tosk

import android.app.Application
import android.content.Context
import android.os.Build
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Crash reporting without a cable or a server: an uncaught JVM exception is
 * written to `files/last_crash_native.txt` (the app support directory, which
 * Dart reads on the next start and shows to the user with a Copy button; see
 * `lib/device/crash_report.dart`).
 *
 * Native crashes (SIGSEGV) can't be caught; the Onyx SDK calls are guarded by
 * a marker instead ([MainActivity.guarded]): when a start finds the marker
 * still set, the previous Onyx call killed the app, so the Onyx features are
 * disabled for good and that is reported the same way.
 */
class ToskApplication : Application() {
    override fun attachBaseContext(base: Context) {
        super.attachBaseContext(base)
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            try {
                val sw = StringWriter()
                error.printStackTrace(PrintWriter(sw))
                write(base, "Uncaught exception on thread '${thread.name}':\n$sw")
            } catch (_: Throwable) {
            }
            previous?.uncaughtException(thread, error)
        }
    }

    override fun onCreate() {
        super.onCreate()
        val prefs = getSharedPreferences(MainActivity.PREFS, Context.MODE_PRIVATE)
        val pending = prefs.getString(MainActivity.KEY_PENDING, null)
        if (pending != null) {
            prefs.edit().putBoolean(MainActivity.KEY_DISABLED, true).remove(MainActivity.KEY_PENDING).commit()
            write(
                this,
                "The app stopped inside the Onyx (Boox) SDK during '$pending' (a native crash).\n" +
                    "The Onyx pen and e-ink refresh are now switched off; the normal writing pad is used instead.",
            )
        }
    }

    companion object {
        const val CRASH_FILE = "last_crash_native.txt"

        fun write(context: Context, body: String) {
            val stamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss Z", Locale.US).format(Date())
            val header = "tosk ${versionName(context)} · ${Build.MANUFACTURER} ${Build.MODEL} · Android ${Build.VERSION.RELEASE} (SDK ${Build.VERSION.SDK_INT}) · $stamp"
            File(context.filesDir, CRASH_FILE).writeText("$header\n\n$body\n")
        }

        private fun versionName(context: Context): String = try {
            context.packageManager.getPackageInfo(context.packageName, 0).versionName ?: "?"
        } catch (_: Throwable) {
            "?"
        }
    }
}
