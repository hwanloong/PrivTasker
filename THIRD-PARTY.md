# 第三方组件与许可

本文件说明本项目**没有**自带哪些东西，以及依赖了什么。发布或分发前请务必读完第一节。

---

## ⚠️ 字体：未随仓库分发

本项目界面用到三款字体，**它们都是商业专有字体，不包含在本仓库中**，也不得随本项目再分发。

| 字体 | 权利人 | 用途 |
|---|---|---|
| **Times New Roman** | Monotype | 英文正文 |
| **宋体 SimSun** | 中易中标 / Microsoft | 中文正文 |
| **Consolas** | Microsoft | 代码块 |

这些字体随 Windows 授权给**本机使用者**，授权范围**不包括再分发**。
把它们打进公开仓库、APK 或任何形式的公开分发，都属于侵权。

因此：

- `assets/fonts/*.ttf` 已在 `.gitignore` 中被排除
- 仓库里只有 `assets/fonts/README.md` 说明如何自行准备
- **不要把这些字体文件提交到公开仓库，也不要把带字体的 APK 公开分发**

### 自己构建时怎么准备字体

字体只在你自己的机器上使用，属于正常的系统授权范围。

```powershell
cd D:\pj3\dsh_agent\assets\fonts

# 1) 从本机 Windows 复制（Times / Consolas 是单文件）
Copy-Item C:\Windows\Fonts\times.ttf    .
Copy-Item C:\Windows\Fonts\timesbd.ttf  .
Copy-Item C:\Windows\Fonts\timesi.ttf   .
Copy-Item C:\Windows\Fonts\timesbi.ttf  .
Copy-Item C:\Windows\Fonts\consola.ttf  .
Copy-Item C:\Windows\Fonts\consolab.ttf .
Copy-Item C:\Windows\Fonts\consolai.ttf .

# 2) 宋体是 TrueType 集合（.ttc），要抽成独立 TTF
Copy-Item C:\Windows\Fonts\simsun.ttc .
& "D:\flutter\flutter_windows_3.47.4-stable\flutter\bin\cache\dart-sdk\bin\dart.exe" `
  ..\..\tools\extract_ttc.dart simsun.ttc simsun.ttf 0
Remove-Item simsun.ttc      # 别把 17.8MB 的集合文件也留下
```

抽出来应该是 `simsun.ttf`，约 17.5 MB，文件头是 `00 01 00 00`。

> **为什么要抽而不是直接用 `.ttc`：** Flutter 对 TrueType 集合的支持不明确，
> 最坏情况是加载失败后**静默回退成黑体** —— 界面上中文会变成另一种字体，
> 而这种问题在手机上不容易当场发现。详见 `tools/extract_ttc.dart` 里的说明。

### 想换成可自由分发的字体

如果打算公开分发带字体的构建产物，需要换成开源字体。功能等价的选择：

| 用途 | 开源替代 | 许可 |
|---|---|---|
| 中文宋体 / 明朝体 | [Source Han Serif](https://github.com/adobe-fonts/source-han-serif)（思源宋体） | SIL OFL 1.1 |
| 英文衬线 | [EB Garamond](https://github.com/octaviopardo/EBGaramond12) / [Linux Libertine](https://github.com/alerque/libertinus) | SIL OFL 1.1 |
| 等宽 | [JetBrains Mono](https://github.com/JetBrains/JetBrainsMono) | SIL OFL 1.1 |

换字体只需要改 `pubspec.yaml` 的 `fonts:` 段和 `lib/theme/app_theme.dart` 里的
`AppFonts.latin` / `cjk` / `mono` 三个家族名 —— 全项目只有这两处引用字体名。

---

## 依赖项

Flutter 生态的依赖，许可均为宽松开源许可，随各自的包分发。

### 直接依赖

| 包 | 许可 | 说明 |
|---|---|---|
| [flutter_inappwebview](https://pub.dev/packages/flutter_inappwebview) | Apache-2.0 | 内置浏览器。**本项目对其 Android 实现做了本地补丁**，见下 |
| [flutter_math_fork](https://pub.dev/packages/flutter_math_fork) | MIT | LaTeX 数学公式渲染（纯 Dart，自带 KaTeX 字体，KaTeX 字体为 MIT） |
| [google_mlkit_text_recognition](https://pub.dev/packages/google_mlkit_text_recognition) | MIT（插件本身） | 本地 OCR。底层 Google ML Kit 受 [Google APIs 服务条款](https://developers.google.com/ml-kit/terms) 约束 |
| [http](https://pub.dev/packages/http) | BSD-3-Clause | 网络请求 |
| [shared_preferences](https://pub.dev/packages/shared_preferences) | BSD-3-Clause | 设置持久化 |
| [path_provider](https://pub.dev/packages/path_provider) | BSD-3-Clause | 目录定位 |
| [image_picker](https://pub.dev/packages/image_picker) | Apache-2.0 | 选图 |
| [file_selector](https://pub.dev/packages/file_selector) | BSD-3-Clause | 选文件、导入导出 |
| [url_launcher](https://pub.dev/packages/url_launcher) | BSD-3-Clause | 打开链接 |

### Android 原生

| 组件 | 许可 | 说明 |
|---|---|---|
| [Shizuku API](https://github.com/RikkaApps/Shizuku-API) | Apache-2.0 | 免 root 拿到 shell 权限 |

---

## 关于 vendored 的补丁

`third_party/flutter_inappwebview_android/` 是 `flutter_inappwebview_android` 1.1.3 的副本，
带**一处本地补丁**。

**原因**：该版本 `android/build.gradle` 使用了 AGP 9 已移除的

```
getDefaultProguardFile('proguard-android.txt')
```

导致构建直接失败。上游没有兼容 AGP 9 的版本，而本项目的构建链沿用已验证的 AGP 9.1.0。

**补丁内容**：`android/build.gradle` 里两处
`proguard-android.txt` → `proguard-android-optimize.txt`

**合规性**：该插件为 Apache-2.0 许可，允许修改和再分发。
副本保留了原有的 `LICENSE` 与 `CHANGELOG.md`。详细说明在
`third_party/flutter_inappwebview_android/VENDORED.md`。

> 升级该插件时需要重新应用同样的补丁，或确认上游已修复后删除该目录
> 并移除 `pubspec.yaml` 中的 `dependency_overrides`。

---

## 参考但不含代码

以下项目**没有**代码进入本仓库，仅作设计参考：

- [agent-web-search](https://github.com/blueewhitee/agent-web-search) ——
  自建搜索服务的 HTTP 接口约定参考。本项目 `lib/core/scrub.dart` 的
  **提示注入清洗思路**受其 Stage 3.5 启发，但实现是独立编写的。
  本项目只实现了它的**客户端**，未包含其服务端代码。
