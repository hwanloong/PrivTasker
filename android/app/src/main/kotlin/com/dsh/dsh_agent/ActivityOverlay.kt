package com.dsh.dsh_agent

import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView

/**
 * 屏幕底部的"正在干什么"小浮窗。
 *
 * ## 为什么需要它
 *
 * agent 可以在后台跑很久（多轮工具调用、长任务）。切出去之后，用户
 * **完全不知道它还在不在干活** —— 只能靠猜，或者切回来看看。
 *
 * 这个浮窗回答的就是那一个问题：现在在干什么。
 *
 * ## 和 ActivityOverlay（确认框）的关系
 *
 * 两者都用 `TYPE_APPLICATION_OVERLAY`，会互相盖住。所以：
 * **弹确认框时先把浮窗收起来，确认完再放回来。**
 * 由 [OverlayConfirm]/[MainActivity] 那边协调，不在这里处理。
 *
 * ## 只在应用不在前台时显示
 *
 * 应用在前台时界面本身就有进度（工具卡片、转圈），
 * 再压一个浮窗是纯粹的视觉噪音。所以是否显示由 Dart 侧的
 * 生命周期状态决定，而不是这里自己判断。
 */
class ActivityOverlay(private val context: Context) {

    private var view: View? = null
    private var textView: TextView? = null
    private val main = Handler(Looper.getMainLooper())

    /** 当前文案。浮窗被临时收起后要靠它恢复。 */
    private var currentText: String = ""

    /** 是否应该显示（生命周期由 Dart 决定）。 */
    private var shouldShow = false

    private val wm: WindowManager?
        get() = context.getSystemService(Context.WINDOW_SERVICE) as? WindowManager

    private fun dp(v: Int): Int = TypedValue.applyDimension(
        TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), context.resources.displayMetrics
    ).toInt()

    // ------------------------------------------------------------ 对外

    /** 显示 / 更新文案 */
    fun show(text: String) {
        currentText = text
        shouldShow = true
        main.post { render() }
    }

    /** 收起（但记住应该显示，之后可恢复） */
    fun hide() {
        shouldShow = false
        main.post { detach() }
    }

    /** 彻底关掉，不再恢复 */
    fun dismiss() {
        shouldShow = false
        currentText = ""
        main.post { detach() }
    }

    // ------------------------------------------------------------ 实现

    private fun render() {
        val w = wm ?: return
        if (!shouldShow) {
            detach()
            return
        }

        val v = view ?: build().also { view = it }

        // 文案变了就更新，不重建视图
        textView?.text = currentText

        if (v.parent == null) {
            try {
                w.addView(v, params())
            } catch (e: Exception) {
                // 权限被撤、或系统拒绝添加 —— 静默失败。
                // 浮窗只是锦上添花，不能因为加不上就影响 agent 干活。
                view = null
                textView = null
            }
        }
    }

    private fun detach() {
        val v = view ?: return
        try {
            if (v.parent != null) wm?.removeView(v)
        } catch (e: Exception) {
            // 已经移除过了
        }
    }

    private fun params(): WindowManager.LayoutParams {
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        return WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            // 不抢焦点：用户还能正常操作底下的应用
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            // 抬高一点，避开全面屏手势条和底部导航
            y = dp(96)
        }
    }

    private fun build(): View {
        val row = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(14), dp(9), dp(16), dp(9))
            background = GradientDrawable().apply {
                cornerRadius = dp(999).toFloat()
                setColor(Color.parseColor("#E6202124")) // 半透明深色，两种主题下都看得清
            }
        }

        // 小圆点表示"在动"。没有它，静止的文字会让人觉得卡住了。
        val dot = View(context).apply {
            val size = dp(7)
            layoutParams = LinearLayout.LayoutParams(size, size).apply {
                rightMargin = dp(9)
            }
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#FF4F7DF3"))
            }
        }

        val tv = TextView(context).apply {
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
            // 限制宽度，长命令不能把浮窗撑到半个屏幕
            maxWidth = dp(260)
            text = currentText
        }

        row.addView(dot)
        row.addView(tv)
        textView = tv
        return row
    }
}
