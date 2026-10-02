# 字体目录（需自行准备）

**这个目录里的字体文件不随仓库分发。**

本目录在 `.gitignore` 中被排除。**请按下文自行准备，否则构建会因为找不到字体资源而失败。**

> **为什么必须放：** 即使界面**默认**用的是 Android 系统族名
> （`sans-serif` / `monospace`）、运行时根本不加载这里的文件，
> `pubspec.yaml` 的 `fonts:` 段**仍然声明了**这些资源路径。
> Flutter 打包时会逐个去找，找不到就直接报错 —— 它不支持"可选字体资源"。
>
> 也就是说：**默认方案不需要这些字体，但这个仓库的构建需要。** 两件事不一样。
>
> 想彻底摆脱这个依赖，就得把 `pubspec.yaml` 的 `fonts:` 段整个删掉，
> 代价是设置里的「衬线」方案会失去 Times / 宋体（回退成系统字体）。

## 需要哪些文件

```
assets/fonts/
├── pingfang.ttf      PingFang SC Regular（苹方，**默认字体方案**）
├── times.ttf         Times New Roman Regular
├── timesbd.ttf       Times New Roman Bold
├── timesi.ttf        Times New Roman Italic
├── timesbi.ttf       Times New Roman Bold Italic
├── simsun.ttf        宋体（从 simsun.ttc 抽出的独立 TTF）
├── consola.ttf       Consolas Regular
├── consolab.ttf      Consolas Bold
└── consolai.ttf      Consolas Italic
```

> **苹方是默认字体方案**，所以缺了它界面会回退到系统字体（不会崩，
> 但看不到预期的观感）。它是苹果的系统字体，最早只在 macOS 上。
>
> `PingFang.ttc` 是**字体集合**（一个文件装多个字重），Flutter 对 `.ttc`
> 支持不确定 —— 先用 `extract_ttc.dart` 抽成单个 `.ttf` 再放进来。
> 抽出来应该是 `00 01 00 00` 开头的合法 sfnt，约 11 MB。
>
> 只放 **Regular** 一个字重就够：苹方每个字重约 11 MB，6 个字重全带会让
> APK 多出 60 MB。粗体由 Flutter 合成，对这种黑体观感可以接受。

## 为什么要自己准备

这几款字体都是**商业专有字体**：

| 字体 | 权利人 |
|---|---|
| 苹方 PingFang SC | 苹果 (Apple) |
| Times New Roman | Monotype |
| 宋体 SimSun | 中易中标 / Microsoft |
| Consolas | Microsoft |

它们随各自的操作系统授权给**本机使用者**，但授权范围**不包括再分发**。
把它们提交到公开仓库或公开分发带字体的构建产物都属于侵权。

在你自己的机器上使用属于正常的系统授权范围。

## 准备方法

```powershell
cd assets/fonts

# Times New Roman 与 Consolas：单文件，直接复制
Copy-Item C:\Windows\Fonts\times.ttf    .
Copy-Item C:\Windows\Fonts\timesbd.ttf  .
Copy-Item C:\Windows\Fonts\timesi.ttf   .
Copy-Item C:\Windows\Fonts\timesbi.ttf  .
Copy-Item C:\Windows\Fonts\consola.ttf  .
Copy-Item C:\Windows\Fonts\consolab.ttf .
Copy-Item C:\Windows\Fonts\consolai.ttf .

# 宋体：Windows 上是 TrueType 集合（.ttc），需要抽成独立 TTF
Copy-Item C:\Windows\Fonts\simsun.ttc .
dart ..\..\tools\extract_ttc.dart simsun.ttc simsun.ttf 0
Remove-Item simsun.ttc
```

### 校验

```powershell
Get-ChildItem | Select-Object Name, @{n='KB';e={[math]::Round($_.Length/1KB)}}
```

`simsun.ttf` 应该是 **约 17.5 MB**。前 4 个字节应为 `00 01 00 00`（合法 sfnt 头）：

```powershell
Format-Hex simsun.ttf -Count 4
```

也可以先看集合里有哪些字体：

```powershell
dart ..\..\tools\extract_ttc.dart simsun.ttc --list
```

应该输出两个：`[0] family="SimSun"` 和 `[1] family="NSimSun"`。取索引 0。

## 为什么宋体要抽出来

`simsun.ttc` 是 TrueType **集合**文件（一个文件装多个字体），而 Flutter 对 `.ttc`
的支持不明确。最坏的情况是**加载失败后静默回退**到系统默认字体 ——
界面上中文会变成黑体，而这种问题在手机上不容易当场发现。

抽成独立的 `.ttf` 就消除了这个不确定性。细节见 `tools/extract_ttc.dart` 的注释。

## 想用开源字体替代

如果打算公开分发带字体的构建产物，需要换成可自由分发的字体。推荐：

| 用途 | 替代 | 许可 |
|---|---|---|
| 中文宋体/明朝体 | [思源宋体 Source Han Serif](https://github.com/adobe-fonts/source-han-serif) | SIL OFL 1.1 |
| 英文衬线 | [EB Garamond](https://github.com/octaviopardo/EBGaramond12) | SIL OFL 1.1 |
| 等宽 | [JetBrains Mono](https://github.com/JetBrains/JetBrainsMono) | SIL OFL 1.1 |

换字体只需改两处：

1. `pubspec.yaml` 的 `fonts:` 段（资源路径与家族名）
2. `lib/theme/app_theme.dart` 的 `AppFonts.applyScheme()`（三个方案的家族名）

全项目只有这两处引用字体名。
