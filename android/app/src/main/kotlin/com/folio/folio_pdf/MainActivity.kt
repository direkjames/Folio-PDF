package com.folio.folio_pdf

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Handles "Open with Folio PDF" (ACTION_VIEW) and "Share → Folio PDF" (ACTION_SEND).
 *
 * Other apps hand us a content:// link, not a real file path. We copy the PDF into
 * Folio's own storage and give the Flutter side that file path, so it can be opened,
 * edited, saved, and kept in the Recent list like any other file.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "folio/open_file"
    private var channel: MethodChannel? = null

    // The PDF the app was launched with, waiting for Flutter to ask for it.
    private var pendingUri: Uri? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingUri = pdfUriFrom(intent)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialFile" -> {
                        val uri = pendingUri
                        pendingUri = null
                        if (uri == null) {
                            result.success(null)
                        } else {
                            copyInBackground(uri) { path -> result.success(path) }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    // A PDF was opened while Folio was already running.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val uri = pdfUriFrom(intent) ?: return
        copyInBackground(uri) { path ->
            if (path != null) channel?.invokeMethod("fileOpened", path)
        }
    }

    private fun pdfUriFrom(intent: Intent?): Uri? {
        if (intent == null) return null
        return when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND ->
                if (Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                }
            else -> null
        }
    }

    /** Copies off the main thread (big PDFs would freeze the UI), then reports back on it. */
    private fun copyInBackground(uri: Uri, done: (String?) -> Unit) {
        Thread {
            val path = try {
                copyToAppStorage(uri)
            } catch (e: Exception) {
                null
            }
            runOnUiThread { done(path) }
        }.start()
    }

    private fun copyToAppStorage(uri: Uri): String? {
        var name = "document.pdf"
        var size = -1L
        contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val nameIdx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                val sizeIdx = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (nameIdx >= 0) cursor.getString(nameIdx)?.let { name = it }
                if (sizeIdx >= 0 && !cursor.isNull(sizeIdx)) size = cursor.getLong(sizeIdx)
            }
        }
        if (uri.scheme == "file") {
            uri.lastPathSegment?.let { name = it }
        }
        name = name.replace(Regex("[\\\\/:*?\"<>|]"), "_")
        if (!name.lowercase().endsWith(".pdf")) name += ".pdf"

        val dir = File(filesDir, "opened").apply { mkdirs() }
        var target = File(dir, name)

        // Opening the same file again reuses the earlier copy (keeps one Recent entry).
        if (target.exists() && size >= 0 && target.length() == size) {
            return target.absolutePath
        }
        // A different file with the same name: don't overwrite it, pick "name (2).pdf".
        var n = 2
        val base = name.removeSuffix(".pdf").removeSuffix(".PDF")
        while (target.exists()) {
            target = File(dir, "$base ($n).pdf")
            n++
        }

        val input = contentResolver.openInputStream(uri) ?: return null
        input.use { inp -> target.outputStream().use { out -> inp.copyTo(out) } }
        return target.absolutePath
    }
}
