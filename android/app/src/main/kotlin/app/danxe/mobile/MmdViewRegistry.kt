package app.danxe.mobile

import io.flutter.plugin.common.MethodChannel

object MmdViewRegistry {
    var current: MmdWebView? = null
    var pendingExportResult: MethodChannel.Result? = null
}

