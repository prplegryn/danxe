package app.danxe.mobile

import android.annotation.SuppressLint
import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Base64
import android.view.View
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import java.io.File
import java.util.Locale
import org.json.JSONObject

class MmdWebView(
    context: Context,
    private val events: MethodChannel,
    private val libraryRoot: File,
) : PlatformView {
    private val appContext = context.applicationContext
    private val main = Handler(Looper.getMainLooper())
    private val webView = WebView(context)
    private val pendingScripts = mutableListOf<String>()
    private var pageReady = false
    private val virtualHost = "danxe.local"

    init {
        ensureDownloadExportRoot()
        configureWebView()
        webView.loadUrl("https://$virtualHost/danxe_viewer.html")
    }

    override fun getView(): View = webView

    override fun dispose() {
        if (MmdViewRegistry.current === this) {
            MmdViewRegistry.current = null
        }
        webView.stopLoading()
        webView.destroy()
    }

    fun loadScene(scene: JSONObject) {
        command("loadScene", scene)
    }

    fun command(name: String, payload: JSONObject = JSONObject()) {
        evaluate("window.Danxe && window.Danxe.$name($payload);")
    }

    private fun evaluate(script: String) {
        main.post {
            if (!pageReady) {
                pendingScripts.add(script)
            } else {
                webView.evaluateJavascript(script, null)
            }
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun configureWebView() {
        WebView.setWebContentsDebuggingEnabled(false)
        webView.setBackgroundColor(android.graphics.Color.BLACK)
        webView.webChromeClient = WebChromeClient()
        webView.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView?, url: String?) {
                pageReady = true
                val scripts = pendingScripts.toList()
                pendingScripts.clear()
                scripts.forEach { webView.evaluateJavascript(it, null) }
            }

            override fun shouldInterceptRequest(
                view: WebView?,
                request: WebResourceRequest?,
            ): WebResourceResponse? {
                val url = request?.url ?: return null
                if (url.scheme != "https" || url.host != virtualHost) return null
                return openVirtualFile(url)
            }
        }
        webView.addJavascriptInterface(AndroidBridge(), "DanxeAndroid")
        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            databaseEnabled = true
            allowFileAccess = true
            allowContentAccess = true
            allowFileAccessFromFileURLs = true
            allowUniversalAccessFromFileURLs = true
            mediaPlaybackRequiresUserGesture = false
            mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
        }
    }

    private fun openVirtualFile(uri: Uri): WebResourceResponse {
        try {
            val segments = uri.pathSegments
                .dropWhile { it.isEmpty() }
                .flatMap { segment ->
                    segment.split('\\', '/').filter { it.isNotEmpty() }
                }
            if (segments.any { it == ".." }) {
                return textResponse(403, "Forbidden", "Blocked unsafe Danxe resource.")
            }
            if (segments.firstOrNull() == "library") {
                return openVirtualLibraryFile(segments)
            }
            return openVirtualAssetFile(segments)
        } catch (error: Exception) {
            return textResponse(500, "Internal Server Error", error.message ?: "Failed to read Danxe resource.")
        }
    }

    private fun openVirtualAssetFile(segments: List<String>): WebResourceResponse {
        if (segments.isEmpty()) {
            return textResponse(404, "Not Found", "Unknown Danxe resource.")
        }
        val assetPath = segments.joinToString("/")
        if (assetPath != "danxe_viewer.html" && !assetPath.startsWith("vendor/")) {
            return textResponse(404, "Not Found", "Unknown Danxe resource.")
        }
        return WebResourceResponse(
            mimeTypeForAsset(assetPath),
            null,
            200,
            "OK",
            corsHeaders(),
            appContext.assets.open(assetPath),
        )
    }

    private fun openVirtualLibraryFile(segments: List<String>): WebResourceResponse {
        if (segments.size < 4) {
            return textResponse(404, "Not Found", "Unknown Danxe resource.")
        }

        val assetDir = File(File(libraryRoot, segments[1]), segments[2])
        val requestedPath = segments.drop(3).joinToString("/")
        val resolvedPath = resolveAssetPathAlias(assetDir, requestedPath)
        var target = assetDir
        for (segment in resolvedPath.split('/').filter { it.isNotEmpty() }) {
            target = File(target, segment)
        }

        val rootPath = assetDir.canonicalPath
        val targetFile = target.canonicalFile
        if (!targetFile.path.startsWith(rootPath + File.separator)) {
            return textResponse(403, "Forbidden", "Blocked unsafe Danxe resource.")
        }
        if (!targetFile.isFile) {
            return textResponse(404, "Not Found", "Danxe resource not found.")
        }

        return WebResourceResponse(
            mimeTypeForFile(targetFile),
            null,
            200,
            "OK",
            corsHeaders(),
            targetFile.inputStream(),
        )
    }

    private fun resolveAssetPathAlias(assetDir: File, relativePath: String): String {
        if (relativePath.isBlank()) return relativePath
        val manifest = File(assetDir, "asset.json")
        if (!manifest.isFile) return relativePath
        return try {
            val aliases = JSONObject(manifest.readText()).optJSONObject("pathAliases")
                ?: return relativePath
            val normalized = relativePath
                .replace('\\', '/')
                .split('/')
                .filter { it.isNotBlank() && it != "." }
                .joinToString("/")
            val basename = normalized.substringAfterLast('/')
            val candidates = listOf(
                normalized,
                basename,
                normalized.lowercase(Locale.US),
                basename.lowercase(Locale.US),
            )
            for (candidate in candidates) {
                val resolved = aliases.optString(candidate, "")
                if (resolved.isNotBlank()) return resolved
            }
            val keys = aliases.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                if (key.substringAfterLast('/').equals(basename, ignoreCase = true)) {
                    val resolved = aliases.optString(key, "")
                    if (resolved.isNotBlank()) return resolved
                }
            }
            relativePath
        } catch (_: Exception) {
            relativePath
        }
    }

    private fun textResponse(status: Int, reason: String, body: String): WebResourceResponse {
        return WebResourceResponse(
            "text/plain",
            "UTF-8",
            status,
            reason,
            corsHeaders(),
            body.byteInputStream(),
        )
    }

    private fun corsHeaders(): Map<String, String> {
        return mapOf(
            "Access-Control-Allow-Origin" to "*",
            "Access-Control-Allow-Methods" to "GET, OPTIONS",
            "Access-Control-Allow-Headers" to "*",
            "Cross-Origin-Resource-Policy" to "cross-origin",
        )
    }

    private fun mimeTypeForFile(file: File): String {
        return when (file.extension.lowercase(Locale.US)) {
            "pmx", "pmd", "vmd", "vpd", "vpdpose", "dds", "spa", "sph" -> "application/octet-stream"
            "png" -> "image/png"
            "jpg", "jpeg" -> "image/jpeg"
            "bmp" -> "image/bmp"
            "tga" -> "image/x-tga"
            "wav" -> "audio/wav"
            "mp3" -> "audio/mpeg"
            "m4a", "aac" -> "audio/mp4"
            "flac" -> "audio/flac"
            "ogg" -> "audio/ogg"
            else -> "application/octet-stream"
        }
    }

    private fun mimeTypeForAsset(path: String): String {
        return when (path.substringAfterLast('.', "").lowercase(Locale.US)) {
            "html" -> "text/html"
            "js" -> "application/javascript"
            "wasm" -> "application/wasm"
            "json" -> "application/json"
            else -> "application/octet-stream"
        }
    }

    private fun ensureDownloadExportRoot(): File {
        val root = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
            "danxe",
        )
        try {
            root.mkdirs()
        } catch (_: Exception) {
        }
        return root
    }

    private fun saveExport(bytes: ByteArray, safeName: String, mimeType: String): String {
        ensureDownloadExportRoot()
        val storageMimeType = normalizeVideoMimeType(mimeType)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveExportWithMediaStore(bytes, safeName, storageMimeType)
        } else {
            saveExportLegacy(bytes, safeName)
        }
    }

    private fun saveExportWithMediaStore(bytes: ByteArray, safeName: String, mimeType: String): String {
        val resolver = appContext.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, safeName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType.ifBlank { "video/webm" })
            put(MediaStore.MediaColumns.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/danxe")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("Unable to create export file in Download/danxe.")
        resolver.openOutputStream(uri).use { output ->
            requireNotNull(output) { "Unable to open export file in Download/danxe." }
            output.write(bytes)
        }
        values.clear()
        values.put(MediaStore.MediaColumns.IS_PENDING, 0)
        resolver.update(uri, values, null, null)
        return "Download/danxe/$safeName"
    }

    private fun saveExportLegacy(bytes: ByteArray, safeName: String): String {
        val output = uniqueFile(ensureDownloadExportRoot(), safeName)
        output.writeBytes(bytes)
        return output.absolutePath
    }

    private fun uniqueFile(directory: File, fileName: String): File {
        var candidate = File(directory, fileName)
        if (!candidate.exists()) return candidate
        val dot = fileName.lastIndexOf('.')
        val base = if (dot > 0) fileName.substring(0, dot) else fileName
        val extension = if (dot > 0) fileName.substring(dot) else ""
        var index = 1
        while (candidate.exists()) {
            candidate = File(directory, "${base}_$index$extension")
            index += 1
        }
        return candidate
    }

    private fun exportExtension(mimeType: String): String {
        return when (normalizeVideoMimeType(mimeType)) {
            "video/mp4" -> "mp4"
            "video/webm" -> "webm"
            else -> "mp4"
        }
    }

    private fun normalizeVideoMimeType(mimeType: String): String {
        return when {
            mimeType.contains("mp4", ignoreCase = true) -> "video/mp4"
            mimeType.contains("webm", ignoreCase = true) -> "video/webm"
            else -> "video/mp4"
        }
    }

    private fun normalizeExportName(fileName: String, mimeType: String): String {
        val extension = exportExtension(mimeType)
        val safe = fileName.replace(Regex("[^A-Za-z0-9._-]"), "_").ifBlank {
            "danxe_export.$extension"
        }
        val dot = safe.lastIndexOf('.')
        val base = if (dot > 0) safe.substring(0, dot) else safe
        return "$base.$extension"
    }

    inner class AndroidBridge {
        @JavascriptInterface
        fun postStatus(payload: String) {
            main.post {
                events.invokeMethod("viewerStatus", payload)
            }
        }

        @JavascriptInterface
        fun saveRecording(base64Video: String, mimeType: String, fileName: String) {
            try {
                val storageMimeType = normalizeVideoMimeType(mimeType)
                val safeName = normalizeExportName(fileName, storageMimeType)
                val bytes = Base64.decode(base64Video, Base64.DEFAULT)
                val outputPath = saveExport(bytes, safeName, storageMimeType)
                main.post {
                    val payload = JSONObject()
                        .put("type", "exportComplete")
                        .put("path", outputPath)
                        .put("mimeType", storageMimeType)
                    events.invokeMethod("viewerStatus", payload.toString())
                    MmdViewRegistry.pendingExportResult?.success(outputPath)
                    MmdViewRegistry.pendingExportResult = null
                }
            } catch (error: Exception) {
                onExportError(error.message ?: "Failed to save recording.")
            }
        }

        @JavascriptInterface
        fun onExportError(message: String) {
            main.post {
                val payload = JSONObject()
                    .put("type", "exportError")
                    .put("message", message)
                events.invokeMethod("viewerStatus", payload.toString())
                MmdViewRegistry.pendingExportResult?.error("EXPORT_FAILED", message, null)
                MmdViewRegistry.pendingExportResult = null
            }
        }
    }
}
