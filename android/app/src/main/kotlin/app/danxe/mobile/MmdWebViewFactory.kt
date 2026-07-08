package app.danxe.mobile

import android.content.Context
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.File

class MmdWebViewFactory(
    private val events: MethodChannel,
    private val libraryRoot: File,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val view = MmdWebView(context, events, libraryRoot)
        MmdViewRegistry.current = view
        return view
    }
}

