package app.danxe.mobile

import android.annotation.SuppressLint
import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
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
    private val main = Handler(Looper.getMainLooper())
    private val webView = WebView(context)
    private val pendingScripts = mutableListOf<String>()
    private var pageReady = false
    private val virtualHost = "danxe.local"

    init {
        configureWebView()
        webView.loadUrl("file:///android_asset/danxe_viewer.html")
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
                return openVirtualLibraryFile(url)
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

    private fun openVirtualLibraryFile(uri: Uri): WebResourceResponse {
        try {
            val segments = uri.pathSegments
                .dropWhile { it.isEmpty() }
                .flatMap { segment ->
                    segment.split('\\', '/').filter { it.isNotEmpty() }
                }
            if (segments.any { it == ".." }) {
                return textResponse(403, "Forbidden", "Blocked unsafe Danxe resource.")
            }
            if (segments.firstOrNull() != "library" || segments.size < 4) {
                return textResponse(404, "Not Found", "Unknown Danxe resource.")
            }

            var target = libraryRoot
            for (segment in segments.drop(1)) {
                target = File(target, segment)
            }

            val rootPath = libraryRoot.canonicalPath
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
        } catch (error: Exception) {
            return textResponse(500, "Internal Server Error", error.message ?: "Failed to read Danxe resource.")
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
                val extension = when {
                    mimeType.contains("webm", ignoreCase = true) -> "webm"
                    mimeType.contains("mp4", ignoreCase = true) -> "mp4"
                    else -> "webm"
                }
                val safeName = fileName.replace(Regex("[^A-Za-z0-9._-]"), "_").ifBlank {
                    "danxe_export.$extension"
                }
                val exports = File(libraryRoot, "exports")
                exports.mkdirs()
                val output = File(exports, safeName)
                val bytes = Base64.decode(base64Video, Base64.DEFAULT)
                output.writeBytes(bytes)
                main.post {
                    val payload = JSONObject()
                        .put("type", "exportComplete")
                        .put("path", output.absolutePath)
                        .put("mimeType", mimeType)
                    events.invokeMethod("viewerStatus", payload.toString())
                    MmdViewRegistry.pendingExportResult?.success(output.absolutePath)
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
