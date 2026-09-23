package com.dsh.dsh_agent

import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/**
 * 与 Termux 应用通信的桥。
 *
 * ## 为什么是"请 Termux 代跑"，而不是自己内置一套环境
 *
 * Termux 的二进制把路径编译死成 `/data/data/com.termux/files/usr`，而这个路径
 * **只有 root 能创建**（`/data/data` 目录本身不允许普通应用写入，Shizuku 给的
 * shell 权限也不是 root）。所以想在别的包名下跑它的环境，就必须上 proot 做
 * bind mount —— 那会引入一个来源和许可都要单独核对的第三方二进制。
 *
 * 而 Termux 自己就在那个路径下运行，前缀天然正确。**我们只是请它代跑。**
 * 这条路同时避开了：proot 依赖、31MB bootstrap、包管理维护、许可问题。
 *
 * ## 官方接口
 *
 * Termux 从 v0.109 起提供 `com.termux.RUN_COMMAND`：
 * 把命令交给 `com.termux.app.RunCommandService` 执行，结果通过调用方传入的
 * PendingIntent 广播回来。
 *
 * **两个前提，缺一不可：**
 *  1. 调用方在 manifest 里声明 `com.termux.permission.RUN_COMMAND`
 *  2. 用户必须在 Termux 里打开 `allow-external-apps=true`
 *     （`~/.termux/termux.properties`，默认是关的）
 *
 * 第 2 条无法用代码检测，只能靠调用失败时的错误码来判断并引导用户。
 */
class TermuxBridge(private val context: Context) {

    companion object {
        private const val TERMUX_PACKAGE = "com.termux"
        private const val TERMUX_SERVICE = "com.termux.app.RunCommandService"

        private const val ACTION_RUN_COMMAND = "com.termux.RUN_COMMAND"
        private const val EXTRA_COMMAND_PATH = "com.termux.RUN_COMMAND_PATH"
        private const val EXTRA_ARGUMENTS = "com.termux.RUN_COMMAND_ARGUMENTS"
        private const val EXTRA_WORKDIR = "com.termux.RUN_COMMAND_WORKDIR"
        private const val EXTRA_BACKGROUND = "com.termux.RUN_COMMAND_BACKGROUND"
        private const val EXTRA_SESSION_ACTION = "com.termux.RUN_COMMAND_SESSION_ACTION"
        private const val EXTRA_COMMAND_LABEL = "com.termux.RUN_COMMAND_COMMAND_LABEL"
        private const val EXTRA_PENDING_INTENT = "com.termux.RUN_COMMAND_PENDING_INTENT"
        private const val EXTRA_RESULT_BUNDLE = "com.termux.RUN_COMMAND_RESULT_BUNDLE"

        /** Termux 的 bash 绝对路径。不用 `bash` 是因为 PATH 在我们这边是空的。 */
        private const val TERMUX_BASH = "/data/data/com.termux/files/usr/bin/bash"

        private val requestCounter = AtomicInteger(1000)
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    // ------------------------------------------------------------ 可用性

    /** Termux 装了没有 */
    fun isInstalled(): Boolean {
        return try {
            context.packageManager.getPackageInfo(TERMUX_PACKAGE, 0)
            true
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }
    }

    /**
     * 我们有没有被授权调用 Termux。
     *
     * 注意这**只能检查权限声明**，查不到 `allow-external-apps` ——
     * 那个是 Termux 内部的设置项，没有对外暴露的查询接口。
     * 所以为 true 也不代表一定能执行，真正的判定要等第一次调用返回的错误码。
     */
    fun hasPermission(): Boolean {
        return context.checkSelfPermission("com.termux.permission.RUN_COMMAND") ==
                PackageManager.PERMISSION_GRANTED
    }

    // ------------------------------------------------------------ 执行

    /**
     * 要执行的一段命令。
     *
     * 用 `bash -lc` 而不是 `bash -c`：
     * `-l` 会加载 login profile，这样 `pkg`、`python` 这些
     * 装在 `$PREFIX/bin` 里的命令才能被 PATH 找到。
     * 不加的话，用户环境里的命令全都"不存在"。
     */
    fun bashArgsFor(command: String): Array<String> = arrayOf("-lc", command)

    /**
     * 执行命令并等待结果。
     *
     * **必须在线程池里调用**，它会阻塞。
     *
     * @param background true 时 Termux 不等命令结束就返回（长任务用），
     *                   此时拿不到输出，需要配合日志文件自行轮询。
     */
    fun run(
        command: String,
        workdir: String?,
        background: Boolean,
        timeoutMs: Long,
    ): Map<String, Any?> {
        if (!isInstalled()) {
            return failure("Termux 未安装", "NOT_INSTALLED")
        }

        val requestCode = requestCounter.incrementAndGet()
        val resultAction = "com.dsh.dsh_agent.TERMUX_RESULT.$requestCode"

        val latch = CountDownLatch(1)
        // 用数组装结果，因为要在匿名内部类里写
        val holder = arrayOfNulls<Bundle>(1)

        val receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context?, intent: Intent?) {
                holder[0] = intent?.getBundleExtra(EXTRA_RESULT_BUNDLE)
                latch.countDown()
            }
        }

