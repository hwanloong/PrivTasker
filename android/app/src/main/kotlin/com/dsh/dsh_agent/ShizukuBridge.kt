package com.dsh.dsh_agent

import android.content.Context
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import moe.shizuku.server.IShizukuService
import rikka.shizuku.Shizuku
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/**
 * Flutter 与 Shizuku 之间的桥。
 *
 * 设计上这里**只做一件事**：以 shell 身份执行命令并回传结果。
 * 所有「应用管理 / 文件读写 / 系统设置」等语义都放在 Dart 侧用命令组合出来——
 * 这样加新工具不用改原生代码，改 Dart 就行。
 *
 * 三个踩过的坑：
 *  1. `Shizuku.newProcess(...)` 在 13.1.5 里是 **private**，编译不过。
 *     公开入口在 AIDL 层：`IShizukuService.newProcess(...)`，
 *     服务对象由 `Shizuku.getBinder()` 取到。这里就走这条路。
 *  2. Shizuku 的 binder 调用**不能在主线程**执行，一律丢到 [io] 线程池。
 *  3. 截图返回的是二进制 PNG，所以 exec 支持 binary 模式回传 ByteArray，
 *     不能用 String 中转（会破坏非 UTF-8 字节）。
 */
class ShizukuBridge(private val context: Context) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        const val METHOD_CHANNEL = "dsh/shizuku"
        const val EVENT_CHANNEL = "dsh/shizuku/events"
        private const val PERMISSION_REQUEST_CODE = 4213

        /** 单条命令的默认超时，防止 `logcat` 这类不会自己结束的命令把 UI 挂死 */
        private const val DEFAULT_TIMEOUT_MS = 20_000L
    }

    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newCachedThreadPool()
    private var events: EventChannel.EventSink? = null

    // ---------------------------------------------------------------- 生命周期

    private val binderReceivedListener = Shizuku.OnBinderReceivedListener {
        emit(mapOf("type" to "binderReceived"))
    }

    private val binderDeadListener = Shizuku.OnBinderDeadListener {
        emit(mapOf("type" to "binderDead"))
    }

    private val permissionListener =
        Shizuku.OnRequestPermissionResultListener { requestCode, grantResult ->
            if (requestCode == PERMISSION_REQUEST_CODE) {
                emit(
                    mapOf(
                        "type" to "permissionResult",
                        "granted" to (grantResult == PackageManager.PERMISSION_GRANTED),
                    )
                )
            }
        }

    init {
        // sticky：如果 binder 在注册监听前就已就绪，也要立刻收到一次回调
        Shizuku.addBinderReceivedListenerSticky(binderReceivedListener)
        Shizuku.addBinderDeadListener(binderDeadListener)
        Shizuku.addRequestPermissionResultListener(permissionListener)
    }

    fun dispose() {
        try {
            Shizuku.removeBinderReceivedListener(binderReceivedListener)
            Shizuku.removeBinderDeadListener(binderDeadListener)
            Shizuku.removeRequestPermissionResultListener(permissionListener)
        } catch (_: Throwable) {
            // Shizuku 可能已经退出，忽略
        }
        events = null
        io.shutdownNow()
    }

    // ---------------------------------------------------------------- 事件通道

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        events = sink
        // 连上就先推一次当前状态，Dart 侧不必再轮询
        emit(
            mapOf(
                "type" to "state",
                "supported" to isSupported(),
                "running" to isRunning(),
                "granted" to hasPermission(),
            )
        )
    }

    override fun onCancel(arguments: Any?) {
        events = null
    }

    private fun emit(payload: Map<String, Any?>) {
        main.post { events?.success(payload) }
    }

    // ---------------------------------------------------------------- 状态查询

    private fun isSupported(): Boolean = try {
        Shizuku.pingBinder()
    } catch (_: Throwable) {
        false
    }

    private fun isRunning(): Boolean = try {
        Shizuku.pingBinder() && !Shizuku.isPreV11()
    } catch (_: Throwable) {
        false
    }

    private fun hasPermission(): Boolean = try {
        if (Shizuku.isPreV11()) {
            false
        } else {
            Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
        }
    } catch (_: Throwable) {
        false
    }

    // ---------------------------------------------------------------- 方法通道

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "state" -> result.success(
                mapOf(
                    "supported" to isSupported(),
                    "running" to isRunning(),
                    "granted" to hasPermission(),
                )
            )

            "requestPermission" -> requestPermission(result)

            "exec" -> {
                val cmd = call.argument<String>("cmd")
                val binary = call.argument<Boolean>("binary") ?: false
                val timeout =
                    (call.argument<Int>("timeoutMs") ?: DEFAULT_TIMEOUT_MS.toInt()).toLong()
                if (cmd.isNullOrBlank()) {
                    result.error("bad_args", "cmd 不能为空", null)
                } else {
                    exec(cmd, binary, timeout, result)
                }
            }

            else -> result.notImplemented()
        }
    }

    private fun requestPermission(result: MethodChannel.Result) {
        try {
            if (!Shizuku.pingBinder()) {
                result.error("not_running", "Shizuku 未运行", null)
                return
            }
            if (hasPermission()) {
                result.success(true)
                return
            }
            Shizuku.requestPermission(PERMISSION_REQUEST_CODE)
            // 结果通过 EventChannel 的 permissionResult 事件回传
            result.success(true)
        } catch (t: Throwable) {
            result.error("request_failed", t.message ?: t.toString(), null)
        }
    }

    /** 取 AIDL 服务。Shizuku 未运行时返回 null。 */
    private fun service(): IShizukuService? {
        return try {
            val binder = Shizuku.getBinder() ?: return null
            IShizukuService.Stub.asInterface(binder)
        } catch (_: Throwable) {
            null
        }
    }

    /**
     * 以 shell 身份执行命令。
     *
     * 用两个线程分别读 stdout / stderr —— 只读一个的话，另一个管道写满后
     * 子进程会阻塞，表现为「命令卡住不返回」。
     *
     * 超时判断用「stdout 读取线程是否结束」而不是 `waitForTimeout`：
     * 进程退出时管道关闭，读取线程自然结束，这个信号比轮询 alive() 更可靠。
     */
    private fun exec(
        command: String,
        binary: Boolean,
        timeoutMs: Long,
        result: MethodChannel.Result,
    ) {
        io.execute {
            val svc = service()
            if (svc == null) {
                main.post {
                    result.error("no_service", "无法获取 Shizuku 服务，请确认已授权", null)
                }
                return@execute
            }

            var remote: moe.shizuku.server.IRemoteProcess? = null
            try {
                remote = svc.newProcess(arrayOf("sh", "-c", command), null, null)
                    ?: throw IllegalStateException("Shizuku 返回了空的进程对象")

                val outBuf = ByteArrayOutputStream()
                val errBuf = ByteArrayOutputStream()

                val outStream =
                    ParcelFileDescriptor.AutoCloseInputStream(remote.inputStream)
                val errStream =
                    ParcelFileDescriptor.AutoCloseInputStream(remote.errorStream)

                val tOut = Thread { runCatching { outStream.use { it.copyTo(outBuf) } } }
                val tErr = Thread { runCatching { errStream.use { it.copyTo(errBuf) } } }
                tOut.isDaemon = true
                tErr.isDaemon = true
                tOut.start()
                tErr.start()

                // 等 stdout 读完；读不完说明进程还在跑，就是超时
                tOut.join(timeoutMs)
                if (tOut.isAlive) {
                    runCatching { remote.destroy() }
                    tOut.join(400)
                    tErr.join(400)
                    postResult(
                        result,
                        mapOf(
                            "stdout" to "",
                            "stderr" to "命令执行超时（${timeoutMs}ms），已终止",
                            "code" to -1,
                            "timedOut" to true,
                        ),
                        null,
                    )
                    return@execute
                }

                tErr.join(1_500)

                val code = try {
                    remote.exitValue()
                } catch (_: Throwable) {
                    0
                }

                val stdoutBytes = outBuf.toByteArray()
                val stderr = errBuf.toByteArray().toString(Charsets.UTF_8)

                if (binary) {
                    postResult(
                        result,
                        mapOf("code" to code, "stderr" to stderr),
                        stdoutBytes,
                    )
                } else {
                    postResult(
                        result,
                        mapOf(
                            "stdout" to stdoutBytes.toString(Charsets.UTF_8),
                            "stderr" to stderr,
                            "code" to code,
                            "timedOut" to false,
                        ),
                        null,
                    )
                }
            } catch (t: Throwable) {
                runCatching { remote?.destroy() }
                main.post {
                    result.error("exec_failed", t.message ?: t.toString(), null)
                }
            }
        }
    }

    private fun postResult(
        result: MethodChannel.Result,
        payload: Map<String, Any?>,
        bytes: ByteArray?,
    ) {
        main.post {
            if (bytes != null) {
                val m = HashMap<String, Any?>(payload)
                m["bytes"] = bytes
                result.success(m)
            } else {
                result.success(payload)
            }
        }
    }
}
