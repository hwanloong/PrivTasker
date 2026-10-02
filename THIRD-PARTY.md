# 第三方组件与许可

本文件说明本项目**自带**和**没有自带**哪些第三方东西，以及它们的许可。分发前务必读完。

**先说结论**：

- ✅ **代码许可是 MIT**，新引入的依赖全是宽松许可，随 APK 分发没问题
- ⚠️ **字体不行** —— 三款商业字体不随仓库分发。**不过默认方案运行时不用它们**，
  只有「衬线」方案和代码块会用到（见第一节）
- ⚠️ **内嵌的 Python 包会随 APK 分发**，加新包前必须核对许可（见第二节）

---

## 内嵌 Python（Chaquopy）及其捆绑的包

APK 里嵌入了一套 CPython 3.13 运行时（由 Chaquopy 提供），以及若干第三方 Python 包。
**这些都会随 APK 一起分发**，所以许可必须逐个核对。

### 运行时

| 组件 | 许可 | 说明 |
|---|---|---|
| [Chaquopy](https://chaquo.com/chaquopy/) | **MIT** | 12.0.1 起完全开源，无任何许可限制 |
| CPython | PSF License | Python 官方许可，允许分发 |

### 捆绑的 Python 包

以下包在**构建时**由 `android/app/build.gradle.kts` 的 `pip {}` 块装入 APK：

| 包 | 许可 | 用途 |
|---|---|---|
| `python-docx` | MIT | Word 读写 |
| `python-pptx` | MIT | PPT 读写 |
| `openpyxl` | MIT | Excel 读写 |
| `et-xmlfile` | MIT | openpyxl 依赖 |
| `XlsxWriter` | BSD-2-Clause | python-pptx 依赖 |
| `lxml` | BSD-3-Clause | C 扩展，含 Chaquopy 编译的 libxml2 / libxslt |
| `pillow` | MIT-CMU | 图像处理 |
| `requests` | Apache-2.0 | HTTP |
| `beautifulsoup4` | MIT | 网页解析 |
| `soupsieve` | MIT | bs4 依赖 |
| `urllib3` / `idna` / `certifi` / `charset-normalizer` | MIT / BSD / MPL-2.0 / MIT | requests 依赖 |

**全部是宽松许可**，随 APK 分发没有问题。
（`certifi` 是 MPL-2.0，但它不是 copyleft 传染性的，只要求对其自身修改开源。）

> **要新增 Python 包时**：先确认它的许可允许再分发。
> **GPL / AGPL 的包不能随便打进来** —— 那会让整个应用受 copyleft 约束，
> 而本项目的许可声明是 MIT。

---

## ⚠️ 字体：未随仓库分发

界面**默认**用的是 Android 系统族名（`sans-serif` / `monospace`），
**运行时**不加载任何自带字体文件。

但 `pubspec.yaml` 的 `fonts:` 段仍然声明了下面三款字体，**构建时会去找这些文件**，
所以从仓库克隆后必须自行准备（见 `assets/fonts/README.md`）——
也就是说这个仓库**默认构建出来的 APK 是带商业字体的，不能公开分发**。

设置里可切换的「衬线」方案用到前两款：

| 字体 | 权利人 | 用途 |
|---|---|---|
| 字体 | 权利人 | 用途 |
|---|---|---|
| **苹方 PingFang SC** | 苹果 (Apple) | **默认方案的正文（内置）** |
| **Times New Roman** | Monotype | 衬线方案的英文正文 |
| **宋体 SimSun** | 中易中标 / Microsoft | 衬线方案的中文正文 |
| **Consolas** | Microsoft | 代码块 |
| **Consolas** | Microsoft | 三套方案共用的代码块字体 |

> 代码块也用了 Consolas。它是商业字体，所以**只要发出去的 APK 里带了
> `assets/fonts/`，三款都算侵权** —— 与用户选哪套方案无关。
> 想干净地公开分发，就得删掉 `pubspec.yaml` 的 `fonts:` 段、
> 并让代码块回退到 `monospace`。

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

> `extract_ttc.dart` **不在本仓库里**，它在工作区上一层的 `tools/` 下
> （即 `D:\pj3\tools\extract_ttc.dart`）。上面那条命令里的 `..\..\tools\`
> 就是按这个位置写的。

> **为什么要抽而不是直接用 `.ttc`：** Flutter 对 TrueType 集合的支持不明确，
> 最坏情况是加载失败后**静默回退成黑体** —— 界面上中文会变成另一种字体，
> 而这种问题在手机上不容易当场发现。详见 `tools/extract_ttc.dart` 里的说明。

### 苹方：内置为默认方案，但同样不进仓库

苹方（PingFang SC）是**默认字体方案**，所以要放进 `assets/fonts/pingfang.ttf`
并在 `pubspec.yaml` 的 `fonts:` 段声明 —— 它和 Times / 宋体 / Consolas 走同一套约定。

这意味着一个必须说清楚的前提：**Flutter 不支持"可选字体资源"** ——
在 `fonts:` 段里声明了却在打包时找不到文件，构建会**直接失败**。
所以克隆这个仓库的人必须自己准备好这几个字体文件（清单见 `assets/fonts/README.md`），
否则编译不过去。这是本项目一贯的取舍，不是这次新增的负担。

字体文件本身**不进仓库**（`assets/fonts/*.ttf|ttc|otf` 在 `.gitignore` 里），
也不会随仓库分发到别人手上。

### 自定义字体：运行时加载，完全不进构建

设置里还有一套「自定义字体文件」方案，**不在 `pubspec.yaml` 里声明任何资源**，
而是让用户在运行时选一个字体文件（`.ttf` / `.otf` / `.ttc`），由
`lib/core/custom_font.dart` 用 `FontLoader` 注册。

它的好处是**换任何字体都不用改代码重新构建**，也不受上面那个
"声明了就必须存在"的约束。代价是只对**本机这一份安装**生效，
换设备要重新选一次（路径存在 `SharedPreferences`，同设备升级不会丢）。

### 想换成可自由分发的字体

如果打算公开分发带字体的构建产物，需要换成开源字体。功能等价的选择：

| 用途 | 开源替代 | 许可 |
|---|---|---|
| 中文宋体 / 明朝体 | [Source Han Serif](https://github.com/adobe-fonts/source-han-serif)（思源宋体） | SIL OFL 1.1 |
| 英文衬线 | [EB Garamond](https://github.com/octaviopardo/EBGaramond12) / [Linux Libertine](https://github.com/alerque/libertinus) | SIL OFL 1.1 |
| 等宽 | [JetBrains Mono](https://github.com/JetBrains/JetBrainsMono) | SIL OFL 1.1 |

换字体只需要改 `pubspec.yaml` 的 `fonts:` 段和 `lib/theme/app_theme.dart` 里
`AppFonts.applyScheme()` 中的家族名 —— 全项目只有这两处引用字体名。

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