        val filter = IntentFilter(resultAction)
        // Android 14+ 要求显式声明导出状态
        if (Build.VERSION.SDK_INT >= 33) {
            ContextCompat.registerReceiver(
                context, receiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED
            )
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            context.registerReceiver(receiver, filter)
        }

        try {
            val pendingIntent = android.app.PendingIntent.getBroadcast(
                context,
                requestCode,
                Intent(resultAction).setPackage(context.packageName),
                android.app.PendingIntent.FLAG_ONE_SHOT or
                        android.app.PendingIntent.FLAG_UPDATE_CURRENT or
                        android.app.PendingIntent.FLAG_IMMUTABLE,
            )

            val intent = Intent().apply {
                action = ACTION_RUN_COMMAND
                component = ComponentName(TERMUX_PACKAGE, TERMUX_SERVICE)
                putExtra(EXTRA_COMMAND_PATH, TERMUX_BASH)
                putExtra(EXTRA_ARGUMENTS, bashArgsFor(command))
                if (!workdir.isNullOrBlank()) putExtra(EXTRA_WORKDIR, workdir)
                putExtra(EXTRA_BACKGROUND, background)
                // 0 = 不切换 Termux 的前台会话，避免我们的调用把用户正在看的终端顶掉
                putExtra(EXTRA_SESSION_ACTION, 0)
                putExtra(EXTRA_COMMAND_LABEL, "PrivTasker")
                putExtra(EXTRA_PENDING_INTENT, pendingIntent)
            }

            try {
                context.startService(intent)
            } catch (e: Exception) {
                return failure("无法启动 Termux 服务：${e.message}", "START_FAILED")
            }

            if (background) {
                // 后台模式不等结果：Termux 只在命令结束时才广播，
                // 而"后台"的意义正是不等它。
                return mapOf(
                    "ok" to true,
                    "stdout" to "",
                    "stderr" to "",
                    "exitCode" to 0,
                    "background" to true,
                )
            }

            val got = latch.await(timeoutMs, TimeUnit.MILLISECONDS)
            if (!got) {
                return failure(
                    "等待 Termux 返回超时（${timeoutMs / 1000} 秒）。" +
                            "长任务请用 background 模式，输出重定向到文件后轮询。",
                    "TIMEOUT",
                )
            }
        } finally {
            try {
                context.unregisterReceiver(receiver)
            } catch (_: Exception) {
                // 已经注销过就忽略
            }
        }

        val bundle = holder[0]
            ?: return failure(
                "Termux 没有返回结果。最常见的原因是 **allow-external-apps 没打开** —— " +
                        "需要你在 Termux 里执行：\n" +
                        "  echo 'allow-external-apps=true' >> ~/.termux/termux.properties\n" +
                        "  termux-reload-settings\n" +
                        "改完再试一次。",
                "NO_RESULT",
            )

        val stdout = bundle.getString("stdout") ?: ""
        val stderr = bundle.getString("stderr") ?: ""
        val exitCode = bundle.getInt("exitCode", 0)
        val errCode = bundle.getInt("errCode", 0)
        val errmsg = bundle.getString("errmsg") ?: ""

        if (errCode != 0) {
            return mapOf(
                "ok" to false,
                "stdout" to stdout,
                "stderr" to stderr,
                "exitCode" to exitCode,
                "error" to "Termux 内部错误（errCode=$errCode）：$errmsg",
                "errorKind" to "TERMUX_ERROR",
            )
        }

        return mapOf(
            "ok" to true,
            "stdout" to stdout,
            "stderr" to stderr,
            "exitCode" to exitCode,
        )
    }

    private fun failure(message: String, kind: String): Map<String, Any?> = mapOf(
        "ok" to false,
        "stdout" to "",
        "stderr" to "",
        "exitCode" to -1,
        "error" to message,
        "errorKind" to kind,
    )
}
