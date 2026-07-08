package app.danxe.mobile

import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.view.View
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import java.io.File
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

