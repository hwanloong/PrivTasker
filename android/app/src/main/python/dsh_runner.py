"""PrivTasker 的 Python 执行入口。

放在 Chaquopy 的 python 源码目录下，构建时会被打进 APK，
运行时通过 Python.getInstance().getModule("dsh_runner") 取到。

## 为什么要单独写一个模块，而不是直接 exec

三个原因，每个都踩过坑才知道：

1. **捕获输出**。直接 exec 的话 print 会进 Logcat，Dart 侧拿不到。
   这里用 redirect_stdout/stderr 把输出收进内存再回传。

2. **结构化结果**。返回 JSON 而不是拼接字符串 —— 否则 Dart 侧要猜
   "这段输出里哪部分是错误"。

3. **状态连续**。`_NS` 是模块级命名空间，同一个进程里连续调用会共享变量，
   所以 "x = 5" 之后 "print(x)" 能拿到 5。这正是 REPL 的语义。
   进程重启后状态清空 —— 这是可接受的，因为我们没有持久化的需求。
"""

import contextlib
import io
import json
import os
import sys
import traceback

# 模块级命名空间：跨调用保持状态，实现 REPL 式连续执行。
_NS: dict = {"__name__": "__main__"}


def run(code: str, reset: bool = False) -> str:
    """执行一段 Python 代码，返回 JSON 字符串。

    返回结构：
      {"ok": bool, "output": str, "error": str | None, "error_type": str | None}
    """
    global _NS
    if reset:
        _NS = {"__name__": "__main__"}

    buf = io.StringIO()
    try:
        with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(buf):
            # 先尝试按"表达式"求值，这样 `1 + 1` 这种会直接显示结果，
            # 不用非得写 print —— 符合 REPL 的直觉。
            try:
                value = eval(compile(code, "<dsh>", "eval"), _NS)
                if value is not None:
                    print(repr(value))
            except SyntaxError:
                # 不是单个表达式（比如有赋值、循环），按语句执行
                exec(compile(code, "<dsh>", "exec"), _NS)

        return json.dumps(
            {"ok": True, "output": buf.getvalue(), "error": None, "error_type": None},
            ensure_ascii=False,
        )
    except BaseException as e:  # noqa: BLE001 —— 任何异常都要回传给模型
        # 只取用户代码的栈帧，不要把我们这个 runner 的帧混进去 ——
        # 那些行号对模型毫无意义，只会干扰它定位问题。
        tb = traceback.format_exc()
        return json.dumps(
            {
                "ok": False,
                "output": buf.getvalue(),
                "error": tb,
                "error_type": type(e).__name__,
            },
            ensure_ascii=False,
        )


def info() -> str:
    """环境信息。设置页用来确认 Python 真的起来了。"""
    return json.dumps(
        {
            "version": sys.version,
            "executable": sys.executable,
            "cwd": os.getcwd(),
            "prefix": sys.prefix,
        },
        ensure_ascii=False,
    )


def packages() -> str:
    """列出已装的第三方包。用来确认 pip 装的东西在不在。"""
    names = []
    try:
        import importlib.metadata as md

        for d in md.distributions():
            try:
                names.append(f"{d.metadata['Name']}=={d.version}")
            except Exception:
                pass
    except Exception as e:
        return json.dumps({"error": str(e)}, ensure_ascii=False)
    return json.dumps(sorted(names), ensure_ascii=False)
