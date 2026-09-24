package com.dsh.dsh_agent

import android.content.Intent
import android.os.Build
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

        /** 后台保活通道（前台服务 + 电池优化） */
        const val BG_CHANNEL = "dsh/bg"
    }

    private var bridge: ShizukuBridge? = null
    private var overlay: OverlayConfirm? = null
    private var activity: ActivityOverlay? = null

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

        // 底部的"正在干什么"浮窗。和确认框是两个独立窗口，
        // 但都用 TYPE_APPLICATION_OVERLAY —— 同时显示会互相盖住，
        // 所以弹确认框前先把它收起来（见下面的 showConfirm）。
        val act = ActivityOverlay(applicationContext)
        activity = act

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, OVERLAY_CHANNEL)
            .setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                when (call.method) {
                    "canDraw" -> result.success(ov.canDraw())

                    "requestPermission" -> {
                        ov.requestPermission()
                        result.success(true)
                    }

                    // ---- 进度浮窗 ----
                    // 显示时机由 Dart 侧决定（应用切到后台时才显示），
                    // 原生这边只管画。
                    "showActivity" -> {
                        act.show(call.argument<String>("text") ?: "正在工作…")
                        result.success(true)
                    }

                    "updateActivity" -> {
                        act.show(call.argument<String>("text") ?: "正在工作…")
                        result.success(true)
                    }

                    "hideActivity" -> {
                        act.hide()
                        result.success(true)
                    }

                    "dismissActivity" -> {
                        act.dismiss()
                        result.success(true)
                    }

                    // 把应用拉回前台。
                    //
                    // 后台启动 Activity 在 Android 10+ 是被限制的，但我们
                    // **两个条件都满足**：有正在运行的前台服务，且持有
                    // SYSTEM_ALERT_WINDOW 权限。所以这里能成功。
                    //
                    // REORDER_TO_FRONT 而不是 CLEAR_TOP：前者保留已有的
                    // Activity 状态，用户回来时还停在原来的滚动位置和输入内容上。
                    "bringToFront" -> {
                        try {
                            val i = Intent(this, MainActivity::class.java).apply {
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                            }
                            startActivity(i)
                            result.success(true)
                        } catch (e: Exception) {
                            // 被系统拦下就算了 —— 还有通知可以点，
                            // 不能因为拉不起来就报错给用户
                            result.success(false)
                        }
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

                        // 确认框和进度浮窗都用 TYPE_APPLICATION_OVERLAY，
                        // 同时显示会互相遮住。确认框是**要用户立刻操作**的，
                        // 优先级更高，所以先把浮窗收起来；用户答完再放回来
                        // （act.hide 只收起、记住状态，不是销毁）。
                        act.hide()

                        ov.show(title, command, reasons, dangerous) { approved ->
                            main.post {
                                if (!replied) {
                                    replied = true
                                    // 答完把浮窗放回来 —— 底层任务还在跑，
                                    // 用户仍然需要看到"在干什么"
                                    act.hide()
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

        // ---------------------------------------------------------- 后台保活
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BG_CHANNEL)
            .setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                when (call.method) {
                    // 有没有"忽略电池优化"。false 时 Doze 会掐掉长任务
                    "batteryIgnored" -> result.success(isIgnoringBattery())

                    // 弹系统对话框申请。这是特殊权限，只能跳系统 UI 让用户点
                    "requestBattery" -> {
                        var ok = false
                        try {
                            val i = Intent(
                                android.provider.Settings
                                    .ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
                            )
                            i.data = android.net.Uri.parse("package:$packageName")
                            startActivity(i)
                            ok = true
                        } catch (e: Exception) {
                            // 个别 ROM 没有这个 Activity，退回"电池优化列表"页
                            try {
                                startActivity(
                                    Intent(
                                        android.provider.Settings
                                            .ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS
                                    )
                                )
                                ok = true
                            } catch (e2: Exception) {
                                ok = false
                            }
                        }
                        result.success(ok)
                    }

                    // 通知权限（Android 13+）。被拒时前台服务**仍会运行**，
                    // 只是通知不显示 —— 所以这是锦上添花，不是必需。
                    "notifEnabled" -> {
                        val ok = if (Build.VERSION.SDK_INT >= 33) {
                            checkSelfPermission("android.permission.POST_NOTIFICATIONS") ==
                                    android.content.pm.PackageManager.PERMISSION_GRANTED
                        } else true
                        result.success(ok)
                    }

                    "startService" -> {
                        val text = call.argument<String>("text") ?: "正在执行任务…"
                        AgentService.start(applicationContext, text)
                        result.success(true)
                    }

                    "updateService" -> {
                        val text = call.argument<String>("text") ?: ""
                        if (text.isNotEmpty()) {
                            AgentService.update(applicationContext, text)
                        }
                        result.success(true)
                    }

                    "stopService" -> {
                        AgentService.stop(applicationContext)
                        result.success(true)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    /** 有没有被加入"电池优化白名单" */
    private fun isIgnoringBattery(): Boolean {
        return try {
            val pm = getSystemService(POWER_SERVICE) as android.os.PowerManager
            pm.isIgnoringBatteryOptimizations(packageName)
        } catch (e: Exception) {
            // 个别 ROM 上这个 API 会抛，保守地当作"没加白名单"
            false
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
        activity?.dismiss()
        activity = null
        bridge?.dispose()
        bridge = null
        super.onDestroy()
    }
}
