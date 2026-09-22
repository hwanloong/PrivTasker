package com.dsh.dsh_agent

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        /** 系统级悬浮窗确认框的通道 */
        const val OVERLAY_CHANNEL = "dsh/overlay"
    }

    private var bridge: ShizukuBridge? = null
    private var overlay: OverlayConfirm? = null

    private val main = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val b = ShizukuBridge(applicationContext)
        bridge = b

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ShizukuBridge.METHOD_CHANNEL)
            .setMethodCallHandler(b)

        // 状态变化（binder 上线/掉线、权限授予结果）通过事件通道推给 Dart
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, ShizukuBridge.EVENT_CHANNEL)
            .setStreamHandler(b)

        // 用 applicationContext：悬浮窗属于系统窗口，
        // 拿 Activity 的 context 容易在旋转/重建时泄漏。
        val ov = OverlayConfirm(applicationContext)
        overlay = ov

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, OVERLAY_CHANNEL)
            .setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                when (call.method) {
                    "canDraw" -> result.success(ov.canDraw())

                    "requestPermission" -> {
                        ov.requestPermission()
                        result.success(true)
                    }

                    "showConfirm" -> {
                        val title = call.argument<String>("title") ?: "操作确认"
                        val command = call.argument<String>("command") ?: ""
                        val reasons = call.argument<List<*>>("reasons")
                            ?.map { it.toString() } ?: emptyList()
                        val dangerous = call.argument<Boolean>("dangerous") ?: false

                        // MethodChannel.Result 必须且只能回一次，
                        // 悬浮窗的超时自动拒绝也走这条路径，所以这里加个闸。
                        var replied = false
                        ov.show(title, command, reasons, dangerous) { approved ->
                            main.post {
                                if (!replied) {
                                    replied = true
                                    result.success(approved)
                                }
                            }
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        overlay?.dismiss()
        overlay = null
        bridge?.dispose()
        bridge = null
        super.onDestroy()
    }
}
