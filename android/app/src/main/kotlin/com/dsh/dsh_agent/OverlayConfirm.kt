package com.dsh.dsh_agent

import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/**
 * 系统级悬浮窗确认框。
 *
 * 为什么需要它：应用内的 `showDialog` 只在 DSH 自己处于前台时可见。
 * 但工具很容易把别的应用切到前台（`am start`、点开链接、拉起设置页……），
 * 这时弹窗被盖在下面，用户必须先切回来才能确认 —— 交互很别扭，
 * 而且用户可能以为程序卡住了。
 *
 * 悬浮窗走 [WindowManager] 的 TYPE_APPLICATION_OVERLAY，由系统合成，
 * 无论前台是谁都在最上层，点完直接回传结果，不需要切换应用。
 *
 * 权限：需要 SYSTEM_ALERT_WINDOW（"显示在其他应用上层"），
 * 属于特殊权限，只能跳系统设置页让用户手动开。
 */
class OverlayConfirm(private val context: Context) {

    private val main = Handler(Looper.getMainLooper())
    private var root: View? = null
    private var timeoutToken: Runnable? = null
    private var pending: ((Boolean) -> Unit)? = null

    companion object {
        /**
         * 无人操作时的兜底时长，避免悬浮窗永远挂在屏幕上。
         * 2 分钟足够用户切回来处理，又不会让界面长时间像卡死。
         */
        private const val AUTO_REJECT_MS = 120_000L
    }

