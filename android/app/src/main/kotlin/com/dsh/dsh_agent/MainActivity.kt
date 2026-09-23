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

        /** Termux 连接通道 */
        const val TERMUX_CHANNEL = "dsh/termux"

        /** 内嵌 Python 通道 */
        const val PYTHON_CHANNEL = "dsh/python"
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

        // ---------------------------------------------------------- Termux
        val tx = TermuxBridge(applicationContext)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TERMUX_CHANNEL)
            .setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                when (call.method) {
                    "status" -> result.success(
                        mapOf(
                            "installed" to tx.isInstalled(),
                            "permitted" to tx.hasPermission(),
                        )
                    )

                    "run" -> {
                        val command = call.argument<String>("command") ?: ""
                        val workdir = call.argument<String>("workdir")
                        val background = call.argument<Boolean>("background") ?: false
                        val timeoutMs = (call.argument<Number>("timeoutMs")?.toLong()
                            ?: 60_000L).coerceIn(5_000L, 300_000L)

                        if (command.isBlank()) {
                            result.success(
                                mapOf(
                                    "ok" to false,
                                    "error" to "命令为空",
                                    "errorKind" to "EMPTY",
                                )
                            )
                            return@setMethodCallHandler
                        }

                        // run() 会阻塞等 Termux 广播回来，**不能占主线程**，
                        // 否则整个界面会卡住直到命令结束。
                        Thread {
                            val r = try {
                                tx.run(command, workdir, background, timeoutMs)
                            } catch (e: Exception) {
                                mapOf<String, Any?>(
                                    "ok" to false,
                                    "error" to "执行异常：${e.message}",
                                    "errorKind" to "EXCEPTION",
                                )
                            }
                            main.post { result.success(r) }
                        }.start()
                    }

                    else -> result.notImplemented()
                }
            }

        // ---------------------------------------------------------- Python
        //
        // 用 Chaquopy 的 Python.getInstance()。**首次调用会启动解释器**，
        // 可能要一两秒，所以放到后台线程，并且要等它完成。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PYTHON_CHANNEL)
            .setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                val code = call.argument<String>("code") ?: ""
                val reset = call.argument<Boolean>("reset") ?: false

                Thread {
                    val out: Any = try {
                        // **必须先 start 再 getInstance**。
                        // 直接 getInstance() 会抛 IllegalStateException:
                        // "Python is not started" —— 解释器不会自己启动。
                        // isStarted() 判一下是因为 start() 只能调一次，
                        // 重复调会报错。
                        if (!com.chaquo.python.Python.isStarted()) {
                            com.chaquo.python.Python.start(
                                com.chaquo.python.android.AndroidPlatform(applicationContext)
                            )
                        }

                        val py = com.chaquo.python.Python.getInstance()
                        when (call.method) {
                            "run" -> py.getModule("dsh_runner")
                                .callAttr("run", code, reset)
                                .toString()

                            "info" -> py.getModule("dsh_runner")
                                .callAttr("info")
                                .toString()

                            "packages" -> py.getModule("dsh_runner")
                                .callAttr("packages")
                                .toString()

                            else -> """{"ok":false,"error":"未知方法"}"""
                        }
                    } catch (e: Throwable) {
                        // 解释器起不来时异常类型很杂（UnsatisfiedLinkError 等），
                        // 统一兜住并回传，否则 Dart 侧只会看到一个没有上下文的报错。
                        """{"ok":false,"error":${jsonString("无法启动 Python：${e.message}")},"error_type":${jsonString(e.javaClass.simpleName)}}"""
                    }
                    main.post { result.success(out) }
                }.start()
            }
    }

    /** 极简的 JSON 字符串转义 —— 只用于把异常信息塞进结果里 */
    private fun jsonString(s: String): String {
        val sb = StringBuilder("\"")
        for (c in s) {
            when (c) {
                '"' -> sb.append("\\\"")
                '\\' -> sb.append("\\\\")
                '\n' -> sb.append("\\n")
                '\r' -> sb.append("\\r")
                '\t' -> sb.append("\\t")
                else -> if (c < ' ') sb.append(" ") else sb.append(c)
            }
        }
        return sb.append("\"").toString()
    }

    override fun onDestroy() {
        overlay?.dismiss()
        overlay = null
        bridge?.dispose()
        bridge = null
        super.onDestroy()
    }
}
