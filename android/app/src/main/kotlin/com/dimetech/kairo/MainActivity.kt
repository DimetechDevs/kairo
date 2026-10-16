package com.dimetech.kairo

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Picks videos and subtitles with the system document picker and keeps read access to them,
 * so imported files stay where they are on the phone (nothing is copied).
 */
class MainActivity : FlutterActivity() {
    private val channelName = "kairo/documents"
    private val pickRequest = 4710
    private var pending: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler(::handle)
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pick" -> {
                if (pending != null) {
                    result.error("busy", "A picker is already open", null)
                    return
                }
                pending = result
                val mimeTypes = call.argument<List<String>>("mimeTypes") ?: listOf("video/*")
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = if (mimeTypes.size == 1) mimeTypes[0] else "*/*"
                    putExtra(Intent.EXTRA_MIME_TYPES, mimeTypes.toTypedArray())
                    putExtra(Intent.EXTRA_ALLOW_MULTIPLE, call.argument<Boolean>("multiple") ?: false)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                }
                startActivityForResult(intent, pickRequest)
            }
            "exists" -> {
                val uri = Uri.parse(call.argument<String>("uri"))
                result.success(
                    try {
                        contentResolver.openFileDescriptor(uri, "r")?.use { true } ?: false
                    } catch (e: Exception) {
                        false
                    },
                )
            }
            "release" -> {
                try {
                    contentResolver.releasePersistableUriPermission(
                        Uri.parse(call.argument<String>("uri")),
                        Intent.FLAG_GRANT_READ_URI_PERMISSION,
                    )
                } catch (_: Exception) {
                    // Already released or never held.
                }
                result.success(null)
            }
            "readText" -> {
                // Small files only (subtitles).
                try {
                    val uri = Uri.parse(call.argument<String>("uri"))
                    val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                    result.success(bytes)
                } catch (e: Exception) {
                    result.error("read_failed", e.message, null)
                }
            }
            else -> result.notImplemented()
        }
    }

    @Deprecated("Uses the platform document picker result")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickRequest) return
        val result = pending ?: return
        pending = null
        if (resultCode != Activity.RESULT_OK || data == null) {
            result.success(emptyList<Map<String, Any?>>())
            return
        }
        val uris = mutableListOf<Uri>()
        data.clipData?.let { clip -> for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri) }
        if (uris.isEmpty()) data.data?.let(uris::add)

        result.success(uris.map { uri ->
            try {
                contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            } catch (_: SecurityException) {
                // Some providers don't offer persistable access; the file still works until reboot.
            }
            var name: String? = null
            var size: Long? = null
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)
                ?.use { c ->
                    if (c.moveToFirst()) {
                        name = c.getString(0)
                        if (!c.isNull(1)) size = c.getLong(1)
                    }
                }
            mapOf("uri" to uri.toString(), "name" to (name ?: uri.lastPathSegment ?: "video"), "size" to size)
        })
    }
}
