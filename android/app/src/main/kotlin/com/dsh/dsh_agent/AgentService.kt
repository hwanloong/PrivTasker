package com.dsh.dsh_agent

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * agent 在后台跑时的常驻前台服务。
 *
 * ## 为什么必须有它
 *
 * Android 会把后台进程按内存压力回收。agent 跑一个长任务（编译、批量处理、
 * 多轮工具调用）时被回收，用户看到的是"跑到一半没动静了"，而且**没有任何提示**。
 *
 * 前台服务是唯一能让系统知道"这个进程正在为用户干活，别动它"的机制。
 * 代价是**必须显示一个常驻通知** —— 这是 Android 的硬性要求，
 * 不是我们想骚扰用户。所以通知文案要老实说明在干什么。
 *
 * ## 为什么同时还要申请"忽略电池优化"
 *
 * 前台服务挡得住内存回收，**挡不住 Doze** —— 打盹模式下 CPU 会被挂起，
 * 网络会被切断。跑长任务时这同样是致命的。
 *
 * 两者是互补的，缺一不可。
 */
class AgentService : Service() {

    companion object {
        const val CHANNEL_ID = "dsh_agent_running"
        const val NOTIFICATION_ID = 0x4453 // "DS"

        /** 更新通知文案 */
        const val ACTION_UPDATE = "com.dsh.dsh_agent.SERVICE_UPDATE"
        const val EXTRA_TEXT = "text"

        fun start(ctx: Context, text: String) {
            val i = Intent(ctx, AgentService::class.java).apply {
                action = ACTION_UPDATE
                putExtra(EXTRA_TEXT, text)
            }
            if (Build.VERSION.SDK_INT >= 26) {
                ctx.startForegroundService(i)
            } else {
                ctx.startService(i)
            }
        }

        fun update(ctx: Context, text: String) = start(ctx, text)

        fun stop(ctx: Context) {
            ctx.stopService(Intent(ctx, AgentService::class.java))
        }
    }

    private var currentText: String = "正在执行任务…"

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_UPDATE) {
            currentText = intent.getStringExtra(EXTRA_TEXT) ?: currentText
        }

        // **必须在 5 秒内调用 startForeground**，否则系统会直接杀掉进程
        // 并报 ANR。所以放在 onStartCommand 的最前面。
        startForeground(NOTIFICATION_ID, buildNotification(currentText))

        // START_STICKY：被系统杀掉后自动重建。
        // 长任务场景下这比"干脆不重启"更符合用户预期。
        return START_STICKY
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < 26) return
        val mgr = getSystemService(NotificationManager::class.java) ?: return
        if (mgr.getNotificationChannel(CHANNEL_ID) != null) return

        val ch = NotificationChannel(
            CHANNEL_ID,
            "后台任务",
            // LOW：不发声、不震动、不在状态栏显示图标。
            // 这是"正在进行"的提示，不是需要用户注意的事件 ——
            // 用 DEFAULT 会让每次 agent 跑任务都叮一下，很烦。
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Agent 在后台执行任务时显示"
            setShowBadge(false)
        }
        mgr.createNotificationChannel(ch)
    }

    private fun buildNotification(text: String): Notification {
        // 点通知回到应用
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        // 通知里一个"停止"按钮 —— agent 跑飞了时用户能立刻叫停，
        // 不用先切回应用
        val stopIntent = PendingIntent.getService(
            this,
            1,
            Intent(this, AgentService::class.java).apply { action = "STOP" },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("PrivTasker 正在工作")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setOngoing(true)          // 划不掉：它表示一个正在进行的任务
            .setOnlyAlertOnce(true)    // 更新文案时不再提醒
            .setContentIntent(open)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .addAction(0, "停止", stopIntent)
            .build()
    }

    override fun onDestroy() {
        currentText = ""
        super.onDestroy()
    }
}