    fun canDraw(): Boolean = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(context)
        } else {
            true
        }
    } catch (_: Throwable) {
        false
    }

    fun requestPermission() {
        try {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:${context.packageName}")
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
        } catch (_: Throwable) {
            // 个别 ROM 没有这个页面，退回到应用详情页
            try {
                context.startActivity(
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                        .setData(Uri.parse("package:${context.packageName}"))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
            } catch (_: Throwable) {
            }
        }
    }

    private fun dp(v: Int): Int = TypedValue.applyDimension(
        TypedValue.COMPLEX_UNIT_DIP,
        v.toFloat(),
        context.resources.displayMetrics
    ).toInt()

    private fun isDark(): Boolean =
        (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
                Configuration.UI_MODE_NIGHT_YES

    /**
     * 弹出确认框。[onResult] 只会被调用一次：用户点按钮、或超时自动拒绝。
     */
    fun show(
        title: String,
        command: String,
        reasons: List<String>,
        dangerous: Boolean,
        onResult: (Boolean) -> Unit,
    ) {
        // 上一个确认还没结果就再弹一个的话，先把旧的按「拒绝」结掉，
        // 否则 Dart 侧那个 await 会永远挂着。
        pending?.let { old ->
            pending = null
            main.post { old(false) }
        }
        dismiss()

        if (!canDraw()) {
            onResult(false)
            return
        }

        pending = onResult

        val dark = isDark()
        val cardBg = if (dark) 0xFF121216.toInt() else 0xFFFFFFFF.toInt()
        val textColor = if (dark) 0xFFEDEDF1.toInt() else 0xFF0A0A0C.toInt()
        val mutedColor = if (dark) 0xFF8A8A92.toInt() else 0xFF82868F.toInt()
        val codeBg = if (dark) 0xFF08080A.toInt() else 0xFFEFEFF2.toInt()
        val borderColor = if (dark) 0xFF2A2A32.toInt() else 0xFFE4E4E8.toInt()
        val dangerColor = 0xFFFF453A.toInt()
        val accentColor = 0xFF4F7DF3.toInt()
        val warnColor = 0xFFFF9F0A.toInt()
        val btnBg = if (dark) 0xFF1C1C22.toInt() else 0xFFF4F4F6.toInt()

        val accent = if (dangerous) dangerColor else accentColor

        // ---- 遮罩 ----
        val scrim = FrameLayout(context).apply {
            setBackgroundColor(0xB3000000.toInt())
        }

        // ---- 卡片 ----
        val card = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(18), dp(20), dp(16))
            background = GradientDrawable().apply {
                cornerRadius = dp(20).toFloat()
                setColor(cardBg)
                setStroke(dp(1), borderColor)
            }
        }

        // 标题行
        val titleRow = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        titleRow.addView(TextView(context).apply {
            text = if (dangerous) "⚠" else "?"
            setTextColor(if (dangerous) dangerColor else warnColor)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
        }, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { rightMargin = dp(9) })

        titleRow.addView(TextView(context).apply {
            text = title
            setTextColor(textColor)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
            setTypeface(typeface, Typeface.BOLD)
        }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        card.addView(titleRow)

        card.addView(TextView(context).apply {
            text = if (dangerous) "以下命令将被执行，请确认无误。" else "请求执行以下内容："
            setTextColor(mutedColor)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12.5f)
        }, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { topMargin = dp(6) })

        // 命令框
        card.addView(TextView(context).apply {
            text = command
            setTextColor(textColor)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12.5f)
            typeface = Typeface.MONOSPACE
            setTextIsSelectable(true)
            setPadding(dp(11), dp(9), dp(11), dp(9))
            background = GradientDrawable().apply {
                cornerRadius = dp(10).toFloat()
                setColor(codeBg)
            }
        }, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { topMargin = dp(10) })

        // 风险条目
        if (reasons.isNotEmpty()) {
            for (r in reasons) {
                val row = LinearLayout(context).apply {
                    orientation = LinearLayout.HORIZONTAL
                }
                row.addView(TextView(context).apply {
                    text = "·"
                    setTextColor(accent)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                }, LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT
                ).apply { rightMargin = dp(8) })

                row.addView(TextView(context).apply {
                    text = r
                    setTextColor(if (dark) 0xFFC9C9D2.toInt() else 0xFF3D434F.toInt())
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 12.5f)
                }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))

                card.addView(row, LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT
                ).apply { topMargin = dp(7) })
            }
        }

        // AI 生成提示
        card.addView(TextView(context).apply {
            text = "该内容由 AI 自动生成，不是你自己输入的。"
            setTextColor(mutedColor)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11.5f)
            alpha = 0.9f
        }, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { topMargin = dp(12) })

        // 按钮行
        val btnRow = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
        }

        val reject = TextView(context).apply {
            text = "拒绝"
            gravity = Gravity.CENTER
            setTextColor(textColor)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            setTypeface(typeface, Typeface.BOLD)
            setPadding(0, dp(12), 0, dp(12))
            background = GradientDrawable().apply {
                cornerRadius = dp(999).toFloat()
                setColor(btnBg)
                setStroke(dp(1), borderColor)
            }
            isClickable = true
            setOnClickListener { finish(false) }
        }
        btnRow.addView(reject, LinearLayout.LayoutParams(
            0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f
        ).apply { rightMargin = dp(5) })

        val confirm = TextView(context).apply {
            text = if (dangerous) "仍然执行" else "执行"
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            setTypeface(typeface, Typeface.BOLD)
            setPadding(0, dp(12), 0, dp(12))
            background = GradientDrawable().apply {
                cornerRadius = dp(999).toFloat()
                setColor(accent)
            }
            isClickable = true
            setOnClickListener { finish(true) }
        }
        btnRow.addView(confirm, LinearLayout.LayoutParams(
            0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f
        ).apply { leftMargin = dp(5) })

        card.addView(btnRow, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { topMargin = dp(14) })

        // 内容可能很长（命令 + 多条理由），套一层限高的滚动容器
        val scroller = ScrollView(context).apply {
            isFillViewport = false
            addView(card, ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ))
        }

        val maxHeight = (context.resources.displayMetrics.heightPixels * 0.72f).toInt()
        val wrap = FrameLayout(context).apply {
            setPadding(dp(20), dp(20), dp(20), dp(20))
        }
        wrap.addView(scroller, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply {
            gravity = Gravity.CENTER
            height = maxHeight
        })

        scrim.addView(wrap, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        ))

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            type,
            // NOT_FOCUSABLE：不抢输入焦点（不弹键盘），但触摸照常可达。
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        )

        try {
            val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
            wm.addView(scrim, lp)
            root = scrim

            // 无人操作时自动拒绝，防止悬浮窗永久占屏
            val token = Runnable { finish(false) }
            timeoutToken = token
            main.postDelayed(token, AUTO_REJECT_MS)
        } catch (t: Throwable) {
            val cb = pending
            pending = null
            root = null
            cb?.invoke(false)
        }
    }

    /** 回传结果并移除悬浮窗。只会生效一次。 */
    private fun finish(approved: Boolean) {
        val cb = pending ?: return
        pending = null
        dismiss()
        main.post { cb(approved) }
    }

    fun dismiss() {
        timeoutToken?.let { main.removeCallbacks(it) }
        timeoutToken = null
        val v = root ?: return
        root = null
        try {
            val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
            wm.removeView(v)
        } catch (_: Throwable) {
            // 已经被移除过，忽略
        }
    }
}
